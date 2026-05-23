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
                .onAppear {
                    appDelegate.installMenuBar(engine: engine)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 540, height: 190)
    }
}
