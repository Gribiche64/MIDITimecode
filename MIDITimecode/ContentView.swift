import SwiftUI

struct ContentView: View {
    @StateObject private var midiManager = MIDIManager()

    var body: some View {
        VStack(spacing: 0) {
            // Main timecode area — fills available space
            ZStack {
                // Dark gradient background
                LinearGradient(
                    colors: [Color(white: 0.05), Color(white: 0.1)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                // Timecode display — scales with window
                TimecodeDisplayView(
                    timecode: midiManager.timecode,
                    tubeColor: midiManager.tubeColor
                )
                .padding(.horizontal, 20)
                .padding(.vertical, 12)

                // (FPS badge moved to settings bar)
            }

            // Settings bar
            HStack(spacing: 0) {
                // Left group: MTC status + MIDI device
                HStack(spacing: 0) {
                    Text(midiManager.frameRate.isEmpty ? "No MTC" : midiManager.frameRate)
                        .foregroundStyle(midiManager.frameRate.isEmpty ? Color(white: 0.85) : Color.orange)
                        .padding(.horizontal, 8)

                    Divider()
                        .frame(height: 14)
                        .overlay(Color(white: 0.35))

                    Text("MIDI:")
                        .foregroundStyle(Color(white: 0.85))
                        .padding(.leading, 8)

                    Menu {
                        if midiManager.availableDevices.isEmpty {
                            Button("No MIDI devices found") {}
                                .disabled(true)
                        }
                        ForEach(midiManager.availableDevices) { device in
                            Button(action: { midiManager.selectedDevice = device }) {
                                HStack {
                                    Text(device.name)
                                    if device == midiManager.selectedDevice {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                        Divider()
                        Button("Rescan Devices") {
                            midiManager.scanDevices()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(midiManager.selectedDevice?.name ?? "None")
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
                .padding(.vertical, 4)
                .background(Color(white: 0.22))
                .clipShape(RoundedRectangle(cornerRadius: 5))

                Spacer()

                // Right group: Color + Pin
                HStack(spacing: 0) {
                    Text("Color:")
                        .foregroundStyle(Color(white: 0.85))
                        .padding(.leading, 8)

                    Menu {
                        ForEach(TubeColor.allCases) { color in
                            Button(action: { midiManager.tubeColor = color }) {
                                HStack {
                                    Text(color.rawValue.capitalized)
                                    if color == midiManager.tubeColor {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(midiManager.tubeColor.rawValue.capitalized)
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

                    Button(action: { midiManager.alwaysOnTop.toggle() }) {
                        Image(systemName: midiManager.alwaysOnTop ? "pin.fill" : "pin")
                            .font(.system(size: 11))
                            .foregroundStyle(midiManager.alwaysOnTop ? Color.orange : Color(white: 0.85))
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
}
