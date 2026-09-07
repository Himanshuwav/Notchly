import AppKit
import SwiftUI

// MARK: - Interaction state

@MainActor
final class NotchInteraction: ObservableObject {
    @Published var isExpanded = false
    @Published var hoveredIndex: Int?
    @Published var pinnedOpen = false
    @Published var providerCount = 0

    func collapse() {
        isExpanded = false
        hoveredIndex = nil
        pinnedOpen = false
    }
}

// MARK: - Panel

/// A fixed-size transparent canvas pinned to the chosen screen edge. Only the
/// glass rail / island / popover content is hit-testable, so the rest of the
/// canvas lets clicks fall through to whatever is underneath.
final class NotchPanel: NSPanel {
    static let sideCanvas = CGSize(width: 400, height: 480)
    static let topCanvas = CGSize(width: 480, height: 360)

    private(set) var side: NotchPanelSide

    init(side: NotchPanelSide) {
        self.side = side
        let canvas = side == .top ? Self.topCanvas : Self.sideCanvas
        super.init(contentRect: NSRect(origin: .zero, size: canvas),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        hidesOnDeactivate = false
        isMovable = false
        place()
    }

    func setSide(_ side: NotchPanelSide) {
        self.side = side
        let canvas = side == .top ? Self.topCanvas : Self.sideCanvas
        setFrame(NSRect(origin: .zero, size: canvas), display: false)
        place()
    }

    /// Anchor the canvas to its edge; the rail is drawn inside it.
    func place() {
        guard let screen = NSScreen.main else { return }
        let f = screen.frame
        let canvas = side == .top ? Self.topCanvas : Self.sideCanvas
        let origin: CGPoint
        switch side {
        case .right:
            origin = CGPoint(x: f.maxX - canvas.width, y: f.midY - canvas.height / 2)
        case .left:
            origin = CGPoint(x: f.minX, y: f.midY - canvas.height / 2)
        case .top:
            origin = CGPoint(x: f.midX - canvas.width / 2, y: f.maxY - canvas.height)
        }
        setFrame(NSRect(origin: origin, size: canvas), display: true)
        contentView?.frame = NSRect(origin: .zero, size: canvas)
    }
}

enum NotchPanelSide: String {
    case left, right, top
}

// MARK: - Hosting & tracking

final class TrackingHostingView<Content: View>: NSHostingView<Content> {
    var onExit: (() -> Void)?
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onExit?()
    }
}

// MARK: - Controller

@MainActor
final class NotchPanelController {
    let panel: NotchPanel
    let interaction = NotchInteraction()

    private var mouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var clickMonitor: Any?
    private var collapseTask: Task<Void, Never>?

    init(side: NotchPanelSide) {
        panel = NotchPanel(side: side)
        startMonitors()
    }

    /// Mount the SwiftUI content into the panel canvas.
    func host(store: UsageStore) {
        let canvas = panel.side == .top ? NotchPanel.topCanvas : NotchPanel.sideCanvas
        let view = TrackingHostingView(rootView:
            NotchRootView(store: store, interaction: interaction, controller: self)
                .environmentObject(AppSettings.shared)
        )
        view.frame = NSRect(origin: .zero, size: canvas)
        view.sizingOptions = []
        view.autoresizingMask = [.width, .height]
        panel.contentView = view
        panel.setContentSize(canvas)
        panel.place()
        panel.orderFrontRegardless()
        updateHover()
    }

    /// Hidden debug hook: --expand opens the notch on launch. On very first
    /// run the notch also opens once so the rail is discoverable.
    func expandNowIfNeeded() {
        if CommandLine.arguments.contains("--expand") {
            interaction.isExpanded = true
        } else if !UserDefaults.standard.bool(forKey: "notchly.hasLaunched") {
            UserDefaults.standard.set(true, forKey: "notchly.hasLaunched")
            interaction.isExpanded = true
        }
    }

    func setSide(_ side: NotchPanelSide) {
        panel.setSide(side)
        interaction.collapse()
    }

    func expandNow() {
        interaction.isExpanded = true
    }

    // MARK: regions (screen coordinates)

    /// Collapsed tab + a forgiving corridor toward the screen edge.
    private func triggerRegion() -> NSRect {
        let frame = panel.frame
        switch panel.side {
        case .right:
            return NSRect(x: frame.maxX - 88, y: frame.minY, width: 88, height: frame.height)
        case .left:
            return NSRect(x: frame.minX, y: frame.minY, width: 88, height: frame.height)
        case .top:
            return NSRect(x: frame.midX - 180, y: frame.maxY - 72, width: 360, height: 72)
        }
    }

    private func expandedContentRegion() -> NSRect {
        let frame = panel.frame
        switch panel.side {
        case .right:
            return NSRect(x: frame.maxX - 400, y: frame.minY, width: 400, height: frame.height)
        case .left:
            return NSRect(x: frame.minX, y: frame.minY, width: 400, height: frame.height)
        case .top:
            return frame
        }
    }

    // MARK: mouse tracking

    private func startMonitors() {
        let mouseMask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .scrollWheel]
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: mouseMask) { [weak self] _ in
            Task { @MainActor [weak self] in self?.updateHover() }
        }
        // Global monitors miss events delivered to our own windows; keep hover
        // working over the panel itself with a local monitor.
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            Task { @MainActor [weak self] in self?.updateHover() }
            return event
        }
        let clickMask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown]
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: clickMask) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.interaction.isExpanded, !self.interaction.pinnedOpen else { return }
                self.interaction.collapse()
            }
        }
    }

    func updateHover() {
        let location = NSEvent.mouseLocation
        let insideTrigger = triggerRegion().contains(location)
        let insideContent = interaction.isExpanded && expandedContentRegion().contains(location)

        if insideTrigger || insideContent {
            cancelCollapse()
            if !interaction.isExpanded {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                    interaction.isExpanded = true
                }
            }
            if interaction.isExpanded && panel.side != .top {
                interaction.hoveredIndex = hoveredRailIndex(at: location)
            }
        } else if interaction.isExpanded && !interaction.pinnedOpen {
            scheduleCollapse()
        }
    }

    /// Rail items start 48pt from the canvas top and pitch 80pt.
    private func hoveredRailIndex(at location: CGPoint) -> Int? {
        let frame = panel.frame
        let topOffset = frame.maxY - location.y
        let rel = topOffset - 48
        let index = Int(floor(rel / 80))
        guard rel >= 0, index >= 0, index < interaction.providerCount else { return nil }
        return index
    }

    func scheduleCollapse() {
        guard collapseTask == nil else { return }
        collapseTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard let self, !Task.isCancelled else { return }
            guard !self.interaction.pinnedOpen else { return }
            withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
                self.interaction.collapse()
            }
            self.collapseTask = nil
        }
    }

    func cancelCollapse() {
        collapseTask?.cancel()
        collapseTask = nil
    }

    func teardown() {
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
    }
}
