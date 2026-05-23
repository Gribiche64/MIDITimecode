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
    private var parser = MTCParser()

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

                if byte == 0xF1, i + 1 < Int(packet.length) {
                    let dataByte = bytes[i + 1]
                    if parser.processQuarterFrame(dataByte) {
                        let tc = parser.timecode
                        let rate = parser.frameRate
                        DispatchQueue.main.async {
                            self.timecode = tc
                            self.frameRate = rate
                        }
                    }
                }
            }
            packet = MIDIPacketNext(&packet).pointee
        }
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
