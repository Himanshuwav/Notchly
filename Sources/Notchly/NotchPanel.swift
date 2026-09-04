import AppKit
import SwiftUI

/// Borderless, non-activating panel pinned to the top edge of the main screen.
final class NotchPanel: NSPanel {
    static let collapsedHeight: CGFloat = 38
    static let expandedHeight: CGFloat = 208

    private(set) var side: Side = .right
    private let store: UsageStore

    enum Side { case left, right }

    init(store: UsageStore) {
        self.store = store
        super.init(contentRect: NSRect(x: 0, y: 0, width: 240, height: Self.collapsedHeight),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        hidesOnDeactivate = false
        acceptsMouseMovedEvents = true
        isMovable = false
        animationBehavior = .utilityWindow

        let view = NSHostingView(rootView: NotchRootView(store: store, panel: self))
        contentView = view
        placeCollapsed()
    }

    // MARK: Placement

    func placeCollapsed() {
        guard let screen = NSScreen.main else { return }
        setFrame(width: desiredCollapsedWidth(), height: Self.collapsedHeight, on: screen)
    }

    func placeExpanded() {
        guard let screen = NSScreen.main else { return }
        setFrame(width: max(desiredCollapsedWidth(), 340), height: Self.expandedHeight, on: screen)
    }

    private func desiredCollapsedWidth() -> CGFloat {
        let count = max(ProviderID.allCases.count, 4)
        return CGFloat(48 + count * 46)
    }

    private func setFrame(width: CGFloat, height: CGFloat, on screen: NSScreen) {
        let screenFrame = screen.frame
        let x = side == .right ? screenFrame.maxX - width : screenFrame.minX
        let y = screenFrame.maxY - height
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.28
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.32, 0.9, 0.35, 1.0)
            animator().setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
        }
    }

    func setSide(_ side: Side) {
        self.side = side
        store.expanded ? placeExpanded() : placeCollapsed()
    }

    // MARK: Expansion

    func setExpanded(_ value: Bool) {
        store.expanded = value
        if value { placeExpanded() } else { placeCollapsed() }
    }

    override var canBecomeKey: Bool { true }

    /// Keep the notch glued to the top edge when displays change.
    func screenDidChange() {
        store.expanded ? placeExpanded() : placeCollapsed()
    }
}
