import Foundation

/// Decides which audio input to use when the device list changes.
///
/// The user's choice is remembered by *name* because CoreAudio device IDs
/// change every time an interface is unplugged and plugged back in. A
/// missing preferred device is waited for rather than silently replaced by
/// whatever else is available, so a USB interface that comes back after a
/// power cycle is picked up again without any clicking.
enum AudioDeviceSelection {
    enum Choice: Equatable {
        /// Use this device (it may be the same one under a new ID).
        case select(AudioDevice)
        /// The preferred device is not present; keep waiting for it.
        case waitFor(String)
        /// Nothing to choose from.
        case none
    }

    static func choose(preferred: String?, current: AudioDevice?, available: [AudioDevice]) -> Choice {
        if let preferred, !preferred.isEmpty {
            if let match = available.first(where: { $0.name == preferred }) {
                return .select(match)
            }
            return .waitFor(preferred)
        }
        if let current, let stillThere = available.first(where: { $0.deviceID == current.deviceID }) {
            return .select(stillThere)
        }
        if let first = available.first {
            return .select(first)
        }
        return .none
    }
}
