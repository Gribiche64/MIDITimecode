import SwiftUI

@main
struct MIDITimecodeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var engine = TimecodeEngine()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(engine)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 540, height: 190)

        MenuBarExtra {
            MenuBarContentView()
                .environmentObject(engine)
        } label: {
            Text(engine.timecode)
                .monospacedDigit()
        }
    }
}
