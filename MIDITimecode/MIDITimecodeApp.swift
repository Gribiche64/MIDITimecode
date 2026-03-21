import SwiftUI

@main
struct MIDITimecodeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 540, height: 190)
    }
}
