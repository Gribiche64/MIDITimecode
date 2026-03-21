import SwiftUI

struct ContentView: View {
    @StateObject private var midiManager = MIDIManager()

    var body: some View {
        ZStack {
            // Dark gradient background
            LinearGradient(
                colors: [Color(white: 0.05), Color(white: 0.1)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // Subtle radial glow behind timecode
            GeometryReader { geometry in
                VStack {
                    // Timecode display
                    TimecodeDisplayView(
                        timecode: midiManager.timecode,
                        tubeColor: midiManager.tubeColor
                    )
                    .frame(
                        minWidth: 400,
                        maxWidth: .infinity,
                        minHeight: 80,
                        maxHeight: 100
                    )
                    .padding(.top, 12)

                    // Frame rate label
                    Text(midiManager.frameRate)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color(white: 0.5))
                }
            }

            // Bottom controls overlay
            VStack {
                Spacer()

                // Device picker + Color picker
                HStack(spacing: 12) {
                    // MIDI device picker
                    VStack(alignment: .leading, spacing: 4) {
                        Text("MIDI Input Device:")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color(white: 0.5))

                        Menu {
                            if midiManager.availableDevices.isEmpty {
                                Button("No MIDI devices found") {}
                                    .disabled(true)
                            }
                            ForEach(midiManager.availableDevices) { device in
                                Button(device.name) {
                                    midiManager.selectedDevice = device
                                }
                            }
                        } label: {
                            HStack {
                                Text(midiManager.selectedDevice?.name ?? "No MIDI devices found")
                                Spacer()
                                Image(systemName: "chevron.up.chevron.down")
                                    .foregroundStyle(Color(white: 0.5))
                                    .font(.system(size: 10))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(white: 0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                    }

                    Divider()
                        .frame(height: 30)

                    // Tube color picker
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Tube Color:")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color(white: 0.5))

                        Menu {
                            ForEach(TubeColor.allCases) { color in
                                Button(color.rawValue.capitalized) {
                                    midiManager.tubeColor = color
                                }
                            }
                        } label: {
                            HStack {
                                Text(midiManager.tubeColor.rawValue.capitalized)
                                Spacer()
                                Image(systemName: "chevron.up.chevron.down")
                                    .foregroundStyle(Color(white: 0.5))
                                    .font(.system(size: 10))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(white: 0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
        }
        .onTapGesture(count: 2) {
            midiManager.scanDevices()
        }
        .background(Color.black)
    }
}
