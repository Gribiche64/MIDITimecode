import AppKit
import CoreMIDI
import Combine
import Foundation

class MIDIManager: ObservableObject {
    @Published var timecode: String = "00:00:00:00"
    @Published var frameRate: String = ""
    @Published var availableDevices: [MIDIDevice] = []
    @Published var selectedDevice: MIDIDevice? {
        didSet { listenToSelectedDevice() }
    }
    @Published var tubeColor: TubeColor = .orange
    @Published var alwaysOnTop: Bool = false {
        didSet { updateWindowLevel() }
    }

    private var midiClient: MIDIClientRef = 0
    private var inputPort: MIDIPortRef = 0

    private var hours: UInt8 = 0
    private var minutes: UInt8 = 0
    private var seconds: UInt8 = 0
    private var frames: UInt8 = 0

    // MTC quarter-frame assembly state
    private var mtcQuarterFrameCount: Int = 0
    private var mtcHours: UInt8 = 0
    private var mtcMinutes: UInt8 = 0
    private var mtcSeconds: UInt8 = 0
    private var mtcFrames: UInt8 = 0

    init() {
        setupMIDI()
        scanDevices()
    }

    // MARK: - MIDI Setup

    private func setupMIDI() {
        let status = MIDIClientCreateWithBlock("MIDITimecodeClient" as CFString, &midiClient) { [weak self] notification in
            // Re-scan devices on MIDI setup changes
            DispatchQueue.main.async {
                self?.scanDevices()
            }
        }
        if status != noErr {
            print("Error creating MIDI client: \(status)")
            return
        }

        let portStatus = MIDIInputPortCreateWithBlock(
            midiClient,
            "MIDITimecodeInput" as CFString,
            &inputPort
        ) { [weak self] packetList, _ in
            self?.handleMIDIPacketList(packetList)
        }
        if portStatus != noErr {
            print("Error creating input port: \(portStatus)")
        }
    }

    func scanDevices() {
        let sourceCount = MIDIGetNumberOfSources()
        print("Scanning MIDI devices, found \(sourceCount)")

        var devices: [MIDIDevice] = []
        for i in 0..<sourceCount {
            let endpoint = MIDIGetSource(i)
            var name: Unmanaged<CFString>?
            MIDIObjectGetStringProperty(endpoint, kMIDIPropertyName, &name)
            let deviceName = (name?.takeRetainedValue() as String?) ?? "Unknown Device"
            print("Found MIDI device: \(deviceName)")
            devices.append(MIDIDevice(name: deviceName, endpoint: endpoint))
        }

        DispatchQueue.main.async {
            self.availableDevices = devices
            if self.selectedDevice == nil, let first = devices.first {
                self.selectedDevice = first
            }
        }
    }

    private func listenToSelectedDevice() {
        // Disconnect all sources first
        let sourceCount = MIDIGetNumberOfSources()
        for i in 0..<sourceCount {
            MIDIPortDisconnectSource(inputPort, MIDIGetSource(i))
        }

        // Connect to the selected device
        guard let device = selectedDevice else { return }
        MIDIPortConnectSource(inputPort, device.endpoint, nil)
    }

    // MARK: - Window

    private func updateWindowLevel() {
        DispatchQueue.main.async {
            if let window = NSApplication.shared.windows.first {
                window.level = self.alwaysOnTop ? .floating : .normal
            }
        }
    }

    // MARK: - MTC Parsing

    private func handleMIDIPacketList(_ packetList: UnsafePointer<MIDIPacketList>) {
        let packets = packetList.pointee
        var packet = packets.packet

        for _ in 0..<packets.numPackets {
            let bytes = Mirror(reflecting: packet.data).children.map { $0.value as! UInt8 }
            for i in 0..<Int(packet.length) {
                let byte = bytes[i]

                // MTC Quarter Frame message: 0xF1 followed by data byte
                if byte == 0xF1, i + 1 < Int(packet.length) {
                    let dataByte = bytes[i + 1]
                    processMTCQuarterFrame(dataByte)
                }
            }
            packet = MIDIPacketNext(&packet).pointee
        }
    }

    private func processMTCQuarterFrame(_ dataByte: UInt8) {
        let messageType = (dataByte >> 4) & 0x07
        let nibbleValue = dataByte & 0x0F

        switch messageType {
        case 0: // Frame count LS nibble
            mtcFrames = (mtcFrames & 0xF0) | nibbleValue
            mtcQuarterFrameCount = 1
        case 1: // Frame count MS nibble
            mtcFrames = (mtcFrames & 0x0F) | (nibbleValue << 4)
            mtcQuarterFrameCount = 2
        case 2: // Seconds count LS nibble
            mtcSeconds = (mtcSeconds & 0xF0) | nibbleValue
            mtcQuarterFrameCount = 3
        case 3: // Seconds count MS nibble
            mtcSeconds = (mtcSeconds & 0x0F) | (nibbleValue << 4)
            mtcQuarterFrameCount = 4
        case 4: // Minutes count LS nibble
            mtcMinutes = (mtcMinutes & 0xF0) | nibbleValue
            mtcQuarterFrameCount = 5
        case 5: // Minutes count MS nibble
            mtcMinutes = (mtcMinutes & 0x0F) | (nibbleValue << 4)
            mtcQuarterFrameCount = 6
        case 6: // Hours count LS nibble
            mtcHours = (mtcHours & 0xF0) | nibbleValue
            mtcQuarterFrameCount = 7
        case 7: // Hours count MS nibble + frame rate
            mtcHours = (mtcHours & 0x0F) | ((nibbleValue & 0x01) << 4)
            updateFrameRate(nibbleValue)
            mtcQuarterFrameCount = 8

            // Full frame assembled — update display
            hours = mtcHours
            minutes = mtcSeconds > 59 ? 59 : mtcMinutes
            seconds = mtcSeconds > 59 ? 59 : mtcSeconds
            frames = mtcFrames
            DispatchQueue.main.async {
                self.updateTimecode()
            }
        default:
            break
        }
    }

    private func updateFrameRate(_ rateNibble: UInt8) {
        let rateType = (rateNibble >> 1) & 0x03
        let rate: String
        switch rateType {
        case 0: rate = "24 fps"
        case 1: rate = "25 fps"
        case 2: rate = "29.97 fps (DF)"
        case 3: rate = "30 fps"
        default: rate = ""
        }
        DispatchQueue.main.async {
            self.frameRate = rate
        }
    }

    private func updateTimecode() {
        timecode = String(format: "%02d:%02d:%02d:%02d", hours, minutes, seconds, frames)
    }

    deinit {
        if inputPort != 0 {
            MIDIPortDispose(inputPort)
        }
        if midiClient != 0 {
            MIDIClientDispose(midiClient)
        }
    }
}
