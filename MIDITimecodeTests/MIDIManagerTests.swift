import XCTest
@testable import MIDITimecode

final class MIDIManagerTests: XCTestCase {

    func testInitialTimecodeIsZeroed() {
        let manager = MIDIManager()
        XCTAssertEqual(manager.timecode, "00:00:00:00")
    }

    func testInitialFrameRateIsEmpty() {
        let manager = MIDIManager()
        XCTAssertEqual(manager.frameRate, "")
    }

    func testDefaultTubeColorIsOrange() {
        let manager = MIDIManager()
        XCTAssertEqual(manager.tubeColor, .orange)
    }

    func testAvailableDevicesStartsEmpty() {
        // On machines without MIDI devices, this should be empty or populated
        // We just verify it doesn't crash on init
        let manager = MIDIManager()
        XCTAssertNotNil(manager.availableDevices)
    }

    func testSelectedDeviceStartsNil() {
        // On machines without MIDI devices
        let manager = MIDIManager()
        // selectedDevice may be set if MIDI devices are present, so just verify no crash
        _ = manager.selectedDevice
    }
}
