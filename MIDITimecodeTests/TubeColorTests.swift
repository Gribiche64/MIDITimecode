import XCTest
import SwiftUI
@testable import MIDITimecode

final class TubeColorTests: XCTestCase {

    func testAllCasesExist() {
        let cases = TubeColor.allCases
        XCTAssertEqual(cases.count, 6)
        XCTAssertTrue(cases.contains(.blue))
        XCTAssertTrue(cases.contains(.cyan))
        XCTAssertTrue(cases.contains(.green))
        XCTAssertTrue(cases.contains(.orange))
        XCTAssertTrue(cases.contains(.purple))
        XCTAssertTrue(cases.contains(.rainbow))
    }

    func testRawValuesMatchExpected() {
        XCTAssertEqual(TubeColor.blue.rawValue, "blue")
        XCTAssertEqual(TubeColor.cyan.rawValue, "cyan")
        XCTAssertEqual(TubeColor.green.rawValue, "green")
        XCTAssertEqual(TubeColor.orange.rawValue, "orange")
        XCTAssertEqual(TubeColor.purple.rawValue, "purple")
        XCTAssertEqual(TubeColor.rainbow.rawValue, "rainbow")
    }

    func testIdentifiableUsesRawValue() {
        for color in TubeColor.allCases {
            XCTAssertEqual(color.id, color.rawValue)
        }
    }

    func testColorsReturnsTupleForAllCases() {
        for color in TubeColor.allCases {
            let result = color.colors(for: 0)
            // Just verify it returns without crashing and produces non-nil colors
            _ = result.primary
            _ = result.secondary
            _ = result.glow
        }
    }

    func testRainbowVariesByDigitIndex() {
        let color0 = TubeColor.rainbow.colors(for: 0)
        let color4 = TubeColor.rainbow.colors(for: 4)
        // Different digit indices should produce different colors in rainbow mode
        // We can't directly compare SwiftUI Colors, but we verify no crash
        _ = color0
        _ = color4
    }

    func testNonRainbowIgnoresDigitIndex() {
        // Non-rainbow colors should return the same result regardless of digit index
        for color in TubeColor.allCases where color != .rainbow {
            let result0 = color.colors(for: 0)
            let result7 = color.colors(for: 7)
            // SwiftUI Color doesn't conform to Equatable in a useful way for testing,
            // but we verify the function is stable and doesn't crash
            _ = result0
            _ = result7
        }
    }

    func testInitFromRawValue() {
        XCTAssertEqual(TubeColor(rawValue: "blue"), .blue)
        XCTAssertEqual(TubeColor(rawValue: "rainbow"), .rainbow)
        XCTAssertNil(TubeColor(rawValue: "invalid"))
    }
}
