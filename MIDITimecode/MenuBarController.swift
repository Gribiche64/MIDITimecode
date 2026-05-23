import AppKit
import Combine
import SwiftUI

/// Manages the menu bar status item directly via AppKit for reliable
/// font rendering (SwiftUI's MenuBarExtra ignores font modifiers on
/// some macOS versions, causing jittery non-monospaced display).
class MenuBarController {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private var cancellables = Set<AnyCancellable>()

    init(engine: TimecodeEngine) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        // Popover hosts the SwiftUI menu content
        popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 240, height: 180)
        popover.contentViewController = NSHostingController(
            rootView: MenuBarContentView().environmentObject(engine)
        )

        configureButton()

        // Subscribe to the throttled timecode and update the menu bar
        engine.$menuBarTimecode
            .receive(on: RunLoop.main)
            .sink { [weak self] tc in
                self?.updateTitle(tc)
            }
            .store(in: &cancellables)

        // Set initial title
        updateTitle(engine.menuBarTimecode)
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(togglePopover)
    }

    private func updateTitle(_ timecode: String) {
        guard let button = statusItem.button else { return }

        // Build an attributed string with explicit monospaced font.
        // Using NSFont.monospacedDigitSystemFont gives us proper menu-bar-
        // sized digits with guaranteed equal advance widths.
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        ]
        button.attributedTitle = NSAttributedString(string: timecode, attributes: attrs)
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
