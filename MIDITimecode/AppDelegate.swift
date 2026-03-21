import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Configure the main window
        if let window = NSApplication.shared.windows.first {
            window.isMovableByWindowBackground = true
            window.level = .floating
            window.setFrame(window.frame, display: true)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        nil
    }
}
