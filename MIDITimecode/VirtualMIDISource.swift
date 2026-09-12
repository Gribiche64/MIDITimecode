import Combine
import CoreMIDI
import Foundation
import os.log

private let logger = Logger(subsystem: "Rob-Sinclair-Inc.MIDITimecode", category: "VirtualMIDISource")

/// Publishes a virtual CoreMIDI source carrying a continuous MTC stream.
///
/// The stream is produced by `MTCStreamScheduler` and disciplined by whatever
/// reference the engine feeds in (decoded LTC or incoming MTC). Packets are
/// handed to CoreMIDI ahead of time with exact host timestamps; the MIDI
/// server delivers them to receivers at the stamped moment.
class VirtualMIDISource: ObservableObject {
    @Published var isActive: Bool = false
    /// Current generator state, updated on the main thread.
    @Published var outputState: MTCClock.State = .stopped

    /// Do not rename: receivers (CuePilot) are configured against this name.
    static let defaultSourceName = "MIDITimecode LTC"

    /// Environment variable that overrides the source name, so a test build
    /// can run beside the production app without receivers picking it up.
    static let sourceNameOverrideKey = "MIDITIMECODE_SOURCE_NAME"

    static var sourceName: String {
        if let override = ProcessInfo.processInfo.environment[sourceNameOverrideKey],
           !override.isEmpty {
            return override
        }
        return defaultSourceName
    }

    /// Name of the spare port created ahead of the real one (see `spareEndpoint`).
    static let spareSourceName = "MIDITimecode (spare)"

    private var midiClient: MIDIClientRef = 0
    private var virtualEndpoint: MIDIEndpointRef = 0
    /// CuePilot 8.5.2 binds its MIDI input by a saved list index that is off
    /// by one (index 1 with one port present binds nothing). A silent spare
    /// port created first puts the real port second in every host's list.
    private var spareEndpoint: MIDIEndpointRef = 0
    private var scheduler: MTCStreamScheduler?
    private var configuration = MTCClock.Configuration()

    /// Frames of missing reference tolerated before output stops.
    var freewheelFrames: Int {
        get { configuration.freewheelFrames }
        set {
            configuration.freewheelFrames = newValue
            scheduler?.updateConfiguration(configuration)
        }
    }

    func start() {
        guard !isActive else { return }

        var status = MIDIClientCreateWithBlock(
            "MIDITimecodeVirtualClient" as CFString,
            &midiClient
        ) { [weak self] notification in
            // If the MIDI server restarts, virtual endpoints vanish; put them back.
            guard notification.pointee.messageID == .msgSetupChanged else { return }
            DispatchQueue.main.async { self?.recreateEndpointsIfGone() }
        }
        guard status == noErr else {
            logger.error("Failed to create MIDI client: \(status)")
            return
        }

        createEndpoints()
        guard virtualEndpoint != 0 else { return }

        let scheduler = MTCStreamScheduler(
            configuration: configuration,
            send: { [weak self] bytes, time in
                self?.sendMIDIBytes(bytes, at: time)
            },
            stateChanged: { [weak self] state in
                DispatchQueue.main.async { self?.outputState = state }
            }
        )
        self.scheduler = scheduler
        scheduler.start()

        isActive = true
        logger.info("Virtual source '\(Self.sourceName)' active")
    }

    private func createEndpoints() {
        var status: OSStatus
        let spareStatus = MIDISourceCreate(midiClient, Self.spareSourceName as CFString, &spareEndpoint)
        if spareStatus != noErr {
            logger.error("Failed to create spare source: \(spareStatus)")
            spareEndpoint = 0
        } else {
            applyPersistentUniqueID(to: spareEndpoint, settingKey: Settings.Keys.spareSourceUniqueID)
        }

        status = MIDISourceCreate(
            midiClient,
            Self.sourceName as CFString,
            &virtualEndpoint
        )
        guard status == noErr else {
            logger.error("Failed to create virtual source: \(status)")
            virtualEndpoint = 0
            return
        }
        applyPersistentUniqueID(to: virtualEndpoint, settingKey: Settings.Keys.virtualSourceUniqueID)
        MIDIObjectSetStringProperty(virtualEndpoint, kMIDIPropertyManufacturer, "Rob Sinclair Inc" as CFString)
        MIDIObjectSetStringProperty(virtualEndpoint, kMIDIPropertyModel, "MIDITimecode" as CFString)
    }

    /// After a MIDI setup change, check our endpoints still exist by unique ID
    /// and recreate them if the server dropped them.
    private func recreateEndpointsIfGone() {
        guard isActive, virtualEndpoint != 0 else { return }
        var object = MIDIObjectRef()
        var type = MIDIObjectType.other
        let found = MIDIObjectFindByUniqueID(Settings.uniqueID(forKey: Settings.Keys.virtualSourceUniqueID), &object, &type)
        guard found != noErr else { return }
        logger.warning("Virtual source disappeared from the MIDI setup; recreating")
        virtualEndpoint = 0
        spareEndpoint = 0
        createEndpoints()
    }

    func stop() {
        scheduler?.stop()
        scheduler = nil

        if virtualEndpoint != 0 {
            MIDIEndpointDispose(virtualEndpoint)
            virtualEndpoint = 0
        }
        if spareEndpoint != 0 {
            MIDIEndpointDispose(spareEndpoint)
            spareEndpoint = 0
        }
        if midiClient != 0 {
            MIDIClientDispose(midiClient)
            midiClient = 0
        }

        isActive = false
        outputState = .stopped
    }

    /// Discipline the stream: `position` is the frame that begins at host time `hostTime` (seconds).
    func reference(_ position: Timecode, at hostTime: Double) {
        scheduler?.reference(position, at: hostTime)
    }

    /// Announce a position with a Full Frame and hold the stream (reverse play).
    func locate(_ position: Timecode, at hostTime: Double) {
        scheduler?.locate(position, at: hostTime)
    }

    // MARK: - Private

    /// Give the virtual source the same CoreMIDI unique ID on every launch.
    /// Receivers that remember a port by ID (WebMIDI apps such as CuePilot
    /// derive the port ID from it) otherwise lose the source each time the
    /// app restarts. The ID is chosen once and kept in the app's defaults.
    private func applyPersistentUniqueID(to endpoint: MIDIEndpointRef, settingKey: String) {
        var uniqueID = Settings.uniqueID(forKey: settingKey)
        for attempt in 0..<8 {
            if uniqueID == 0 {
                uniqueID = Int32.random(in: 1...Int32.max)
            }
            let status = MIDIObjectSetIntegerProperty(endpoint, kMIDIPropertyUniqueID, uniqueID)
            if status == noErr {
                Settings.setUniqueID(uniqueID, forKey: settingKey)
                logger.info("Virtual source unique ID \(uniqueID) for \(settingKey) (attempt \(attempt + 1))")
                return
            }
            if status != kMIDIIDNotUnique {
                logger.error("Could not set virtual source unique ID: \(status); using CoreMIDI's assigned ID")
                return
            }
            uniqueID = 0
        }
        logger.error("Could not find an unused unique ID for the virtual source; using CoreMIDI's assigned ID")
    }

    private func sendMIDIBytes(_ bytes: [UInt8], at hostTime: Double) {
        guard virtualEndpoint != 0 else { return }

        var packetList = MIDIPacketList()
        let packetListSize = MemoryLayout<MIDIPacketList>.size
        // A single-packet list holds 256 data bytes; the longest message here
        // is the 10-byte Full Frame, so the add cannot run out of room.
        let packet = MIDIPacketListInit(&packetList)
        _ = MIDIPacketListAdd(
            &packetList,
            packetListSize,
            packet,
            HostTime.ticks(fromSeconds: hostTime),
            bytes.count,
            bytes
        )

        let status = MIDIReceived(virtualEndpoint, &packetList)
        if status != noErr {
            logger.error("MIDIReceived failed: \(status)")
        }
    }

    deinit {
        stop()
    }
}
