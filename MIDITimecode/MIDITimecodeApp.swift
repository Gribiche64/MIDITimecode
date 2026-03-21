import SwiftUI

@main
struct MIDITimecodeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 480, idealWidth: 520, maxWidth: 600,
                       minHeight: 140, idealHeight: 160, maxHeight: 200)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 520, height: 160)
    }
}
