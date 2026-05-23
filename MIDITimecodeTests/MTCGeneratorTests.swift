import XCTest
@testable import MIDITimecode

final class MTCGeneratorTests: XCTestCase {

    let generator = MTCGenerator()

    // MARK: - Round-trip through MTCParser

    func testRoundTrip25fps() {
        let tc = Timecode(hours: 1, minutes: 23, seconds: 45, frames: 12, rate: .fps25)
        let bytes = generator.allQuarterFrameDataBytes(for: tc)

        var parser = MTCParser()
        for byte in bytes {
            parser.processQuarterFrame(byte)
        }

        XCTAssertEqual(parser.hours, tc.hours)
        XCTAssertEqual(parser.minutes, tc.minutes)
        XCTAssertEqual(parser.seconds, tc.seconds)
        XCTAssertEqual(parser.frames, tc.frames)
        XCTAssertEqual(parser.frameRate, "25 fps")
    }

    func testRoundTrip24fps() {
        let tc = Timecode(hours: 0, minutes: 0, seconds: 0, frames: 23, rate: .fps24)
        let bytes = generator.allQuarterFrameDataBytes(for: tc)

        var parser = MTCParser()
        for byte in bytes {
            parser.processQuarterFrame(byte)
        }

        XCTAssertEqual(parser.hours, 0)
        XCTAssertEqual(parser.frames, 23)
        XCTAssertEqual(parser.frameRate, "24 fps")
    }

    func testRoundTrip2997DF() {
        let tc = Timecode(hours: 10, minutes: 30, seconds: 0, frames: 2, rate: .df2997)
        let bytes = generator.allQuarterFrameDataBytes(for: tc)

        var parser = MTCParser()
        for byte in bytes {
            parser.processQuarterFrame(byte)
        }

        XCTAssertEqual(parser.hours, 10)
        XCTAssertEqual(parser.minutes, 30)
        XCTAssertEqual(parser.seconds, 0)
        XCTAssertEqual(parser.frames, 2)
        XCTAssertEqual(parser.frameRate, "29.97 fps (DF)")
    }

    func testRoundTrip30fps() {
        let tc = Timecode(hours: 23, minutes: 59, seconds: 59, frames: 29, rate: .fps30)
        let bytes = generator.allQuarterFrameDataBytes(for: tc)

        var parser = MTCParser()
        for byte in bytes {
            parser.processQuarterFrame(byte)
        }

        XCTAssertEqual(parser.hours, 23)
        XCTAssertEqual(parser.minutes, 59)
        XCTAssertEqual(parser.seconds, 59)
        XCTAssertEqual(parser.frames, 29)
        XCTAssertEqual(parser.frameRate, "30 fps")
    }

    func testRoundTripZero() {
        let tc = Timecode.zero
        let bytes = generator.allQuarterFrameDataBytes(for: tc)

        var parser = MTCParser()
        for byte in bytes {
            parser.processQuarterFrame(byte)
        }

        XCTAssertEqual(parser.timecode, "00:00:00:00")
    }

    // MARK: - Message format

    func testQuarterFrameMessageFormat() {
        let tc = Timecode(hours: 1, minutes: 0, seconds: 0, frames: 0, rate: .fps25)
        for i in 0..<8 {
            let msg = generator.quarterFrameMessage(index: i, timecode: tc)
            XCTAssertEqual(msg.count, 2)
            XCTAssertEqual(msg[0], 0xF1)

            // Verify message type is encoded in high nibble of data byte
            let messageType = (msg[1] >> 4) & 0x07
            XCTAssertEqual(messageType, UInt8(i))
        }
    }

    // MARK: - Rate code encoding

    func testAllRateCodesEncoded() {
        for rate in FrameRate.allCases {
            let tc = Timecode(hours: 0, minutes: 0, seconds: 0, frames: 0, rate: rate)
            let bytes = generator.allQuarterFrameDataBytes(for: tc)

            // Message type 7 contains the rate code
            let msg7 = bytes[7]
            let nibble = msg7 & 0x0F
            let encodedRate = (nibble >> 1) & 0x03
            XCTAssertEqual(encodedRate, rate.mtcRateCode, "Rate code mismatch for \(rate)")
        }
    }

    // MARK: - 8 bytes produced

    func testAlwaysProduces8Bytes() {
        let tc = Timecode(hours: 12, minutes: 34, seconds: 56, frames: 7, rate: .fps25)
        let bytes = generator.allQuarterFrameDataBytes(for: tc)
        XCTAssertEqual(bytes.count, 8)
    }
}
