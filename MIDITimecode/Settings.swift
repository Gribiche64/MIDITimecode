import Foundation

/// Persists user preferences to UserDefaults so the app remembers
/// the last device/channel/mode/colour/etc. between launches.
enum Settings {
    private static let defaults = UserDefaults.standard

    enum Keys {
        static let inputMode = "inputMode"
        static let midiDeviceName = "midiDeviceName"
        static let audioDeviceName = "audioDeviceName"
        static let audioChannel = "audioChannel"
        static let tubeColor = "tubeColor"
        static let alwaysOnTop = "alwaysOnTop"
        static let virtualMTCEnabled = "virtualMTCEnabled"
        static let freewheelSeconds = "freewheelSeconds"
        static let virtualSourceUniqueID = "virtualSourceUniqueID"
        static let spareSourceUniqueID = "spareSourceUniqueID"
    }

    /// Default freewheel on loss of LTC, in seconds.
    static let defaultFreewheelSeconds = 1.0

    // MARK: - Typed accessors

    static var inputMode: InputMode {
        get { InputMode(rawValue: defaults.string(forKey: Keys.inputMode) ?? "") ?? .mtc }
        set { defaults.set(newValue.rawValue, forKey: Keys.inputMode) }
    }

    static var midiDeviceName: String? {
        get { defaults.string(forKey: Keys.midiDeviceName) }
        set { defaults.set(newValue, forKey: Keys.midiDeviceName) }
    }

    static var audioDeviceName: String? {
        get { defaults.string(forKey: Keys.audioDeviceName) }
        set { defaults.set(newValue, forKey: Keys.audioDeviceName) }
    }

    static var audioChannel: Int {
        get { defaults.integer(forKey: Keys.audioChannel) }
        set { defaults.set(newValue, forKey: Keys.audioChannel) }
    }

    static var tubeColor: TubeColor {
        get { TubeColor(rawValue: defaults.string(forKey: Keys.tubeColor) ?? "") ?? .orange }
        set { defaults.set(newValue.rawValue, forKey: Keys.tubeColor) }
    }

    static var alwaysOnTop: Bool {
        get { defaults.bool(forKey: Keys.alwaysOnTop) }
        set { defaults.set(newValue, forKey: Keys.alwaysOnTop) }
    }

    static var virtualMTCEnabled: Bool {
        get { defaults.bool(forKey: Keys.virtualMTCEnabled) }
        set { defaults.set(newValue, forKey: Keys.virtualMTCEnabled) }
    }

    /// CoreMIDI unique ID stored under `key`; 0 until one has been chosen.
    static func uniqueID(forKey key: String) -> Int32 {
        Int32(clamping: defaults.integer(forKey: key))
    }

    static func setUniqueID(_ id: Int32, forKey key: String) {
        defaults.set(Int(id), forKey: key)
    }

    static var freewheelSeconds: Double {
        get {
            guard defaults.object(forKey: Keys.freewheelSeconds) != nil else { return defaultFreewheelSeconds }
            let value = defaults.double(forKey: Keys.freewheelSeconds)
            return value > 0 ? value : defaultFreewheelSeconds
        }
        set { defaults.set(newValue, forKey: Keys.freewheelSeconds) }
    }
}
