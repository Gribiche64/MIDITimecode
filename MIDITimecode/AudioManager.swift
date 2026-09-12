import AppKit
import AVFoundation
import Combine
import CoreAudio
import Foundation
import os
import os.log

private let logger = Logger(subsystem: "Rob-Sinclair-Inc.MIDITimecode", category: "AudioManager")

class AudioManager: ObservableObject {
    @Published var availableDevices: [AudioDevice] = []
    @Published var selectedDevice: AudioDevice? {
        didSet {
            if let device = selectedDevice {
                deviceMissing = false
                if preferredDeviceName != device.name {
                    preferredDeviceName = device.name   // user's pick; reconciles to the same device
                    return
                }
            }
            if wantsRunning { restartEngine() }
        }
    }
    @Published var selectedChannel: Int = 0 {
        didSet {
            if isRunning { restartEngine() }
        }
    }
    /// True while the remembered device is not present on the system.
    @Published var deviceMissing: Bool = false

    /// Name of the device the user wants, kept even while it is unplugged.
    var preferredDeviceName: String? {
        didSet { if preferredDeviceName != oldValue { reconcileSelection() } }
    }
    @Published var latestTimecode: Timecode = .zero
    @Published var isLocked: Bool = false
    @Published var isReversing: Bool = false
    @Published var signalLevel: Float = 0.0

    /// A decoded LTC frame with the host time (seconds) at which it ended.
    struct TimedFrame {
        let timecode: Timecode
        /// Host time of the frame's last sample; the next frame starts here.
        let endHostTime: Double
        let isReversing: Bool
    }

    /// Called on the audio thread for every decoded frame, in order.
    /// Keep the handler short: it runs inside the audio tap callback.
    var frameHandler: ((TimedFrame) -> Void)?

    private var engine: AVAudioEngine?
    private var warnedMissingHostTime = false
    private var decoder = LTCDecoder()
    private var isRunning = false
    /// Set by `start()`, cleared by `stop()`: the engine should be running
    /// whenever the device is present, and be brought back when it returns.
    private var wantsRunning = false
    private var deviceMonitor: AudioDeviceMonitor?
    private var observers: [NSObjectProtocol] = []
    private var watchdog: Timer?
    private let lastBufferTime = OSAllocatedUnfairLock(initialState: 0.0)

    /// Seconds without an audio buffer before the engine is assumed dead.
    static let bufferTimeoutSeconds = 3.0

    init() {
        scanDevices()
        deviceMonitor = AudioDeviceMonitor { [weak self] in
            logger.info("Audio device list changed")
            self?.scanDevices()
        }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            logger.info("System woke; restarting audio if wanted")
            self?.scanDevices()
            self?.restartEngineIfWanted()
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: nil, queue: .main
        ) { [weak self] note in
            guard let self, let engine = note.object as? AVAudioEngine, engine === self.engine else { return }
            // Logged only. Some devices post this repeatedly while running
            // normally; restarting on it resets the decoder each time. If the
            // engine really stopped, buffers stop and the watchdog restarts it.
            logger.info("Audio engine configuration changed (running: \(engine.isRunning))")
        })
        logger.info("AudioManager created")
        watchdog = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.checkBuffersArriving()
        }
    }

    func scanDevices() {
        let devices = AudioDevice.availableInputDevices()
        logger.info("Scanned audio devices: \(devices.map { "\($0.name) (\($0.inputChannelCount)ch, id=\($0.deviceID))" }.joined(separator: ", "))")
        DispatchQueue.main.async { [weak self] in
            self?.availableDevices = devices
            self?.reconcileSelection()
        }
    }

    /// Apply the remembered device name to the current device list.
    private func reconcileSelection() {
        switch AudioDeviceSelection.choose(preferred: preferredDeviceName, current: selectedDevice, available: availableDevices) {
        case .select(let device):
            deviceMissing = false
            if selectedDevice?.deviceID != device.deviceID || selectedDevice?.name != device.name {
                selectedDevice = device   // didSet restarts the engine if wanted
            } else if wantsRunning, !isRunning {
                restartEngineIfWanted()
            }
        case .waitFor(let name):
            if !deviceMissing { logger.warning("Audio device '\(name)' not present; waiting for it") }
            deviceMissing = true
            if isRunning { stopEngine() }
        case .none:
            deviceMissing = false
            if isRunning { stopEngine() }
        }
    }

    /// Run LTC decoding on the selected device, now and whenever it comes back.
    func start() {
        wantsRunning = true
        if isRunning { return }
        reconcileSelection()
        if !isRunning, !deviceMissing { startEngine() }
    }

    func stop() {
        wantsRunning = false
        stopEngine()
    }

    private var lastRestart = 0.0
    /// Shortest interval between automatic restarts, so a flapping device
    /// cannot make the engine thrash.
    static let minimumRestartInterval = 1.0

    private func restartEngineIfWanted() {
        guard wantsRunning else { return }
        let now = HostTime.now()
        guard now - lastRestart >= Self.minimumRestartInterval else {
            logger.warning("Restart requested again within \(Self.minimumRestartInterval) s; skipping")
            return
        }
        lastRestart = now
        restartEngine()
    }

    private func checkBuffersArriving() {
        guard isRunning else { return }
        let last = lastBufferTime.withLock { $0 }
        guard last > 0, HostTime.now() - last > Self.bufferTimeoutSeconds else { return }
        logger.warning("No audio buffers for \(Self.bufferTimeoutSeconds) s; restarting engine")
        scanDevices()
        restartEngine()
    }

    private func startEngine() {
        guard !isRunning else { return }
        guard let device = selectedDevice else {
            logger.warning("Cannot start: no device selected")
            return
        }
        guard availableDevices.contains(where: { $0.deviceID == device.deviceID }) else {
            logger.warning("Cannot start: device '\(device.name)' is not present")
            deviceMissing = true
            return
        }
        lastBufferTime.withLock { $0 = 0 }

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

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: tapFormat) { [weak self] buffer, when in
            self?.processAudioBuffer(buffer, at: when)
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

    private func stopEngine() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        isRunning = false
        decoder.reset()
        DispatchQueue.main.async { [weak self] in
            self?.isLocked = false
            self?.signalLevel = 0.0
        }
    }

    // MARK: - Private

    private func restartEngine() {
        stopEngine()
        startEngine()
    }

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer, at when: AVAudioTime) {
        lastBufferTime.withLock { $0 = HostTime.now() }
        guard let channelData = buffer.floatChannelData else { return }
        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        let sampleRate = buffer.format.sampleRate

        // Pick the user-selected channel (clamped to available channels)
        let channel = min(selectedChannel, channelCount - 1)
        let samples = UnsafeBufferPointer(start: channelData[channel], count: frameCount)

        let bufferStart = bufferStartHostTime(when, sampleCount: frameCount, sampleRate: sampleRate)
        let results = decoder.decode(samples, sampleRate: sampleRate)
        let locked = decoder.isLocked
        let reversing = decoder.isReversing
        let level = decoder.signalLevel

        if let handler = frameHandler {
            for frame in results {
                let end = bufferStart + Double(frame.sampleOffset + 1) / sampleRate
                handler(TimedFrame(timecode: frame.timecode, endHostTime: end, isReversing: reversing))
            }
        }

        if let tc = results.last?.timecode {
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

    /// Host time (seconds) of the first sample in a tap buffer.
    /// Falls back to "now minus the buffer length" if the driver gave no host time.
    private func bufferStartHostTime(_ when: AVAudioTime, sampleCount: Int, sampleRate: Double) -> Double {
        if when.isHostTimeValid {
            return HostTime.seconds(fromTicks: when.hostTime)
        }
        if !warnedMissingHostTime {
            warnedMissingHostTime = true
            logger.warning("Audio tap delivered no host time; MTC timing will use buffer arrival time")
        }
        return HostTime.now() - Double(sampleCount) / sampleRate
    }

    deinit {
        // The engine's manager lives as long as the app; reaching here means
        // an instance was created and dropped, which is worth knowing about.
        logger.error("AudioManager deallocated")
        watchdog?.invalidate()
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
    }
}
