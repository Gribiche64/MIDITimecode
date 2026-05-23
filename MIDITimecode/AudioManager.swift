import AVFoundation
import Combine
import CoreAudio
import Foundation

class AudioManager: ObservableObject {
    @Published var availableDevices: [AudioDevice] = []
    @Published var selectedDevice: AudioDevice? {
        didSet {
            if isRunning { restart() }
        }
    }
    @Published var selectedChannel: Int = 0 {
        didSet {
            if isRunning { restart() }
        }
    }
    @Published var latestTimecode: Timecode = .zero
    @Published var isLocked: Bool = false
    @Published var isReversing: Bool = false
    @Published var signalLevel: Float = 0.0

    private var engine: AVAudioEngine?
    private var decoder = LTCDecoder()
    private var isRunning = false

    init() {
        scanDevices()
    }

    func scanDevices() {
        let devices = AudioDevice.availableInputDevices()
        DispatchQueue.main.async {
            self.availableDevices = devices
            if self.selectedDevice == nil, let first = devices.first {
                self.selectedDevice = first
            }
        }
    }

    func start() {
        guard !isRunning else { return }
        guard let device = selectedDevice else { return }

        decoder.reset()

        let engine = AVAudioEngine()
        self.engine = engine

        // Set the input device on the engine's audio unit
        setInputDevice(device.deviceID, on: engine)

        let inputNode = engine.inputNode
        let hwFormat = inputNode.outputFormat(forBus: 0)
        let sampleRate = hwFormat.sampleRate

        // Install a tap — request the hardware format to avoid conversion
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: hwFormat) { [weak self] buffer, _ in
            self?.processAudioBuffer(buffer, sampleRate: sampleRate)
        }

        do {
            try engine.start()
            isRunning = true
        } catch {
            print("AudioManager: Failed to start engine: \(error)")
            self.engine = nil
        }
    }

    func stop() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        isRunning = false
        DispatchQueue.main.async {
            self.isLocked = false
            self.signalLevel = 0.0
        }
    }

    // MARK: - Private

    private func restart() {
        stop()
        start()
    }

    private func setInputDevice(_ deviceID: AudioDeviceID, on engine: AVAudioEngine) {
        let inputNode = engine.inputNode
        guard let audioUnit = inputNode.audioUnit else { return }

        var devID = deviceID
        AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &devID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
    }

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer, sampleRate: Double) {
        guard let channelData = buffer.floatChannelData else { return }
        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)

        // Pick the user-selected channel (clamped to available channels)
        let channel = min(selectedChannel, channelCount - 1)
        let samples = UnsafeBufferPointer(start: channelData[channel], count: frameCount)

        let results = decoder.processSamples(samples, sampleRate: sampleRate)
        let locked = decoder.isLocked
        let reversing = decoder.isReversing
        let level = decoder.signalLevel

        if let tc = results.last {
            DispatchQueue.main.async {
                self.latestTimecode = tc
                self.isLocked = locked
                self.isReversing = reversing
                self.signalLevel = level
            }
        } else {
            DispatchQueue.main.async {
                self.isLocked = locked
                self.signalLevel = level
            }
        }
    }

    deinit {
        stop()
    }
}
