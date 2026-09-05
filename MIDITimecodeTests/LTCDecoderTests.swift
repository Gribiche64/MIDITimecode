import XCTest
@testable import MIDITimecode

final class LTCDecoderTests: XCTestCase {

    // MARK: - LTC Audio Synthesiser

    /// Generate biphase-mark-encoded audio samples for a single LTC frame.
    private func synthesiseLTCFrame(
        hours: UInt8, minutes: UInt8, seconds: UInt8, frames: UInt8,
        dropFrame: Bool = false,
        sampleRate: Double = 48000.0,
        fps: Int = 25
    ) -> [Float] {
        // Build the 80-bit LTC frame
        var bits = [Bool](repeating: false, count: 80)

        // Frame units (bits 0-3)
        let frameUnits = frames % 10
        let frameTens = frames / 10
        for b in 0..<4 { bits[b] = ((frameUnits >> b) & 1) == 1 }

        // User bits field 1 (bits 4-7) — zeros
        // Frame tens (bits 8-9)
        for b in 0..<2 { bits[8 + b] = ((frameTens >> b) & 1) == 1 }

        // Drop frame flag (bit 10)
        bits[10] = dropFrame

        // Color frame (bit 11) — false
        // User bits field 2 (bits 12-15) — zeros

        // Seconds units (bits 16-19)
        let secUnits = seconds % 10
        let secTens = seconds / 10
        for b in 0..<4 { bits[16 + b] = ((secUnits >> b) & 1) == 1 }

        // User bits field 3 (bits 20-23) — zeros

        // Seconds tens (bits 24-26)
        for b in 0..<3 { bits[24 + b] = ((secTens >> b) & 1) == 1 }

        // Bit 27: biphase correction — false
        // User bits field 4 (bits 28-31) — zeros

        // Minutes units (bits 32-35)
        let minUnits = minutes % 10
        let minTens = minutes / 10
        for b in 0..<4 { bits[32 + b] = ((minUnits >> b) & 1) == 1 }

        // User bits field 5 (bits 36-39) — zeros

        // Minutes tens (bits 40-42)
        for b in 0..<3 { bits[40 + b] = ((minTens >> b) & 1) == 1 }

        // Bit 43: binary group flag — false
        // User bits field 6 (bits 44-47) — zeros

        // Hours units (bits 48-51)
        let hrUnits = hours % 10
        let hrTens = hours / 10
        for b in 0..<4 { bits[48 + b] = ((hrUnits >> b) & 1) == 1 }

        // User bits field 7 (bits 52-55) — zeros

        // Hours tens (bits 56-57)
        for b in 0..<2 { bits[56 + b] = ((hrTens >> b) & 1) == 1 }

        // Bit 58: binary group flag — false
        // User bits field 8 (bits 60-63) — zeros

        // Sync word (bits 64-79): 0011 1111 1111 1101 (MSB-first in temporal order)
        // Bit 64 is transmitted first = MSB of 0x3FFD
        let syncWord: UInt16 = 0x3FFD
        for b in 0..<16 {
            bits[64 + b] = ((syncWord >> (15 - b)) & 1) == 1
        }

        // Bit 59: polarity correction. Set so the word holds an even number of
        // zeros, which makes every frame end at the level it started on — a
        // biphase-mark stream then has a transition at every frame boundary.
        let zerosElsewhere = bits.enumerated().filter { $0.offset != 59 && !$0.element }.count
        bits[59] = zerosElsewhere % 2 == 0

        // Biphase mark encode
        let samplesPerBit = sampleRate / (Double(fps) * 80.0)
        let halfBit = Int(samplesPerBit / 2.0)
        let fullBit = Int(samplesPerBit)

        var samples: [Float] = []
        var currentLevel: Float = 1.0

        for bit in bits {
            if bit {
                // '1': transition at start, transition at mid-cell
                for _ in 0..<halfBit {
                    samples.append(currentLevel)
                }
                currentLevel = -currentLevel
                for _ in 0..<(fullBit - halfBit) {
                    samples.append(currentLevel)
                }
                currentLevel = -currentLevel
            } else {
                // '0': transition at start only
                for _ in 0..<fullBit {
                    samples.append(currentLevel)
                }
                currentLevel = -currentLevel
            }
        }

        return samples
    }

    /// Generate multiple identical preamble frames followed by target frames.
    /// The preamble lets the decoder establish bit period before the frames we care about.
    private func synthesiseWithPreamble(
        preambleCount: Int = 4,
        hours: UInt8, minutes: UInt8, seconds: UInt8, frames: UInt8,
        dropFrame: Bool = false,
        sampleRate: Double = 48000.0,
        fps: Int = 25
    ) -> [Float] {
        var samples: [Float] = []

        // Preamble frames (same timecode, just to establish lock)
        for _ in 0..<preambleCount {
            samples.append(contentsOf: synthesiseLTCFrame(
                hours: hours, minutes: minutes, seconds: seconds, frames: frames,
                dropFrame: dropFrame, sampleRate: sampleRate, fps: fps
            ))
        }

        // Target frame
        samples.append(contentsOf: synthesiseLTCFrame(
            hours: hours, minutes: minutes, seconds: seconds, frames: frames,
            dropFrame: dropFrame, sampleRate: sampleRate, fps: fps
        ))

        return samples
    }

    // MARK: - Basic Decoding

    func testDecodeBasicFrame() {
        var decoder = LTCDecoder()
        let samples = synthesiseWithPreamble(
            hours: 1, minutes: 23, seconds: 45, frames: 12
        )

        var decoded: [Timecode] = []
        samples.withUnsafeBufferPointer { buffer in
            decoded = decoder.processSamples(buffer, sampleRate: 48000.0)
        }

        XCTAssertFalse(decoded.isEmpty, "Expected at least one decoded frame")

        if let last = decoded.last {
            XCTAssertEqual(last.hours, 1)
            XCTAssertEqual(last.minutes, 23)
            XCTAssertEqual(last.seconds, 45)
            XCTAssertEqual(last.frames, 12)
        }
    }

    func testDecodeVariedTimecode() {
        var decoder = LTCDecoder()
        // Use preambleCount=2 (3 total frames) — matches standalone diagnostic
        let samples = synthesiseWithPreamble(
            hours: 5, minutes: 15, seconds: 30, frames: 10
        )

        var decoded: [Timecode] = []
        samples.withUnsafeBufferPointer { buffer in
            decoded = decoder.processSamples(buffer, sampleRate: 48000.0)
        }

        XCTAssertFalse(decoded.isEmpty, "Expected at least one decoded frame")
        if let last = decoded.last {
            XCTAssertEqual(last.hours, 5)
            XCTAssertEqual(last.minutes, 15)
            XCTAssertEqual(last.seconds, 30)
            XCTAssertEqual(last.frames, 10)
        }
    }

    // MARK: - Drop Frame Detection

    func testDropFrameFlag() {
        var decoder = LTCDecoder()
        let samples = synthesiseWithPreamble(
            hours: 1, minutes: 0, seconds: 0, frames: 2,
            dropFrame: true, fps: 30
        )

        var decoded: [Timecode] = []
        samples.withUnsafeBufferPointer { buffer in
            decoded = decoder.processSamples(buffer, sampleRate: 48000.0)
        }

        XCTAssertFalse(decoded.isEmpty, "Expected at least one decoded frame")
        if let tc = decoded.last {
            XCTAssertEqual(tc.rate, .df2997)
        }
    }

    // MARK: - Signal Level

    func testSignalLevelUpdated() {
        var decoder = LTCDecoder()
        let frame = synthesiseLTCFrame(hours: 0, minutes: 0, seconds: 0, frames: 0)

        frame.withUnsafeBufferPointer { buffer in
            _ = decoder.processSamples(buffer, sampleRate: 48000.0)
        }

        XCTAssertGreaterThan(decoder.signalLevel, 0.0)
    }

    func testNoSignalOnSilence() {
        var decoder = LTCDecoder()
        let silence = [Float](repeating: 0.0, count: 4800)

        silence.withUnsafeBufferPointer { buffer in
            _ = decoder.processSamples(buffer, sampleRate: 48000.0)
        }

        XCTAssertEqual(decoder.signalLevel, 0.0)
        XCTAssertFalse(decoder.isLocked)
    }

    // MARK: - Reset

    func testResetClearsState() {
        var decoder = LTCDecoder()
        let frame = synthesiseLTCFrame(hours: 1, minutes: 0, seconds: 0, frames: 0)

        frame.withUnsafeBufferPointer { buffer in
            _ = decoder.processSamples(buffer, sampleRate: 48000.0)
        }

        decoder.reset()
        XCTAssertNil(decoder.lastTimecode)
        XCTAssertFalse(decoder.isLocked)
        XCTAssertFalse(decoder.isReversing)
        XCTAssertEqual(decoder.signalLevel, 0.0)
    }

    // MARK: - Boundary Values

    func testMaxBoundaryValues() {
        var decoder = LTCDecoder()
        let samples = synthesiseWithPreamble(
            hours: 23, minutes: 59, seconds: 59, frames: 24
        )

        var decoded: [Timecode] = []
        samples.withUnsafeBufferPointer { buffer in
            decoded = decoder.processSamples(buffer, sampleRate: 48000.0)
        }

        XCTAssertFalse(decoded.isEmpty, "Expected at least one decoded frame")
        if let tc = decoded.last {
            XCTAssertEqual(tc.hours, 23)
            XCTAssertEqual(tc.minutes, 59)
            XCTAssertEqual(tc.seconds, 59)
            XCTAssertEqual(tc.frames, 24)
        }
    }

    // MARK: - Sample offsets (used to timestamp frames on the host clock)

    /// Feed a run of consecutive frames and check that each decoded frame is
    /// reported at the sample where its sync word ends.
    private func assertFrameOffsets(fps: Int, sampleRate: Double, file: StaticString = #filePath, line: UInt = #line) {
        var decoder = LTCDecoder()
        let base = Timecode(hours: 4, minutes: 20, seconds: 0, frames: 1, rate: fps == 25 ? .fps25 : .fps30)
        let frameCount = 12
        var samples: [Float] = []
        var frameLengths: [Int] = []
        // One extra trailing frame: a frame only completes once the decoder
        // sees the transition that starts the following frame.
        for n in 0...frameCount {
            let tc = base.advanced(by: n)
            let f = synthesiseLTCFrame(hours: tc.hours, minutes: tc.minutes, seconds: tc.seconds, frames: tc.frames,
                                       sampleRate: sampleRate, fps: fps)
            frameLengths.append(f.count)
            samples += f
        }

        var decoded: [DecodedLTCFrame] = []
        samples.withUnsafeBufferPointer { buffer in
            decoded = decoder.decode(buffer, sampleRate: sampleRate)
        }

        XCTAssertGreaterThanOrEqual(decoded.count, frameCount - 4, "Expected most frames to decode", file: file, line: line)
        XCTAssertTrue(decoder.isLocked, file: file, line: line)

        // Each frame's sync word ends on the last sample of that frame.
        var frameEnds: [Timecode: Int] = [:]
        var end = -1
        for n in 0...frameCount {
            end += frameLengths[n]
            frameEnds[base.advanced(by: n)] = end
        }
        for frame in decoded {
            guard let expected = frameEnds[frame.timecode] else {
                XCTFail("Unexpected timecode \(frame.timecode.displayString)", file: file, line: line)
                continue
            }
            // The Schmitt trigger registers the final transition within a
            // couple of samples of the true edge.
            XCTAssertEqual(frame.sampleOffset, expected, accuracy: 2,
                           "Offset for \(frame.timecode.displayString)", file: file, line: line)
        }
        if let last = decoded.last {
            XCTAssertEqual(last.timecode, base.advanced(by: frameCount - 1), file: file, line: line)
        }
    }

    func testFrameOffsets30fps48k() {
        assertFrameOffsets(fps: 30, sampleRate: 48000)
    }

    func testFrameOffsets25fps48k() {
        assertFrameOffsets(fps: 25, sampleRate: 48000)
    }

    func testFrameOffsets30fps96k() {
        assertFrameOffsets(fps: 30, sampleRate: 96000)
    }

    func testProcessSamplesMatchesDecode() {
        var a = LTCDecoder()
        var b = LTCDecoder()
        let samples = synthesiseWithPreamble(hours: 1, minutes: 2, seconds: 3, frames: 4, fps: 30)
        var viaProcess: [Timecode] = []
        var viaDecode: [DecodedLTCFrame] = []
        samples.withUnsafeBufferPointer { buffer in
            viaProcess = a.processSamples(buffer, sampleRate: 48000)
            viaDecode = b.decode(buffer, sampleRate: 48000)
        }
        XCTAssertEqual(viaProcess, viaDecode.map(\.timecode))
    }

    // MARK: - Dropout recovery

    func testRelocksQuicklyAfterSilenceWithoutSpuriousFrames() {
        let fps = 30
        let sampleRate = 48000.0
        let base = Timecode(hours: 4, minutes: 20, seconds: 0, frames: 1, rate: .fps30)
        var decoder = LTCDecoder()
        var samples: [Float] = []
        var valid = Set<Timecode>()

        func append(_ range: Range<Int>) {
            for n in range {
                let tc = base.advanced(by: n)
                valid.insert(tc)
                samples += synthesiseLTCFrame(hours: tc.hours, minutes: tc.minutes, seconds: tc.seconds,
                                              frames: tc.frames, sampleRate: sampleRate, fps: fps)
            }
        }
        append(0..<15)
        let silenceStart = samples.count
        samples += [Float](repeating: 0, count: Int(sampleRate * 0.5))
        let resume = samples.count
        append(30..<60)

        var decoded: [DecodedLTCFrame] = []
        samples.withUnsafeBufferPointer { buffer in
            decoded = decoder.decode(buffer, sampleRate: sampleRate)
        }

        for frame in decoded {
            XCTAssertTrue(valid.contains(frame.timecode), "Spurious frame \(frame.timecode.displayString)")
            XCTAssertFalse(frame.sampleOffset > silenceStart && frame.sampleOffset < resume,
                           "Frame reported during silence")
        }
        guard let firstAfter = decoded.first(where: { $0.sampleOffset >= resume }) else {
            return XCTFail("Never relocked after the dropout")
        }
        let frameLength = Int(sampleRate) / fps
        let relockFrames = Double(firstAfter.sampleOffset - resume) / Double(frameLength)
        XCTAssertLessThanOrEqual(relockFrames, 3.0, "Relock took \(relockFrames) frames")
        XCTAssertEqual(decoded.last?.timecode, base.advanced(by: 58))
    }

    func testRejectsFramesWithImpossibleFieldValues() {
        var decoder = LTCDecoder()
        // Frame number 29 cannot exist at 25 fps; the sync word is still valid.
        // (The frame-tens field is two bits, so 29 is the largest encodable value.)
        let samples = synthesiseWithPreamble(hours: 1, minutes: 2, seconds: 3, frames: 29, fps: 25)
        var decoded: [Timecode] = []
        samples.withUnsafeBufferPointer { buffer in
            decoded = decoder.processSamples(buffer, sampleRate: 48000)
        }
        XCTAssertTrue(decoded.isEmpty, "Decoded \(decoded.map(\.displayString))")
        XCTAssertFalse(decoder.isLocked)
    }

    // MARK: - Noise immunity

    /// A hot line with no timecode on it: a 7.2 kHz whine plus random hash,
    /// the kind of signal a USB interface delivers when the generator stops.
    /// The decoder must produce nothing.
    func testNoFramesFromLineNoise() {
        let sampleRate = 48000.0
        var samples = [Float](repeating: 0, count: Int(sampleRate * 20))
        var seed: UInt64 = 7
        for i in 0..<samples.count {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let noise = Float(Double(seed >> 11) / Double(1 << 53) * 2 - 1)
            let whine = Float(sin(2 * Double.pi * 7230 * Double(i) / sampleRate))
            samples[i] = 0.15 * (0.8 * whine + 0.6 * noise)
        }
        var decoder = LTCDecoder()
        var decoded: [Timecode] = []
        samples.withUnsafeBufferPointer { buffer in
            decoded = decoder.processSamples(buffer, sampleRate: sampleRate)
        }
        XCTAssertTrue(decoded.isEmpty, "Noise decoded as \(decoded.map(\.displayString))")
        XCTAssertFalse(decoder.isLocked)
    }

    func testNoFramesFromRandomBitsAtLTCRate() {
        // Random biphase bits at a legal LTC rate: sync words appear by chance
        // only with bit errors, which must not be accepted before lock.
        let sampleRate = 48000.0
        let halfBit = 10
        var samples: [Float] = []
        var level: Float = 1
        var seed: UInt64 = 99
        for _ in 0..<(30 * 80 * 20) {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let one = (seed >> 40) & 1 == 1
            if one {
                samples += [Float](repeating: level, count: halfBit); level = -level
                samples += [Float](repeating: level, count: halfBit); level = -level
            } else {
                samples += [Float](repeating: level, count: 2 * halfBit); level = -level
            }
        }
        var decoder = LTCDecoder()
        var decoded: [Timecode] = []
        samples.withUnsafeBufferPointer { buffer in
            decoded = decoder.processSamples(buffer, sampleRate: sampleRate)
        }
        // 20 s of random bits contains an exact sync word by chance about
        // 0.7 times; anything beyond a couple is the tolerant match creeping back.
        XCTAssertLessThanOrEqual(decoded.count, 2, "Random bits decoded as \(decoded.map(\.displayString))")
    }

    // MARK: - Lock State

    func testIsLockedAfterDecode() {
        var decoder = LTCDecoder()
        let samples = synthesiseWithPreamble(
            hours: 2, minutes: 30, seconds: 15, frames: 12
        )

        samples.withUnsafeBufferPointer { buffer in
            _ = decoder.processSamples(buffer, sampleRate: 48000.0)
        }

        XCTAssertTrue(decoder.isLocked)
    }
}
