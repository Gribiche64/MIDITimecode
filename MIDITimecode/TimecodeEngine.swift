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

    @Published var inputMode: InputMode = .mtc {
        didSet { switchMode() }
    }
    @Published var timecode: String = "00:00:00:00"
    @Published var frameRate: String = ""
    @Published var isLocked: Bool = false
    @Published var isReversing: Bool = false
    @Published var signalLevel: Float = 0.0

    // Display preferences
    @Published var tubeColor: TubeColor = .orange
    @Published var alwaysOnTop: Bool = false {
        didSet { updateWindowLevel() }
    }

    // Virtual MTC output
    @Published var virtualMTCEnabled: Bool = false {
        didSet { toggleVirtualOutput() }
    }

    // Sub-managers (exposed for UI binding)
    let midiManager = MIDIManager()
    let audioManager = AudioManager()
    let virtualSource = VirtualMIDISource()

    private var cancellables = Set<AnyCancellable>()

    init() {
        setupBindings()
        // Start in MTC mode by default
        midiManager.start()
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
