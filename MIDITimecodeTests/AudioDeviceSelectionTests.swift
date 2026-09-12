import XCTest
@testable import MIDITimecode

final class AudioDeviceSelectionTests: XCTestCase {
    private let usb = AudioDevice(name: "USB Audio Device", deviceID: 148, inputChannelCount: 1)
    private let usbReplugged = AudioDevice(name: "USB Audio Device", deviceID: 173, inputChannelCount: 1)
    private let mic = AudioDevice(name: "MacBook Pro Microphone", deviceID: 91, inputChannelCount: 1)

    func testPreferredDeviceIsPickedUnderItsNewIDAfterReplug() {
        let choice = AudioDeviceSelection.choose(preferred: "USB Audio Device", current: usb, available: [mic, usbReplugged])
        XCTAssertEqual(choice, .select(usbReplugged))
    }

    func testMissingPreferredDeviceIsWaitedForNotReplaced() {
        let choice = AudioDeviceSelection.choose(preferred: "USB Audio Device", current: usb, available: [mic])
        XCTAssertEqual(choice, .waitFor("USB Audio Device"))
    }

    func testNoPreferenceKeepsCurrentIfStillPresent() {
        XCTAssertEqual(AudioDeviceSelection.choose(preferred: nil, current: mic, available: [usb, mic]), .select(mic))
    }

    func testNoPreferenceFallsBackToFirstDevice() {
        XCTAssertEqual(AudioDeviceSelection.choose(preferred: nil, current: nil, available: [usb, mic]), .select(usb))
        XCTAssertEqual(AudioDeviceSelection.choose(preferred: "", current: nil, available: [usb, mic]), .select(usb))
    }

    func testNothingAvailable() {
        XCTAssertEqual(AudioDeviceSelection.choose(preferred: nil, current: nil, available: []), .none)
        XCTAssertEqual(AudioDeviceSelection.choose(preferred: "USB Audio Device", current: nil, available: []), .waitFor("USB Audio Device"))
    }
}
