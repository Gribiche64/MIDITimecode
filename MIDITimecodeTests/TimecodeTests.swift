import XCTest
@testable import MIDITimecode

final class TimecodeTests: XCTestCase {

    // MARK: - Display String

    func testDisplayStringZero() {
        let tc = Timecode.zero
        XCTAssertEqual(tc.displayString, "00:00:00:00")
    }

    func testDisplayStringPadded() {
        let tc = Timecode(hours: 1, minutes: 2, seconds: 3, frames: 4, rate: .fps25)
        XCTAssertEqual(tc.displayString, "01:02:03:04")
    }

    func testDisplayStringMaxValues() {
        let tc = Timecode(hours: 23, minutes: 59, seconds: 59, frames: 29, rate: .fps30)
        XCTAssertEqual(tc.displayString, "23:59:59:29")
    }

    // MARK: - Clamping

    func testClampedMinutes() {
        let tc = Timecode(hours: 0, minutes: 63, seconds: 0, frames: 0, rate: .fps25)
        XCTAssertEqual(tc.clamped.minutes, 59)
    }

    func testClampedSeconds() {
        let tc = Timecode(hours: 0, minutes: 0, seconds: 61, frames: 0, rate: .fps25)
        XCTAssertEqual(tc.clamped.seconds, 59)
    }

    func testClampedFrames24fps() {
        let tc = Timecode(hours: 0, minutes: 0, seconds: 0, frames: 30, rate: .fps24)
        XCTAssertEqual(tc.clamped.frames, 23)
    }

    func testClampedFrames25fps() {
        let tc = Timecode(hours: 0, minutes: 0, seconds: 0, frames: 30, rate: .fps25)
        XCTAssertEqual(tc.clamped.frames, 24)
    }

    func testClampedFrames30fps() {
        let tc = Timecode(hours: 0, minutes: 0, seconds: 0, frames: 31, rate: .fps30)
        XCTAssertEqual(tc.clamped.frames, 29)
    }

    func testClampedPreservesValidValues() {
        let tc = Timecode(hours: 10, minutes: 30, seconds: 45, frames: 12, rate: .fps25)
        XCTAssertEqual(tc.clamped, tc)
    }

    // MARK: - Equality

    func testEquality() {
        let a = Timecode(hours: 1, minutes: 2, seconds: 3, frames: 4, rate: .fps25)
        let b = Timecode(hours: 1, minutes: 2, seconds: 3, frames: 4, rate: .fps25)
        XCTAssertEqual(a, b)
    }

    func testInequalityDifferentFrames() {
        let a = Timecode(hours: 1, minutes: 2, seconds: 3, frames: 4, rate: .fps25)
        let b = Timecode(hours: 1, minutes: 2, seconds: 3, frames: 5, rate: .fps25)
        XCTAssertNotEqual(a, b)
    }

    func testInequalityDifferentRate() {
        let a = Timecode(hours: 1, minutes: 2, seconds: 3, frames: 4, rate: .fps25)
        let b = Timecode(hours: 1, minutes: 2, seconds: 3, frames: 4, rate: .fps30)
        XCTAssertNotEqual(a, b)
    }

    // MARK: - FrameRate

    func testFrameRateMTCRoundTrip() {
        for rate in FrameRate.allCases {
            let recovered = FrameRate(mtcRateCode: rate.mtcRateCode)
            XCTAssertEqual(recovered, rate)
        }
    }

    func testFrameRateInvalidMTCCode() {
        XCTAssertNil(FrameRate(mtcRateCode: 4))
        XCTAssertNil(FrameRate(mtcRateCode: 255))
    }

    func testFrameRateLabels() {
        XCTAssertEqual(FrameRate.fps24.rawValue, "24 fps")
        XCTAssertEqual(FrameRate.fps25.rawValue, "25 fps")
        XCTAssertEqual(FrameRate.df2997.rawValue, "29.97 fps (DF)")
        XCTAssertEqual(FrameRate.fps30.rawValue, "30 fps")
    }

    func testFrameRateFromDuration() {
        XCTAssertEqual(FrameRate.fromFrameDuration(1.0 / 24.0), .fps24)
        XCTAssertEqual(FrameRate.fromFrameDuration(1.0 / 25.0), .fps25)
        XCTAssertEqual(FrameRate.fromFrameDuration(1.0 / 30.0), .fps30)
    }

    func testFrameDuration() {
        XCTAssertEqual(FrameRate.fps24.frameDuration, 1.0 / 24.0, accuracy: 0.0001)
        XCTAssertEqual(FrameRate.fps25.frameDuration, 1.0 / 25.0, accuracy: 0.0001)
        XCTAssertEqual(FrameRate.fps30.frameDuration, 1.0 / 30.0, accuracy: 0.0001)
    }
}
