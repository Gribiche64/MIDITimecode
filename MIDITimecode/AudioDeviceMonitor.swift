import CoreAudio
import Foundation

/// Calls a handler on the main queue whenever the system's audio device list
/// changes (an interface plugged in, unplugged or power-cycled).
final class AudioDeviceMonitor {
    private var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    private let listener: AudioObjectPropertyListenerBlock
    private let installed: Bool

    init(onChange: @escaping () -> Void) {
        listener = { _, _ in onChange() }
        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, listener
        )
        installed = status == noErr
    }

    deinit {
        if installed {
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, listener
            )
        }
    }
}
