import SwiftUI

struct MenuBarContentView: View {
    @EnvironmentObject var engine: TimecodeEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Status row
            HStack {
                Text(engine.inputMode.rawValue)
                    .fontWeight(.medium)
                Text("·")
                    .foregroundStyle(.secondary)
                statusText
            }

            Divider()

            // Source info
            switch engine.inputMode {
            case .mtc:
                Text("MIDI: \(engine.midiManager.selectedDevice?.name ?? "None")")
            case .ltc:
                Text("Audio: \(engine.audioManager.selectedDevice?.name ?? "None")")
                if let device = engine.audioManager.selectedDevice, device.inputChannelCount > 1 {
                    Text("Channel: \(engine.audioManager.selectedChannel + 1)")
                }
            }

            if engine.virtualMTCEnabled {
                Text("MTC Out: Active")
                    .foregroundStyle(.orange)
            }

            Divider()

            Button("Quit MIDITimecode") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(8)
    }

    private var statusText: some View {
        Group {
            if engine.inputMode == .ltc {
                if engine.isLocked {
                    Text(engine.frameRate + (engine.isReversing ? " REV" : ""))
                        .foregroundStyle(.green)
                } else if engine.signalLevel > 0.01 {
                    Text("Locking...")
                        .foregroundStyle(.yellow)
                } else {
                    Text("No Signal")
                        .foregroundStyle(.secondary)
                }
            } else {
                if engine.frameRate.isEmpty {
                    Text("No MTC")
                        .foregroundStyle(.secondary)
                } else {
                    Text(engine.frameRate)
                        .foregroundStyle(.orange)
                }
            }
        }
    }
}
