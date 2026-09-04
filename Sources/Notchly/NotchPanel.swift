import AppKit
import SwiftUI

/// Borderless, non-activating panel pinned to an edge of the main screen:
/// a vertical tongue on the left/right side edge, or a bar at top-center.
final class NotchPanel: NSPanel {
    static let thickness: CGFloat = 38            // depth across the edge when collapsed
    static let collapsedSideLength: CGFloat = 240 // run along the side edge
    static let expandedTopSize = CGSize(width: 356, height: 224)
    static let expandedSideSize = CGSize(width: 392, height: 348)

    private(set) var side: Side
    private let store: UsageStore

    enum Side: String { case left, right, top }

    init(store: UsageStore, side: Side) {
        self.store = store
        self.side = side
        super.init(contentRect: NSRect(x: 0, y: 0, width: 240, height: Self.thickness),
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

        let view = NSHostingView(rootView:
            NotchRootView(store: store, panel: self)
                .environmentObject(AppSettings.shared)
        )
        contentView = view
        placeCollapsed()
    }

    // MARK: Placement

    private func targetFrame(size: CGSize, on screen: NSScreen) -> NSRect {
        let f = screen.frame
        switch side {
        case .top:
            return NSRect(x: f.midX - size.width / 2, y: f.maxY - size.height,
                          width: size.width, height: size.height)
        case .right:
            return NSRect(x: f.maxX - size.width, y: f.midY - size.height / 2,
                          width: size.width, height: size.height)
        case .left:
            return NSRect(x: f.minX, y: f.midY - size.height / 2,
                          width: size.width, height: size.height)
        }
    }

    private func animateTo(_ rect: NSRect) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.28
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.32, 0.9, 0.35, 1.0)
            animator().setFrame(rect, display: true)
        }
    }

    func placeCollapsed() {
        guard let screen = NSScreen.main else { return }
        let size: CGSize
        switch side {
        case .top:
            size = CGSize(width: desiredTopWidth(), height: Self.thickness)
        case .right, .left:
            size = CGSize(width: Self.thickness, height: Self.collapsedSideLength)
        }
        animateTo(targetFrame(size: size, on: screen))
    }

    func placeExpanded() {
        guard let screen = NSScreen.main else { return }
        let size = side == .top ? Self.expandedTopSize : Self.expandedSideSize
        animateTo(targetFrame(size: size, on: screen))
    }

    private func desiredTopWidth() -> CGFloat {
        let count = max(ProviderID.allCases.count, 4)
        return CGFloat(48 + count * 46)
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

    /// Keep the notch glued to its edge when displays change.
    func screenDidChange() {
        store.expanded ? placeExpanded() : placeCollapsed()
    }
}
