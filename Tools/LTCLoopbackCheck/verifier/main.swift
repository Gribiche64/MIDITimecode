import AVFoundation
import CoreAudio
import CoreMIDI
import Foundation

// Independent MTC reader + LTC decoder.
// Usage: verifier <midi source name> <audio device name> <seconds>
// Listens to the MTC stream and decodes the LTC from the audio device itself,
// then reports how the MTC position compares with the LTC-derived position at
// the same host time, plus quarter-frame continuity, Full Frames and gaps.

let args = CommandLine.arguments
guard args.count == 4, let seconds = Double(args[3]) else { print("usage: verifier <source> <device> <seconds>"); exit(2) }
let sourceName = args[1], deviceName = args[2]

func deviceID(named name: String) -> AudioDeviceID? {
    var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size)
    var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
    AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids)
    for id in ids {
        var nameAddr = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var cf: CFString = "" as CFString
        var s = UInt32(MemoryLayout<CFString>.size)
        if AudioObjectGetPropertyData(id, &nameAddr, 0, nil, &s, &cf) == noErr, (cf as String) == name { return id }
    }
    return nil
}

// ---- Shared state (single lock) ----
let lock = NSLock()
struct LTCRef { let index: Int; let end: Double; let rate: FrameRate }
var ltcRefs: [LTCRef] = []          // decoded LTC frames (position index+1 starts at end)
var ltcDecodedCount = 0
var ltcFirst: Timecode?, ltcLast: Timecode?
var mtcSamples: [(time: Double, offsetFrames: Double, tc: Timecode)] = []
var restarts = 0, qfCount = 0, lastQFIndex = -1, lastQFTime: Double?
var qfGaps: [(time: Double, gap: Double)] = []
var qfIntervals: [Double] = []
var fullFrames: [(time: Double, tc: Timecode)] = []
var unmatched = 0
var groupStartTime: Double?
var ltcJumps: [(time: Double, from: Timecode, to: Timecode)] = []
var ltcGaps: [(time: Double, gap: Double)] = []
var lastLTCEnd: Double?
var lateness: [Double] = []   // callback time minus packet stamp, per packet
var tapCallbacks = 0
var tapPeak: Float = 0
var t0 = HostTime.now()

func ltcPosition(at t: Double) -> (Double, FrameRate)? {
    // Use the latest LTC frame that ended at or before t (or the nearest).
    guard let ref = ltcRefs.last(where: { $0.end <= t }) ?? ltcRefs.last else { return nil }
    return (Double(ref.index + 1) + (t - ref.end) / ref.rate.frameDuration, ref.rate)
}

// ---- Audio: decode LTC on channel 0 ----
guard let dev = deviceID(named: deviceName) else { print("audio device not found: \(deviceName)"); exit(1) }
let engine = AVAudioEngine()
let input = engine.inputNode
guard let unit = input.audioUnit else { print("no input unit"); exit(1) }
AudioUnitUninitialize(unit)
var devID = dev
guard AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &devID, UInt32(MemoryLayout<AudioDeviceID>.size)) == noErr else { print("set input device failed"); exit(1) }
AudioUnitInitialize(unit)
let hw = input.outputFormat(forBus: 0)
// Same explicit tap format the app uses; the raw hardware format sometimes
// leaves the engine "started" but not running.
guard let tapFormat = AVAudioFormat(standardFormatWithSampleRate: hw.sampleRate, channels: 2) else { print("no tap format"); exit(1) }
var decoder = LTCDecoder()
var lastLTCReport = 0.0
input.installTap(onBus: 0, bufferSize: 1024, format: tapFormat) { buffer, when in
    guard let data = buffer.floatChannelData else { return }
    let n = Int(buffer.frameLength)
    let sr = buffer.format.sampleRate
    lock.lock()
    tapCallbacks += 1
    for i in 0..<n { tapPeak = max(tapPeak, abs(data[0][i])) }
    lock.unlock()
    let start = when.isHostTimeValid ? HostTime.seconds(fromTicks: when.hostTime) : HostTime.now() - Double(n) / sr
    let frames = decoder.decode(UnsafeBufferPointer(start: data[0], count: n), sampleRate: sr)
    guard !frames.isEmpty else { return }
    lock.lock()
    for f in frames {
        ltcDecodedCount += 1
        if ltcFirst == nil { ltcFirst = f.timecode }
        let end = start + Double(f.sampleOffset + 1) / sr
        if let last = ltcLast, f.timecode.frameIndex != last.frameIndex + 1 { ltcJumps.append((end - t0, last, f.timecode)) }
        if let le = lastLTCEnd, end - le > 0.1 { ltcGaps.append((le - t0, end - le)) }
        lastLTCEnd = end
        ltcLast = f.timecode
        ltcRefs.append(LTCRef(index: f.timecode.frameIndex, end: end, rate: f.timecode.rate))
        if ltcRefs.count > 200 { ltcRefs.removeFirst(100) }
    }
    lock.unlock()
}
// Switching the AUHAL device posts a configuration change that can stop the
// engine just after start; settle, start, and restart until it stays up.
Thread.sleep(forTimeInterval: 0.5)
engine.prepare()
try engine.start()
for attempt in 1...5 {
    Thread.sleep(forTimeInterval: 0.4)
    if engine.isRunning { break }
    print("engine stopped after start, restart \(attempt)")
    engine.stop(); engine.prepare(); try engine.start()
}
var cur: AudioDeviceID = 0; var csz = UInt32(MemoryLayout<AudioDeviceID>.size)
AudioUnitGetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &cur, &csz)
print("audio: wanted device \(dev), AUHAL now on \(cur), engine running \(engine.isRunning)")

// ---- MIDI: read MTC ----
var client = MIDIClientRef(); MIDIClientCreateWithBlock("verifier" as CFString, &client, nil)
var source: MIDIEndpointRef = 0
for i in 0..<MIDIGetNumberOfSources() {
    var name: Unmanaged<CFString>?
    MIDIObjectGetStringProperty(MIDIGetSource(i), kMIDIPropertyName, &name)
    if (name?.takeRetainedValue() as String?) == sourceName { source = MIDIGetSource(i); break }
}
guard source != 0 else { print("MIDI source not found: \(sourceName)"); exit(1) }
var parser = MTCParser()
var port = MIDIPortRef()
MIDIInputPortCreateWithBlock(client, "in" as CFString, &port) { list, _ in
    let arrivalNow = HostTime.now()
    var packet = list.pointee.packet
    for _ in 0..<list.pointee.numPackets {
        let bytes = withUnsafeBytes(of: packet.data) { Array($0.prefix(Int(packet.length))) }
        let stamp = packet.timeStamp == 0 ? arrivalNow : HostTime.seconds(fromTicks: packet.timeStamp)
        lock.lock()
        lateness.append(arrivalNow - stamp)
        var i = 0
        while i < bytes.count {
            if bytes[i] == 0xF1, i + 1 < bytes.count {
                let d = bytes[i + 1]; let idx = Int((d >> 4) & 7)
                qfCount += 1
                if lastQFIndex >= 0 && idx != (lastQFIndex + 1) % 8 { restarts += 1 }
                if let lt = lastQFTime {
                    let gap = stamp - lt
                    qfIntervals.append(gap)
                    if gap > 0.05 { qfGaps.append((stamp - t0, gap)) }
                }
                lastQFIndex = idx; lastQFTime = stamp
                if idx == 0 { groupStartTime = stamp }
                if parser.processQuarterFrame(d), let tc = parser.assembledTimecode {
                    // The group encodes the time at its first message: compare
                    // the encoded value with the LTC position at that moment.
                    if let qf0 = groupStartTime, let (ltcPos, _) = ltcPosition(at: qf0) {
                        mtcSamples.append((qf0 - t0, Double(tc.frameIndex) - ltcPos, tc))
                    } else { unmatched += 1 }
                }
                i += 2
            } else if bytes[i] == 0xF0, bytes.count - i >= 10, bytes[i+1] == 0x7F, bytes[i+3] == 0x01, bytes[i+4] == 0x01 {
                let rate = FrameRate(mtcRateCode: (bytes[i+5] >> 5) & 3) ?? .fps30
                let tc = Timecode(hours: bytes[i+5] & 0x1F, minutes: bytes[i+6], seconds: bytes[i+7], frames: bytes[i+8], rate: rate)
                fullFrames.append((stamp - t0, tc))
                lastQFIndex = -1  // a Full Frame legitimately restarts the sequence
                i += 10
            } else { i += 1 }
        }
        lock.unlock()
        packet = MIDIPacketNext(&packet).pointee
    }
}
MIDIPortConnectSource(port, source, nil)
print("verifier: listening to '\(sourceName)', decoding LTC from '\(deviceName)' @ \(hw.sampleRate) Hz for \(seconds) s")
t0 = HostTime.now()
Thread.sleep(forTimeInterval: seconds)
engine.stop()

// ---- Report ----
lock.lock()
print("\n=== LTC (independent decode) ===")
print("audio tap: \(tapCallbacks) buffers, peak \(tapPeak), format \(hw)")
print("frames decoded: \(ltcDecodedCount)  first: \(ltcFirst?.displayString ?? "-") \(ltcFirst?.rate.rawValue ?? "")  last: \(ltcLast?.displayString ?? "-")")
print("LTC discontinuities (value not previous+1): \(ltcJumps.count)")
for j in ltcJumps { print(String(format: "   at %.2f s: %@ -> %@", j.time, j.from.displayString, j.to.displayString)) }
print("LTC gaps > 100 ms: \(ltcGaps.count)")
for g in ltcGaps { print(String(format: "   from %.2f s: %.0f ms without decoded frames", g.time, g.gap * 1000)) }
print("\n=== MTC stream ===")
print("quarter-frames: \(qfCount)  sequence restarts (excluding after Full Frame): \(restarts)")
if !qfIntervals.isEmpty {
    let sorted = qfIntervals.sorted()
    let mean = qfIntervals.reduce(0, +) / Double(qfIntervals.count)
    let sd = (qfIntervals.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(qfIntervals.count)).squareRoot()
    print(String(format: "QF interval: mean %.3f ms  sd %.3f ms  min %.3f  max %.3f ms (expected 8.333 ms at 30 fps)", mean * 1000, sd * 1000, sorted.first! * 1000, sorted.last! * 1000))
}
if !lateness.isEmpty {
    let sorted = lateness.sorted()
    let mean = lateness.reduce(0, +) / Double(lateness.count)
    print(String(format: "delivery: callback ran %.3f ms after stamp on average (min %.3f, median %.3f, max %.3f ms) over %d packets",
                 mean * 1000, sorted.first! * 1000, sorted[sorted.count / 2] * 1000, sorted.last! * 1000, lateness.count))
    func pct(_ q: Double) -> Double { sorted[min(sorted.count - 1, Int(Double(sorted.count) * q))] * 1000 }
    print(String(format: "   percentiles: p1 %.3f  p5 %.3f  p95 %.3f  p99 %.3f ms;  |lateness| > 2 ms: %d packets (%.2f%%)",
                 pct(0.01), pct(0.05), pct(0.95), pct(0.99),
                 lateness.filter { abs($0) > 0.002 }.count,
                 100.0 * Double(lateness.filter { abs($0) > 0.002 }.count) / Double(lateness.count)))
}
print("gaps > 50 ms: \(qfGaps.count)")
for g in qfGaps { print(String(format: "   at %.2f s: %.0f ms without quarter-frames", g.time, g.gap * 1000)) }
print("Full Frames: \(fullFrames.count)")
for f in fullFrames { print(String(format: "   at %.2f s: %@", f.time, f.tc.displayString)) }
print("\n=== MTC group value vs LTC position at the group's first message (frames, + = MTC ahead) ===")
print("groups compared: \(mtcSamples.count)  unmatched (no LTC yet): \(unmatched)")
if !mtcSamples.isEmpty {
    let offs = mtcSamples.map { $0.offsetFrames }
    let mean = offs.reduce(0, +) / Double(offs.count)
    let sd = (offs.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(offs.count)).squareRoot()
    let maxAbs = offs.map { abs($0) }.max()!
    print(String(format: "offset: mean %+.3f  sd %.3f  max|offset| %.3f frames", mean, sd, maxAbs))
    let over = mtcSamples.filter { abs($0.offsetFrames) >= 1.0 }
    print("groups with |offset| >= 1 frame: \(over.count)")
    for o in over.prefix(20) { print(String(format: "   at %.2f s: MTC %@ offset %+.2f", o.time, o.tc.displayString, o.offsetFrames)) }
    print("\nfirst/last samples:")
    for s in mtcSamples.prefix(3) + mtcSamples.suffix(3) { print(String(format: "   %.2f s  %@  %+.3f", s.time, s.tc.displayString, s.offsetFrames)) }
    // Timeline around the mute (every ~1 s)
    print("\ntimeline (1 s steps):")
    var next = 0.0
    for s in mtcSamples where s.time >= next { print(String(format: "   %5.1f s  %@  %+.3f", s.time, s.tc.displayString, s.offsetFrames)); next += 1 }
}
lock.unlock()
