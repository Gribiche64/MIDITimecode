import SwiftUI

@main
struct MIDITimecodeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    // SwiftUI can evaluate an App's state-object initialiser more than once at
    // launch; a shared instance guarantees one engine, one audio tap, one port.
    @StateObject private var engine = TimecodeEngine.shared

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
        .defaultSize(width: AppDelegate.minWidth, height: AppDelegate.minHeight)
    }
}
