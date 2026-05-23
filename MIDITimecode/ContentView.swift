import SwiftUI

struct ContentView: View {
    @EnvironmentObject var engine: TimecodeEngine

    var body: some View {
        VStack(spacing: 0) {
            // Main timecode area
            ZStack {
                LinearGradient(
                    colors: [Color(white: 0.05), Color(white: 0.1)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                TimecodeDisplayView(
                    timecode: engine.timecode,
                    tubeColor: engine.tubeColor
                )
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }

            // Settings bar
            HStack(spacing: 0) {
                // Left group: Mode + Status + Source
                HStack(spacing: 0) {
                    // Input mode picker
                    inputModePicker

                    Divider()
                        .frame(height: 14)
                        .overlay(Color(white: 0.35))

                    // Status indicator
                    statusIndicator
                        .padding(.horizontal, 8)

                    Divider()
                        .frame(height: 14)
                        .overlay(Color(white: 0.35))

                    // Source picker (changes based on mode)
                    sourcePicker
                }
                .padding(.vertical, 4)
                .background(Color(white: 0.22))
                .clipShape(RoundedRectangle(cornerRadius: 5))

                Spacer()

                // Right group: Virtual MTC + Color + Pin
                HStack(spacing: 0) {
                    // Virtual MTC output toggle
                    Button(action: { engine.virtualMTCEnabled.toggle() }) {
                        HStack(spacing: 3) {
                            Image(systemName: engine.virtualMTCEnabled ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right")
                                .font(.system(size: 10))
                            Text("MTC Out")
                        }
                        .foregroundStyle(engine.virtualMTCEnabled ? Color.orange : Color(white: 0.5))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 8)
                    .help(engine.virtualMTCEnabled ? "Virtual MTC output active" : "Enable virtual MTC output")

                    Divider()
                        .frame(height: 14)
                        .overlay(Color(white: 0.35))

                    Text("Color:")
                        .foregroundStyle(Color(white: 0.85))
                        .padding(.leading, 8)

                    Menu {
                        ForEach(TubeColor.allCases) { color in
                            Button(action: { engine.tubeColor = color }) {
                                HStack {
                                    Text(color.rawValue.capitalized)
                                    if color == engine.tubeColor {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(engine.tubeColor.rawValue.capitalized)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 9))
                                .foregroundStyle(Color(white: 0.6))
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 4)

                    Divider()
                        .frame(height: 14)
                        .overlay(Color(white: 0.35))
                        .padding(.leading, 8)

                    Button(action: { engine.alwaysOnTop.toggle() }) {
                        Image(systemName: engine.alwaysOnTop ? "pin.fill" : "pin")
                            .font(.system(size: 11))
                            .foregroundStyle(engine.alwaysOnTop ? Color.orange : Color(white: 0.85))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 8)
                    .help("Always on top")
                }
                .padding(.vertical, 4)
                .background(Color(white: 0.22))
                .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            .font(.system(size: 12))
            .foregroundStyle(Color(white: 0.85))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color(white: 0.14))
        }
        .background(Color.black)
    }

    // MARK: - Input Mode Picker

    private var inputModePicker: some View {
        Menu {
            ForEach(InputMode.allCases) { mode in
                Button(action: { engine.inputMode = mode }) {
                    HStack {
                        Text(mode.rawValue)
                        if mode == engine.inputMode {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(engine.inputMode.rawValue)
                    .fontWeight(.medium)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9))
                    .foregroundStyle(Color(white: 0.6))
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
    }

    // MARK: - Status Indicator

    private var statusIndicator: some View {
        Group {
            if engine.inputMode == .ltc {
                HStack(spacing: 4) {
                    // Signal level dot
                    Circle()
                        .fill(signalColor)
                        .frame(width: 6, height: 6)

                    if engine.isLocked {
                        Text(engine.frameRate + (engine.isReversing ? " REV" : ""))
                            .foregroundStyle(Color.green)
                    } else if engine.signalLevel > 0.01 {
                        Text("Locking...")
                            .foregroundStyle(Color.yellow)
                    } else {
                        Text("No Signal")
                            .foregroundStyle(Color(white: 0.5))
                    }
                }
            } else {
                Text(engine.frameRate.isEmpty ? "No MTC" : engine.frameRate)
                    .foregroundStyle(engine.frameRate.isEmpty ? Color(white: 0.85) : Color.orange)
            }
        }
    }

    private var signalColor: Color {
        if engine.isLocked { return .green }
        if engine.signalLevel > 0.01 { return .yellow }
        return Color(white: 0.4)
    }

    // MARK: - Source Picker

    private var sourcePicker: some View {
        Group {
            if engine.inputMode == .mtc {
                mtcSourcePicker
            } else {
                ltcSourcePicker
            }
        }
    }

    private var mtcSourcePicker: some View {
        HStack(spacing: 0) {
            Text("MIDI:")
                .foregroundStyle(Color(white: 0.85))
                .padding(.leading, 8)

            Menu {
                if engine.midiManager.availableDevices.isEmpty {
                    Button("No MIDI devices found") {}
                        .disabled(true)
                }
                ForEach(engine.midiManager.availableDevices) { device in
                    Button(action: { engine.midiManager.selectedDevice = device }) {
                        HStack {
                            Text(device.name)
                            if device == engine.midiManager.selectedDevice {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
                Divider()
                Button("Rescan Devices") {
                    engine.midiManager.scanDevices()
                }
            } label: {
                HStack(spacing: 4) {
                    Text(engine.midiManager.selectedDevice?.name ?? "None")
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9))
                        .foregroundStyle(Color(white: 0.6))
                }
            }
            .buttonStyle(.plain)
            .padding(.leading, 4)
            .padding(.trailing, 8)
        }
    }

    private var ltcSourcePicker: some View {
        HStack(spacing: 0) {
            Text("Audio:")
                .foregroundStyle(Color(white: 0.85))
                .padding(.leading, 8)

            Menu {
                if engine.audioManager.availableDevices.isEmpty {
                    Button("No audio inputs found") {}
                        .disabled(true)
                }
                ForEach(engine.audioManager.availableDevices) { device in
                    Button(action: { engine.audioManager.selectedDevice = device }) {
                        HStack {
                            Text(device.name)
                            if device == engine.audioManager.selectedDevice {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
                Divider()
                Button("Rescan Devices") {
                    engine.audioManager.scanDevices()
                }
            } label: {
                HStack(spacing: 4) {
                    Text(engine.audioManager.selectedDevice?.name ?? "None")
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9))
                        .foregroundStyle(Color(white: 0.6))
                }
            }
            .buttonStyle(.plain)
            .padding(.leading, 4)

            // Channel picker (only if device has multiple channels)
            if let device = engine.audioManager.selectedDevice, device.inputChannelCount > 1 {
                Divider()
                    .frame(height: 14)
                    .overlay(Color(white: 0.35))
                    .padding(.leading, 4)

                Menu {
                    ForEach(0..<device.inputChannelCount, id: \.self) { ch in
                        Button(action: { engine.audioManager.selectedChannel = ch }) {
                            HStack {
                                Text("Ch \(ch + 1)")
                                if ch == engine.audioManager.selectedChannel {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("Ch \(engine.audioManager.selectedChannel + 1)")
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 9))
                            .foregroundStyle(Color(white: 0.6))
                    }
                }
                .buttonStyle(.plain)
                .padding(.leading, 4)
            }

            Spacer().frame(width: 8)
        }
    }
}
