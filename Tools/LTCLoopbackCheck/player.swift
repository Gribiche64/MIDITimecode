import AVFoundation
import CoreAudio
import Foundation

// Usage: player <wav> <output device name>
let args = CommandLine.arguments
guard args.count == 3 else { print("usage: player <wav> <device>"); exit(2) }
let url = URL(fileURLWithPath: args[1])
let wanted = args[2]

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

guard let dev = deviceID(named: wanted) else { print("device not found: \(wanted)"); exit(1) }
let engine = AVAudioEngine()
let output = engine.outputNode
guard let unit = output.audioUnit else { print("no output unit"); exit(1) }
var devID = dev
let st = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &devID, UInt32(MemoryLayout<AudioDeviceID>.size))
guard st == noErr else { print("set device failed \(st)"); exit(1) }

let file = try AVAudioFile(forReading: url)
let player = AVAudioPlayerNode()
engine.attach(player)
engine.connect(player, to: engine.mainMixerNode, format: file.processingFormat)
try engine.start()
player.scheduleFile(file, at: nil)
player.play()
let started = Date()
print("playing \(url.lastPathComponent) to \(wanted) at \(started)")
let duration = Double(file.length) / file.processingFormat.sampleRate
Thread.sleep(forTimeInterval: duration + 0.5)
player.stop(); engine.stop()
print("done")
