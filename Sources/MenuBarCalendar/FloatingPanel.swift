import AppKit

/// Borderless, non-activating panel used instead of NSPopover so we get
/// full control over the shape (no arrow/pointer) — matches Granola's
/// floating rounded-rect dropdown.
final class FloatingPanel: NSPanel {
    init(contentRect: NSRect, contentViewController: NSViewController) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.contentViewController = contentViewController
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        appearance = NSAppearance(named: .vibrantDark)
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        isMovableByWindowBackground = false
        animationBehavior = .utilityWindow
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
