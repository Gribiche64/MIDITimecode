import AVFoundation
import Combine
import CoreAudio
import Foundation
import os.log

private let logger = Logger(subsystem: "Rob-Sinclair-Inc.MIDITimecode", category: "AudioManager")

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
        logger.info("Scanned audio devices: \(devices.map { "\($0.name) (\($0.inputChannelCount)ch, id=\($0.deviceID))" }.joined(separator: ", "))")
        DispatchQueue.main.async {
            self.availableDevices = devices
            if self.selectedDevice == nil, let first = devices.first {
                self.selectedDevice = first
            }
        }
    }

    func start() {
        guard !isRunning else { return }
        guard let device = selectedDevice else {
            logger.warning("Cannot start: no device selected")
            return
        }

        decoder.reset()

        let engine = AVAudioEngine()
        self.engine = engine

        // Access inputNode first to create the audio unit
        let inputNode = engine.inputNode

        // Set the desired input device on the audio unit
        guard let audioUnit = inputNode.audioUnit else {
            logger.error("Cannot start: inputNode.audioUnit is nil")
            self.engine = nil
            return
        }

        var devID = device.deviceID
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &devID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )

        if status != noErr {
            logger.error("Failed to set input device '\(device.name)' (id=\(device.deviceID)): OSStatus \(status)")
            self.engine = nil
            return
        }

        // Re-read format after device change — the format reflects the new device
        let hwFormat = inputNode.outputFormat(forBus: 0)
        let sampleRate = hwFormat.sampleRate

        logger.info("Starting: device='\(device.name)', sampleRate=\(sampleRate), channels=\(hwFormat.channelCount)")

        guard sampleRate > 0 else {
            logger.error("Invalid sample rate (0) for device '\(device.name)'. Device may not be configured for input.")
            self.engine = nil
            return
        }

        // Install tap — use nil format to let the engine pick the best match
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, _ in
            self?.processAudioBuffer(buffer, sampleRate: buffer.format.sampleRate)
        }

        do {
            try engine.start()
            isRunning = true
            logger.info("Engine started successfully for '\(device.name)'")
        } catch {
            logger.error("Failed to start engine: \(error.localizedDescription)")
            inputNode.removeTap(onBus: 0)
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
