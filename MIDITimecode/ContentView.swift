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
                    // Virtual MTC output toggle (click) and freewheel setting (menu)
                    mtcOutputControl

                    Divider()
                        .frame(height: 14)
                        .overlay(Color(white: 0.35))

                    Text("Color:")
                .lineLimit(1)
                .fixedSize()
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
                                .lineLimit(1)
                                .fixedSize()
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

    // MARK: - MTC Output

    private var mtcOutputControl: some View {
        Menu {
            Section("Freewheel on signal loss") {
                ForEach(TimecodeEngine.freewheelChoices, id: \.self) { seconds in
                    Button(action: { engine.freewheelSeconds = seconds }) {
                        HStack {
                            Text(Self.freewheelLabel(seconds))
                            if seconds == engine.freewheelSeconds {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: engine.virtualMTCEnabled
                      ? "antenna.radiowaves.left.and.right"
                      : "antenna.radiowaves.left.and.right.slash")
                    .font(.system(size: 10))
                Text(mtcOutputLabel)
                    .lineLimit(1)
                    .fixedSize()
                Circle()
                    .fill(mtcOutputColor)
                    .frame(width: 6, height: 6)
            }
            .foregroundStyle(mtcOutputColor)
        } primaryAction: {
            engine.virtualMTCEnabled.toggle()
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .help(mtcOutputHelp)
    }

    private var mtcOutputLabel: String {
        guard engine.virtualMTCEnabled else { return "MTC Off" }
        switch engine.mtcOutputState {
        case .stopped: return "MTC Waiting"
        case .locked: return "MTC Locked"
        case .freewheeling: return "MTC Freewheel"
        }
    }

    private var mtcOutputColor: Color {
        guard engine.virtualMTCEnabled else { return Color(white: 0.45) }
        switch engine.mtcOutputState {
        case .stopped: return Color(white: 0.9)
        case .locked: return .orange
        case .freewheeling: return .yellow
        }
    }

    private var mtcOutputHelp: String {
        guard engine.virtualMTCEnabled else { return "Enable virtual MTC output" }
        let freewheel = Self.freewheelLabel(engine.freewheelSeconds)
        switch engine.mtcOutputState {
        case .stopped: return "Virtual MTC output on, waiting for timecode (freewheel \(freewheel))"
        case .locked: return "Virtual MTC output locked to input (freewheel \(freewheel))"
        case .freewheeling: return "Input lost, MTC freewheeling for up to \(freewheel)"
        }
    }

    private static func freewheelLabel(_ seconds: Double) -> String {
        seconds == seconds.rounded() ? String(format: "%.0f s", seconds) : String(format: "%.1f s", seconds)
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
                    .fixedSize()
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

                    if engine.audioManager.deviceMissing {
                        Text("No Device")
                            .fixedSize()
                            .foregroundStyle(Color.red)
                    } else if engine.isLocked {
                        Text(engine.frameRate + (engine.isReversing ? " REV" : ""))
                            .fixedSize()
                            .foregroundStyle(Color.green)
                    } else if engine.signalLevel > 0.01 {
                        Text("Locking...")
                            .fixedSize()
                            .foregroundStyle(Color.yellow)
                    } else {
                        Text("No Signal")
                            .fixedSize()
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
        if engine.audioManager.deviceMissing { return .red }
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
                .lineLimit(1)
                .fixedSize()
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
                        .frame(maxWidth: 220, alignment: .leading)
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
                .lineLimit(1)
                .fixedSize()
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
                        .frame(maxWidth: 220, alignment: .leading)
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
                            .lineLimit(1)
                            .fixedSize()
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
