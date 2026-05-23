import XCTest
@testable import MIDITimecode

final class MTCParserTests: XCTestCase {

    // MARK: - Helpers

    /// Builds an MTC quarter-frame data byte from message type (0-7) and nibble value (0-15).
    private func qf(_ messageType: UInt8, _ nibble: UInt8) -> UInt8 {
        (messageType << 4) | (nibble & 0x0F)
    }

    /// Feeds all 8 quarter-frame messages encoding the given timecode and frame rate.
    /// Rate codes: 0 = 24fps, 1 = 25fps, 2 = 29.97 DF, 3 = 30fps.
    @discardableResult
    private func feedFullFrame(
        _ parser: inout MTCParser,
        hours: UInt8, minutes: UInt8, seconds: UInt8, frames: UInt8,
        rateCode: UInt8 = 0
    ) -> Bool {
        let framesLS = frames & 0x0F
        let framesMS = (frames >> 4) & 0x0F
        let secsLS = seconds & 0x0F
        let secsMS = (seconds >> 4) & 0x0F
        let minsLS = minutes & 0x0F
        let minsMS = (minutes >> 4) & 0x0F
        let hrsLS = hours & 0x0F
        let hrsMS = ((rateCode & 0x03) << 1) | ((hours >> 4) & 0x01)

        var completed = false
        completed = parser.processQuarterFrame(qf(0, framesLS)) || completed
        completed = parser.processQuarterFrame(qf(1, framesMS)) || completed
        completed = parser.processQuarterFrame(qf(2, secsLS)) || completed
        completed = parser.processQuarterFrame(qf(3, secsMS)) || completed
        completed = parser.processQuarterFrame(qf(4, minsLS)) || completed
        completed = parser.processQuarterFrame(qf(5, minsMS)) || completed
        completed = parser.processQuarterFrame(qf(6, hrsLS)) || completed
        completed = parser.processQuarterFrame(qf(7, hrsMS)) || completed
        return completed
    }

    // MARK: - Initial State

    func testInitialTimecodeIsZeroed() {
        let parser = MTCParser()
        XCTAssertEqual(parser.timecode, "00:00:00:00")
        XCTAssertEqual(parser.frameRate, "")
    }

    // MARK: - Full Frame Assembly

    func testBasicTimecodeAssembly() {
        var parser = MTCParser()
        let completed = feedFullFrame(&parser, hours: 1, minutes: 23, seconds: 45, frames: 12)

        XCTAssertTrue(completed)
        XCTAssertEqual(parser.hours, 1)
        XCTAssertEqual(parser.minutes, 23)
        XCTAssertEqual(parser.seconds, 45)
        XCTAssertEqual(parser.frames, 12)
        XCTAssertEqual(parser.timecode, "01:23:45:12")
    }

    func testZeroTimecode() {
        var parser = MTCParser()
        feedFullFrame(&parser, hours: 0, minutes: 0, seconds: 0, frames: 0)
        XCTAssertEqual(parser.timecode, "00:00:00:00")
    }

    func testMaxBoundaryValues() {
        var parser = MTCParser()
        feedFullFrame(&parser, hours: 23, minutes: 59, seconds: 59, frames: 29, rateCode: 3)

        XCTAssertEqual(parser.hours, 23)
        XCTAssertEqual(parser.minutes, 59)
        XCTAssertEqual(parser.seconds, 59)
        XCTAssertEqual(parser.frames, 29)
        XCTAssertEqual(parser.timecode, "23:59:59:29")
    }

    // MARK: - Frame Rate Detection

    func testFrameRate24() {
        var parser = MTCParser()
        feedFullFrame(&parser, hours: 0, minutes: 0, seconds: 0, frames: 0, rateCode: 0)
        XCTAssertEqual(parser.frameRate, "24 fps")
    }

    func testFrameRate25() {
        var parser = MTCParser()
        feedFullFrame(&parser, hours: 0, minutes: 0, seconds: 0, frames: 0, rateCode: 1)
        XCTAssertEqual(parser.frameRate, "25 fps")
    }

    func testFrameRate2997DF() {
        var parser = MTCParser()
        feedFullFrame(&parser, hours: 0, minutes: 0, seconds: 0, frames: 0, rateCode: 2)
        XCTAssertEqual(parser.frameRate, "29.97 fps (DF)")
    }

    func testFrameRate30() {
        var parser = MTCParser()
        feedFullFrame(&parser, hours: 0, minutes: 0, seconds: 0, frames: 0, rateCode: 3)
        XCTAssertEqual(parser.frameRate, "30 fps")
    }

    // MARK: - Partial Frames

    func testPartialFrameDoesNotComplete() {
        var parser = MTCParser()

        XCTAssertFalse(parser.processQuarterFrame(qf(0, 0)))
        XCTAssertFalse(parser.processQuarterFrame(qf(1, 0)))
        XCTAssertFalse(parser.processQuarterFrame(qf(2, 5)))
        XCTAssertFalse(parser.processQuarterFrame(qf(3, 0)))
        XCTAssertFalse(parser.processQuarterFrame(qf(4, 3)))
        XCTAssertFalse(parser.processQuarterFrame(qf(5, 0)))
        XCTAssertFalse(parser.processQuarterFrame(qf(6, 1)))

        // Still showing initial state — no message type 7 received
        XCTAssertEqual(parser.timecode, "00:00:00:00")
    }

    func testMessageType7Completes() {
        var parser = MTCParser()

        for i: UInt8 in 0..<7 {
            parser.processQuarterFrame(qf(i, 0))
        }
        let completed = parser.processQuarterFrame(qf(7, 0))
        XCTAssertTrue(completed)
    }

    // MARK: - Consecutive Frames

    func testConsecutiveFramesUpdateCorrectly() {
        var parser = MTCParser()

        feedFullFrame(&parser, hours: 1, minutes: 0, seconds: 0, frames: 0)
        XCTAssertEqual(parser.timecode, "01:00:00:00")

        feedFullFrame(&parser, hours: 1, minutes: 0, seconds: 0, frames: 1)
        XCTAssertEqual(parser.timecode, "01:00:00:01")

        feedFullFrame(&parser, hours: 2, minutes: 30, seconds: 15, frames: 24)
        XCTAssertEqual(parser.timecode, "02:30:15:24")
    }

    // MARK: - Clamping

    func testSecondsClampedTo59() {
        var parser = MTCParser()
        // Manually feed nibbles that encode seconds = 63 (0x3F)
        parser.processQuarterFrame(qf(0, 0))
        parser.processQuarterFrame(qf(1, 0))
        parser.processQuarterFrame(qf(2, 0x0F)) // seconds LS = 15
        parser.processQuarterFrame(qf(3, 0x03)) // seconds MS = 3 → seconds = 63
        parser.processQuarterFrame(qf(4, 0))
        parser.processQuarterFrame(qf(5, 0))
        parser.processQuarterFrame(qf(6, 0))
        parser.processQuarterFrame(qf(7, 0))

        XCTAssertEqual(parser.seconds, 59)
    }

    func testMinutesClampedTo59() {
        var parser = MTCParser()
        parser.processQuarterFrame(qf(0, 0))
        parser.processQuarterFrame(qf(1, 0))
        parser.processQuarterFrame(qf(2, 0))
        parser.processQuarterFrame(qf(3, 0))
        parser.processQuarterFrame(qf(4, 0x0F)) // minutes LS = 15
        parser.processQuarterFrame(qf(5, 0x03)) // minutes MS = 3 → minutes = 63
        parser.processQuarterFrame(qf(6, 0))
        parser.processQuarterFrame(qf(7, 0))

        XCTAssertEqual(parser.minutes, 59)
    }

    // MARK: - Nibble Assembly

    func testNibbleAssemblyForAllFields() {
        var parser = MTCParser()
        // Encode: 10:20:30:15 at 25fps (rate code 1)
        // frames=15 → LS=0xF, MS=0x0
        // seconds=30 → LS=0xE, MS=0x1
        // minutes=20 → LS=0x4, MS=0x1
        // hours=10  → LS=0xA, MS= (rateCode<<1)|((hours>>4)&1) = (1<<1)|0 = 0x2
        feedFullFrame(&parser, hours: 10, minutes: 20, seconds: 30, frames: 15, rateCode: 1)

        XCTAssertEqual(parser.hours, 10)
        XCTAssertEqual(parser.minutes, 20)
        XCTAssertEqual(parser.seconds, 30)
        XCTAssertEqual(parser.frames, 15)
        XCTAssertEqual(parser.frameRate, "25 fps")
        XCTAssertEqual(parser.timecode, "10:20:30:15")
    }

    // MARK: - Timecode Formatting

    func testTimecodeStringPadding() {
        var parser = MTCParser()
        feedFullFrame(&parser, hours: 0, minutes: 1, seconds: 2, frames: 3)
        XCTAssertEqual(parser.timecode, "00:01:02:03")
    }
}
