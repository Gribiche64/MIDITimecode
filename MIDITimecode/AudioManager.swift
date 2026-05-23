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

        // Access inputNode to create the underlying AUHAL audio unit
        let inputNode = engine.inputNode

        guard let audioUnit = inputNode.audioUnit else {
            logger.error("Cannot start: inputNode.audioUnit is nil")
            self.engine = nil
            return
        }

        // CRITICAL: AUHAL must be uninitialised before changing the current device.
        // Otherwise the property set is silently ignored and the engine keeps using
        // the default device.
        AudioUnitUninitialize(audioUnit)

        var devID = device.deviceID
        let setStatus = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &devID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )

        if setStatus != noErr {
            logger.error("Failed to set device '\(device.name)' (id=\(device.deviceID)): OSStatus \(setStatus)")
            self.engine = nil
            return
        }

        let initStatus = AudioUnitInitialize(audioUnit)
        if initStatus != noErr {
            logger.error("Failed to reinitialise AUHAL after device change: OSStatus \(initStatus)")
            self.engine = nil
            return
        }

        // Verify the device actually changed
        var currentDev: AudioDeviceID = 0
        var sz = UInt32(MemoryLayout<AudioDeviceID>.size)
        AudioUnitGetProperty(audioUnit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &currentDev, &sz)
        logger.info("AUHAL device after change: \(currentDev) (requested \(device.deviceID))")

        // Re-read format after device change
        let hwFormat = inputNode.outputFormat(forBus: 0)
        let sampleRate = hwFormat.sampleRate

        logger.info("Starting: device='\(device.name)' (id=\(device.deviceID)), sampleRate=\(sampleRate), hwChannels=\(hwFormat.channelCount), deviceChannels=\(device.inputChannelCount)")

        guard sampleRate > 0 else {
            logger.error("Invalid sample rate (0) for device '\(device.name)'.")
            self.engine = nil
            return
        }

        // Build an explicit mono format matching the device's sample rate.
        // Avoids channel-layout mismatches that cause the engine to fail silently.
        guard let tapFormat = AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: AVAudioChannelCount(device.inputChannelCount)
        ) else {
            logger.error("Failed to create AVAudioFormat for \(device.inputChannelCount)ch @ \(sampleRate)Hz")
            self.engine = nil
            return
        }

        logger.info("Installing tap with format: \(tapFormat.description)")

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: tapFormat) { [weak self] buffer, _ in
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
