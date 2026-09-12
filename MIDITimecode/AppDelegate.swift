import AppKit

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    /// Wide enough for the full settings bar on one line at any state
    /// (LTC · status · Audio: name · Ch n | MTC Freewheel · Color: Rainbow · pin).
    static let minWidth: CGFloat = 820
    static let aspectRatio: CGFloat = 540.0 / 190.0
    static var minHeight: CGFloat { (minWidth / aspectRatio).rounded() }

    private let minWidth = AppDelegate.minWidth
    private let minHeight = AppDelegate.minHeight
    private let aspectRatio = AppDelegate.aspectRatio

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
