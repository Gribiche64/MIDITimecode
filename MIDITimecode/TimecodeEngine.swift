import AppKit
import Combine
import Foundation

enum InputMode: String, CaseIterable, Identifiable {
    case mtc = "MTC"
    case ltc = "LTC"
    var id: String { rawValue }
}

class TimecodeEngine: ObservableObject {
    // MARK: - Published state

    @Published var inputMode: InputMode {
        didSet {
            Settings.inputMode = inputMode
            switchMode()
        }
    }
    @Published var timecode: String = "00:00:00:00"
    @Published var frameRate: String = ""
    @Published var isLocked: Bool = false
    @Published var isReversing: Bool = false
    @Published var signalLevel: Float = 0.0

    /// Throttled copy of `timecode` for the menu bar — updates at ~10Hz
    /// to avoid rendering jitter from 30Hz timecode updates.
    @Published var menuBarTimecode: String = "00:00:00:00"
    private var menuBarUpdateTimer: Timer?

    // Display preferences (persisted)
    @Published var tubeColor: TubeColor {
        didSet { Settings.tubeColor = tubeColor }
    }
    @Published var alwaysOnTop: Bool {
        didSet {
            Settings.alwaysOnTop = alwaysOnTop
            updateWindowLevel()
        }
    }

    // Virtual MTC output (persisted)
    @Published var virtualMTCEnabled: Bool {
        didSet {
            Settings.virtualMTCEnabled = virtualMTCEnabled
            toggleVirtualOutput()
        }
    }

    // Sub-managers (exposed for UI binding)
    let midiManager = MIDIManager()
    let audioManager = AudioManager()
    let virtualSource = VirtualMIDISource()

    private var cancellables = Set<AnyCancellable>()

    init() {
        // Load persisted preferences
        self.inputMode = Settings.inputMode
        self.tubeColor = Settings.tubeColor
        self.alwaysOnTop = Settings.alwaysOnTop
        self.virtualMTCEnabled = Settings.virtualMTCEnabled

        setupBindings()
        startMenuBarUpdates()

        // Restore device selection once devices are enumerated
        restoreDeviceSelection()

        // Start in saved mode
        switch inputMode {
        case .mtc:
            midiManager.start()
        case .ltc:
            audioManager.start()
        }

        // Restore virtual MTC if it was enabled
        if virtualMTCEnabled {
            virtualSource.start()
        }

        // Apply always-on-top if saved
        if alwaysOnTop {
            updateWindowLevel()
        }
    }

    private func startMenuBarUpdates() {
        // Sample timecode at 10Hz for the menu bar (avoids jittery 30Hz updates)
        menuBarUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.menuBarTimecode != self.timecode {
                self.menuBarTimecode = self.timecode
            }
        }
    }

    // MARK: - Device persistence

    private func restoreDeviceSelection() {
        // Watch for MIDI devices to appear and restore saved selection by name
        midiManager.$availableDevices
            .receive(on: RunLoop.main)
            .sink { [weak self] devices in
                guard let self else { return }
                if let savedName = Settings.midiDeviceName,
                   let match = devices.first(where: { $0.name == savedName }),
                   self.midiManager.selectedDevice?.name != savedName {
                    self.midiManager.selectedDevice = match
                }
            }
            .store(in: &cancellables)

        // Save MIDI device whenever the user picks one
        midiManager.$selectedDevice
            .compactMap { $0?.name }
            .receive(on: RunLoop.main)
            .sink { Settings.midiDeviceName = $0 }
            .store(in: &cancellables)

        // Same for audio
        audioManager.$availableDevices
            .receive(on: RunLoop.main)
            .sink { [weak self] devices in
                guard let self else { return }
                if let savedName = Settings.audioDeviceName,
                   let match = devices.first(where: { $0.name == savedName }),
                   self.audioManager.selectedDevice?.name != savedName {
                    self.audioManager.selectedDevice = match
                }
            }
            .store(in: &cancellables)

        audioManager.$selectedDevice
            .compactMap { $0?.name }
            .receive(on: RunLoop.main)
            .sink { Settings.audioDeviceName = $0 }
            .store(in: &cancellables)

        // Restore audio channel
        audioManager.selectedChannel = Settings.audioChannel

        audioManager.$selectedChannel
            .receive(on: RunLoop.main)
            .sink { Settings.audioChannel = $0 }
            .store(in: &cancellables)
    }

    // MARK: - Mode switching

    private func switchMode() {
        // Tear down current mode
        midiManager.stop()
        audioManager.stop()

        // Reset display
        timecode = "00:00:00:00"
        frameRate = ""
        isLocked = false
        isReversing = false
        signalLevel = 0.0

        // Start new mode
        switch inputMode {
        case .mtc:
            midiManager.start()
        case .ltc:
            audioManager.start()
        }
    }

    // MARK: - Combine bindings

    private func setupBindings() {
        // MTC mode → forward timecode
        midiManager.$timecode
            .receive(on: RunLoop.main)
            .sink { [weak self] tc in
                guard let self, self.inputMode == .mtc else { return }
                self.timecode = tc
            }
            .store(in: &cancellables)

        midiManager.$frameRate
            .receive(on: RunLoop.main)
            .sink { [weak self] rate in
                guard let self, self.inputMode == .mtc else { return }
                self.frameRate = rate
                self.isLocked = !rate.isEmpty
            }
            .store(in: &cancellables)

        // Forward assembled timecode to virtual MTC output (MTC mode)
        midiManager.$latestTimecode
            .compactMap { $0 }
            .receive(on: RunLoop.main)
            .sink { [weak self] tc in
                guard let self, self.inputMode == .mtc, self.virtualMTCEnabled else { return }
                self.virtualSource.send(timecode: tc)
            }
            .store(in: &cancellables)

        // LTC mode → forward timecode
        audioManager.$latestTimecode
            .receive(on: RunLoop.main)
            .sink { [weak self] tc in
                guard let self, self.inputMode == .ltc else { return }
                self.timecode = tc.displayString
                self.frameRate = tc.rate.rawValue

                if self.virtualMTCEnabled {
                    self.virtualSource.send(timecode: tc)
                }
            }
            .store(in: &cancellables)

        audioManager.$isLocked
            .receive(on: RunLoop.main)
            .sink { [weak self] locked in
                guard let self, self.inputMode == .ltc else { return }
                self.isLocked = locked
            }
            .store(in: &cancellables)

        audioManager.$isReversing
            .receive(on: RunLoop.main)
            .sink { [weak self] rev in
                guard let self, self.inputMode == .ltc else { return }
                self.isReversing = rev
            }
            .store(in: &cancellables)

        audioManager.$signalLevel
            .receive(on: RunLoop.main)
            .sink { [weak self] level in
                guard let self, self.inputMode == .ltc else { return }
                self.signalLevel = level
            }
            .store(in: &cancellables)
    }

    // MARK: - Virtual MTC output

    private func toggleVirtualOutput() {
        if virtualMTCEnabled {
            virtualSource.start()
        } else {
            virtualSource.stop()
        }
    }

    // MARK: - Window

    private func updateWindowLevel() {
        DispatchQueue.main.async {
            if let window = NSApplication.shared.windows.first {
                window.level = self.alwaysOnTop ? .floating : .normal
            }
        }
    }
}
