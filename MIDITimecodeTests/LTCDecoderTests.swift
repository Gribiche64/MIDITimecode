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
        // Bit 59: polarity correction — false
        // User bits field 8 (bits 60-63) — zeros

        // Sync word (bits 64-79): 0011 1111 1111 1101
        let syncWord: UInt16 = 0x3FFD
        for b in 0..<16 {
            bits[64 + b] = ((syncWord >> b) & 1) == 1
        }

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

    func testDecodeZeroTimecode() {
        var decoder = LTCDecoder()
        let samples = synthesiseWithPreamble(
            hours: 0, minutes: 0, seconds: 0, frames: 0
        )

        var decoded: [Timecode] = []
        samples.withUnsafeBufferPointer { buffer in
            decoded = decoder.processSamples(buffer, sampleRate: 48000.0)
        }

        XCTAssertFalse(decoded.isEmpty, "Expected at least one decoded frame")
        if let first = decoded.first {
            XCTAssertEqual(first.displayString, "00:00:00:00")
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

    // MARK: - Lock State

    func testIsLockedAfterDecode() {
        var decoder = LTCDecoder()
        let samples = synthesiseWithPreamble(
            hours: 0, minutes: 0, seconds: 0, frames: 0
        )

        samples.withUnsafeBufferPointer { buffer in
            _ = decoder.processSamples(buffer, sampleRate: 48000.0)
        }

        XCTAssertTrue(decoder.isLocked)
    }
}
