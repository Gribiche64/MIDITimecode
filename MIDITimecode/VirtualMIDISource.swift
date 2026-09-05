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
    static let sourceName = "MIDITimecode LTC"

    private var midiClient: MIDIClientRef = 0
    private var virtualEndpoint: MIDIEndpointRef = 0
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
            &midiClient,
            nil
        )
        guard status == noErr else {
            logger.error("Failed to create MIDI client: \(status)")
            return
        }

        status = MIDISourceCreate(
            midiClient,
            Self.sourceName as CFString,
            &virtualEndpoint
        )
        guard status == noErr else {
            logger.error("Failed to create virtual source: \(status)")
            MIDIClientDispose(midiClient)
            midiClient = 0
            return
        }

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

    func stop() {
        scheduler?.stop()
        scheduler = nil

        if virtualEndpoint != 0 {
            MIDIEndpointDispose(virtualEndpoint)
            virtualEndpoint = 0
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

    private func sendMIDIBytes(_ bytes: [UInt8], at hostTime: Double) {
        guard virtualEndpoint != 0 else { return }

        var packetList = MIDIPacketList()
        let packetListSize = MemoryLayout<MIDIPacketList>.size
        var packet = MIDIPacketListInit(&packetList)
        packet = MIDIPacketListAdd(
            &packetList,
            packetListSize,
            packet,
            HostTime.ticks(fromSeconds: hostTime),
            bytes.count,
            bytes
        )
        guard packet != nil else {
            logger.error("Packet list too small for \(bytes.count)-byte message")
            return
        }

        let status = MIDIReceived(virtualEndpoint, &packetList)
        if status != noErr {
            logger.error("MIDIReceived failed: \(status)")
        }
    }

    deinit {
        stop()
    }
}
