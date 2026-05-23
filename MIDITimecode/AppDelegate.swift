import AppKit

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let minWidth: CGFloat = 540
    private let minHeight: CGFloat = 190
    private let aspectRatio: CGFloat = 540.0 / 190.0

    private var menuBarController: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let window = NSApplication.shared.windows.first {
            window.isMovableByWindowBackground = true
            window.delegate = self
            window.minSize = NSSize(width: minWidth, height: minHeight)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        let width = max(frameSize.width, minWidth)
        let height = max(width / aspectRatio, minHeight)
        return NSSize(width: max(width, height * aspectRatio), height: height)
    }

    func installMenuBar(engine: TimecodeEngine) {
        // Idempotent — only create once
        guard menuBarController == nil else { return }
        menuBarController = MenuBarController(engine: engine)
    }
}
