import XCTest
@testable import MIDITimecode

final class TimecodeMathTests: XCTestCase {

    // MARK: - Non-drop rates

    func testFrameIndexRoundTripNonDrop() {
        for rate in [FrameRate.fps24, .fps25, .fps30] {
            let tc = Timecode(hours: 4, minutes: 20, seconds: 0, frames: 1, rate: rate)
            let index = tc.frameIndex
            XCTAssertEqual(index, (4 * 3600 + 20 * 60) * rate.nominalFPS + 1)
            XCTAssertEqual(Timecode(frameIndex: index, rate: rate), tc)
        }
    }

    func testAdvanceCrossesSecondMinuteAndHour() {
        let tc = Timecode(hours: 0, minutes: 59, seconds: 59, frames: 24, rate: .fps25)
        XCTAssertEqual(tc.advanced(by: 1), Timecode(hours: 1, minutes: 0, seconds: 0, frames: 0, rate: .fps25))
        XCTAssertEqual(tc.advanced(by: 1).advanced(by: -1), tc)
    }

    func testAdvanceWrapsAtMidnight() {
        let tc = Timecode(hours: 23, minutes: 59, seconds: 59, frames: 29, rate: .fps30)
        XCTAssertEqual(tc.advanced(by: 1), Timecode.zero.withRate(.fps30))
        XCTAssertEqual(Timecode.zero.withRate(.fps30).advanced(by: -1), tc)
    }

    // MARK: - Drop frame

    func testDropFrameSkipsFramesZeroAndOneExceptTenthMinutes() {
        var tc = Timecode(hours: 0, minutes: 0, seconds: 0, frames: 0, rate: .df2997)
        // Walk one full hour frame by frame.
        for _ in 0..<(FrameRate.df2997.framesPerTenMinutes * 6) {
            let next = tc.advanced(by: 1)
            if next.seconds == 0 && next.minutes != tc.minutes {
                // Start of a new minute
                if next.minutes % 10 == 0 {
                    XCTAssertEqual(next.frames, 0, "Tenth minute \(next.displayString) must start at frame 00")
                } else {
                    XCTAssertEqual(next.frames, 2, "Minute \(next.displayString) must start at frame 02")
                }
            }
            tc = next
        }
        XCTAssertEqual(tc.hours, 1)
        XCTAssertEqual(tc.minutes, 0)
    }

    func testDropFrameKnownValues() {
        // 00:01:00:02 is the first frame of minute 1 (frames 00 and 01 dropped).
        XCTAssertEqual(Timecode(frameIndex: 1800, rate: .df2997),
                       Timecode(hours: 0, minutes: 1, seconds: 0, frames: 2, rate: .df2997))
        XCTAssertEqual(Timecode(hours: 0, minutes: 1, seconds: 0, frames: 2, rate: .df2997).frameIndex, 1800)
        // 00:10:00:00 begins after 17982 real frames.
        XCTAssertEqual(Timecode(frameIndex: 17982, rate: .df2997),
                       Timecode(hours: 0, minutes: 10, seconds: 0, frames: 0, rate: .df2997))
        // One hour of drop-frame is 107892 frames.
        XCTAssertEqual(Timecode(hours: 1, minutes: 0, seconds: 0, frames: 0, rate: .df2997).frameIndex, 107_892)
    }

    func testDropFrameRoundTripWholeDayIsConsistent() {
        let rate = FrameRate.df2997
        XCTAssertEqual(rate.framesPerDay, 2_589_408)
        for index in stride(from: 0, to: rate.framesPerDay, by: 997) {
            let tc = Timecode(frameIndex: index, rate: rate)
            XCTAssertEqual(tc.frameIndex, index, "Round trip failed at \(tc.displayString)")
            if tc.seconds == 0 && tc.minutes % 10 != 0 {
                XCTAssertGreaterThanOrEqual(tc.frames, 2)
            }
        }
    }
}

private extension Timecode {
    func withRate(_ rate: FrameRate) -> Timecode {
        Timecode(hours: hours, minutes: minutes, seconds: seconds, frames: frames, rate: rate)
    }
}
