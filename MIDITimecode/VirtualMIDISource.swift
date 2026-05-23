import CoreMIDI
import Foundation

class VirtualMIDISource: ObservableObject {
    @Published var isActive: Bool = false

    private var midiClient: MIDIClientRef = 0
    private var virtualEndpoint: MIDIEndpointRef = 0
    private let generator = MTCGenerator()

    private var lastSentTimecode: Timecode?
    private var quarterFrameIndex: Int = 0
    private var timer: DispatchSourceTimer?

    static let sourceName = "MIDITimecode LTC"

    func start() {
        guard !isActive else { return }

        var status = MIDIClientCreateWithBlock(
            "MIDITimecodeVirtualClient" as CFString,
            &midiClient,
            nil
        )
        guard status == noErr else {
            print("VirtualMIDISource: Failed to create MIDI client: \(status)")
            return
        }

        status = MIDISourceCreate(
            midiClient,
            Self.sourceName as CFString,
            &virtualEndpoint
        )
        guard status == noErr else {
            print("VirtualMIDISource: Failed to create virtual source: \(status)")
            return
        }

        isActive = true
    }

    func stop() {
        timer?.cancel()
        timer = nil

        if virtualEndpoint != 0 {
            MIDIEndpointDispose(virtualEndpoint)
            virtualEndpoint = 0
        }
        if midiClient != 0 {
            MIDIClientDispose(midiClient)
            midiClient = 0
        }

        isActive = false
        lastSentTimecode = nil
        quarterFrameIndex = 0
    }

    /// Called when a new timecode frame is decoded. Schedules 8 quarter-frame messages
    /// spread evenly across the frame duration for smooth MTC output.
    func send(timecode: Timecode) {
        guard isActive, virtualEndpoint != 0 else { return }

        // Cancel any in-flight QF sequence from a previous frame
        timer?.cancel()

        lastSentTimecode = timecode
        quarterFrameIndex = 0

        // Send QF messages evenly spaced across two frame durations
        // (MTC transmits a full timecode over 2 frames = 8 QF messages)
        let qfInterval = timecode.rate.frameDuration / 4.0

        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .userInteractive))
        timer.schedule(
            deadline: .now(),
            repeating: qfInterval,
            leeway: .microseconds(100)
        )
        timer.setEventHandler { [weak self] in
            self?.sendNextQuarterFrame()
        }
        timer.resume()
        self.timer = timer
    }

    // MARK: - Private

    private func sendNextQuarterFrame() {
        guard let tc = lastSentTimecode, quarterFrameIndex < 8 else {
            timer?.cancel()
            timer = nil
            return
        }

        let message = generator.quarterFrameMessage(index: quarterFrameIndex, timecode: tc)
        sendMIDIBytes(message)
        quarterFrameIndex += 1

        if quarterFrameIndex >= 8 {
            timer?.cancel()
            timer = nil
        }
    }

    private func sendMIDIBytes(_ bytes: [UInt8]) {
        guard virtualEndpoint != 0 else { return }

        // Build a MIDIPacketList with a single packet
        var packetList = MIDIPacketList()
        let packetListSize = MemoryLayout<MIDIPacketList>.size
        var curPacket = MIDIPacketListInit(&packetList)
        curPacket = MIDIPacketListAdd(
            &packetList,
            packetListSize,
            curPacket,
            0, // timestamp 0 = now
            bytes.count,
            bytes
        )

        MIDIReceived(virtualEndpoint, &packetList)
    }

    deinit {
        stop()
    }
}
