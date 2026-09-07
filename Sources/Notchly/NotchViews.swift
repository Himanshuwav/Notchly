import SwiftUI

// MARK: - Layout metrics

enum RailLayout {
    static let railWidth: CGFloat = 72
    static let tabWidth: CGFloat = 22
    static let collapsedHeight: CGFloat = 64
    static let itemPitch: CGFloat = 76
    static let itemSize: CGFloat = 72
    static let topInset: CGFloat = 40
    static let settingsZone: CGFloat = 56
    static let popoverWidth: CGFloat = 300

    static func railHeight(for count: Int) -> CGFloat {
        topInset + CGFloat(max(count, 1)) * itemPitch + settingsZone
    }
}

enum IslandLayout {
    static let expandedHeight: CGFloat = 74
    static let collapsedHeight: CGFloat = 20
    static let itemWidth: CGFloat = 68
    static let itemSpacing: CGFloat = 10
    static let sidePadding: CGFloat = 24
    static let popoverWidth: CGFloat = 312

    static func expandedWidth(for count: Int) -> CGFloat {
        let n = CGFloat(max(count, 1))
        return n * itemWidth + (n - 1) * itemSpacing + sidePadding * 2
    }

    static func itemCenterX(for index: Int, islandLeft: CGFloat) -> CGFloat {
        islandLeft + sidePadding + CGFloat(index) * (itemWidth + itemSpacing) + itemWidth / 2
    }
}

// MARK: - Root

struct NotchRootView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var interaction: NotchInteraction
    @EnvironmentObject var settings: AppSettings
    weak var controller: NotchPanelController?

    private var providers: [ProviderState] {
        ProviderID.allCases.map { store.states[$0] ?? ProviderState(id: $0) }
    }

    var body: some View {
        Group {
            if settings.side == .top {
                islandLayout
            } else {
                railLayout
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity,
               alignment: railAnchor)
        .onAppear { interaction.providerCount = providers.count }
        .onChange(of: providers.count) { _, newValue in interaction.providerCount = newValue }
    }

    /// Pin the rail content to the edge it belongs to.
    private var railAnchor: Alignment {
        switch settings.side {
        case .right: return .topTrailing
        case .left: return .topLeading
        case .top: return .top
        }
    }

    // MARK: side rail (left / right edge)

    private var railLayout: some View {
        let isLeft = settings.side == .left
        let count = providers.count
        let expandedHeight = RailLayout.railHeight(for: count)

        return HStack(alignment: .top, spacing: 12) {
            if isLeft { rail }

            if let index = interaction.hoveredIndex,
               interaction.isExpanded,
               providers.indices.contains(index) {
                DetailPopoverCard(state: providers[index], pointerOnLeft: isLeft, pointerY: popoverPointerY)
                    .offset(y: popoverOffsetY)
                    .onHover { hovering in
                        if hovering {
                            controller?.cancelCollapse()
                        } else {
                            controller?.scheduleCollapse()
                        }
                    }
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.95, anchor: isLeft ? .leading : .trailing)
                            .combined(with: .opacity),
                        removal: .opacity.combined(with: .scale(scale: 0.96, anchor: isLeft ? .leading : .trailing))
                    ))
            }

            if !isLeft { rail }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: interaction.isExpanded)
    }

    private var popoverOffsetY: CGFloat {
        guard let index = interaction.hoveredIndex else { return 16 }
        return CGFloat(index) * RailLayout.itemPitch + 16
    }

    private var popoverPointerY: CGFloat { 60 }

    private var rail: some View {
        let isLeft = settings.side == .left
        let expanded = interaction.isExpanded
        let count = max(interaction.providerCount, 1)
        let shape = SideNotchShape(
            flareWidth: expanded ? 24 : 0,
            flareHeight: expanded ? 36 : 0,
            cornerRadius: expanded ? 28 : 10,
            mirrored: isLeft
        )

        return ZStack(alignment: .topTrailing) {
            VStack(spacing: 4) {
                if expanded {
                    ForEach(Array(providers.enumerated()), id: \.element.id) { index, state in
                        RailItemView(state: state, isHovered: interaction.hoveredIndex == index)
                            .frame(width: RailLayout.railWidth, height: RailLayout.itemSize)
                            .contentShape(Rectangle())
                            .onHover { hovering in
                                guard hovering else { return }
                                controller?.cancelCollapse()
                                withAnimation(.spring(response: 0.16, dampingFraction: 0.9)) {
                                    interaction.hoveredIndex = index
                                }
                            }
                            .onTapGesture {
                                withAnimation(.spring(response: 0.18, dampingFraction: 0.88)) {
                                    interaction.pinnedOpen.toggle()
                                    if interaction.pinnedOpen { interaction.hoveredIndex = index }
                                }
                            }
                    }
                }
            }
            .padding(.top, RailLayout.topInset)
            .opacity(expanded ? 1 : 0)
            .scaleEffect(expanded ? 1 : 0.85, anchor: isLeft ? .topLeading : .topTrailing)

            if expanded {
                // Tucked into the bottom of the rail, centered across its width.
                settingsCornerButton
                    .frame(width: RailLayout.railWidth)
                    .offset(y: RailLayout.railHeight(for: count) - 54)
            }

            if !expanded {
                collapsedGrip
                    .frame(width: RailLayout.tabWidth, height: RailLayout.collapsedHeight)
            }
        }
        .frame(width: expanded ? RailLayout.railWidth : RailLayout.tabWidth,
               height: expanded ? RailLayout.railHeight(for: count) : RailLayout.collapsedHeight,
               alignment: isLeft ? .topLeading : .topTrailing)
        .background(
            ThemedGlass(shape: shape)
                .shadow(color: .black.opacity(expanded ? 0.5 : 0.35),
                        radius: expanded ? 14 : 5,
                        x: isLeft ? (expanded ? 4 : 1) : (expanded ? -4 : -1),
                        y: 0)
        )
        .contentShape(shape)
        .onHover { hovering in
            if hovering {
                controller?.cancelCollapse()
            } else {
                controller?.scheduleCollapse()
                withAnimation(.spring(response: 0.2, dampingFraction: 0.9)) {
                    interaction.hoveredIndex = nil
                }
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: expanded)
    }

    /// Always-visible grip on the collapsed tab: a chevron pointing inward,
    /// with the ambient status dot above it when something needs eyes.
    private var collapsedGrip: some View {
        let isLeft = settings.side == .left
        return VStack(spacing: 5) {
            ambientDot
            Image(systemName: isLeft ? "chevron.right" : "chevron.left")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.75))
                .shadow(color: .black.opacity(0.6), radius: 2)
        }
    }

    private var ambientDot: some View {
        let needsAttention = providers.contains { $0.hasAttention }
        let working = providers.contains { $0.isWorking }
        return Group {
            if needsAttention {
                Circle()
                    .fill(Color(red: 1.0, green: 0.70, blue: 0.12))
                    .frame(width: 5, height: 5)
                    .shadow(color: Color(red: 1.0, green: 0.70, blue: 0.12), radius: 3)
            } else if working {
                Circle()
                    .fill(Color.white)
                    .frame(width: 4, height: 4)
            }
        }
    }

    private var settingsCornerButton: some View {
        Button {
            NotificationCenter.default.post(name: .openNotchlySettings, object: nil)
        } label: {
            ZStack {
                ThemedGlass(shape: Circle())
                    .frame(width: 40, height: 40)
                    .overlay(Circle().stroke(Color.white.opacity(0.24), lineWidth: 1))
                Image(systemName: "gearshape")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.white)
            }
            .shadow(color: .black.opacity(0.4), radius: 5, y: 1)
        }
        .buttonStyle(.plain)
    }

    // MARK: top island

    private var islandLayout: some View {
        let expanded = interaction.isExpanded
        let count = providers.count
        let width = expanded ? IslandLayout.expandedWidth(for: count) : 64
        let height = expanded ? IslandLayout.expandedHeight : IslandLayout.collapsedHeight
        let shape = TopIslandShape(
            flareWidth: expanded ? 16 : 0,
            flareHeight: expanded ? 16 : 0,
            cornerRadius: expanded ? 20 : 8
        )
        let islandLeft = (480 - width) / 2

        return VStack(alignment: .center, spacing: 8) {
            ZStack {
                if expanded {
                    HStack(spacing: IslandLayout.itemSpacing) {
                        ForEach(Array(providers.enumerated()), id: \.element.id) { index, state in
                            RailItemView(state: state, isHovered: interaction.hoveredIndex == index)
                                .frame(width: IslandLayout.itemWidth, height: 58)
                                .contentShape(Rectangle())
                                .onHover { hovering in
                                    guard hovering else { return }
                                    controller?.cancelCollapse()
                                    withAnimation(.spring(response: 0.16, dampingFraction: 0.9)) {
                                        interaction.hoveredIndex = index
                                    }
                                }
                                .onTapGesture {
                                    withAnimation(.spring(response: 0.18, dampingFraction: 0.88)) {
                                        interaction.pinnedOpen.toggle()
                                        if interaction.pinnedOpen { interaction.hoveredIndex = index }
                                    }
                                }
                        }
                    }
                    .padding(.horizontal, IslandLayout.sidePadding)
                    .padding(.top, 8)

                    settingsInlineButton
                        .offset(x: width / 2 + 4, y: 6)
                } else {
                    ambientDot.frame(height: 20)
                }
            }
            .frame(width: width, height: height)
            .background(
                ThemedGlass(shape: shape)
                    .shadow(color: .black.opacity(expanded ? 0.55 : 0.35), radius: expanded ? 18 : 5, y: -1)
            )
            .contentShape(shape)
            .onHover { hovering in
                if hovering {
                    controller?.cancelCollapse()
                } else {
                    controller?.scheduleCollapse()
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.9)) {
                        interaction.hoveredIndex = nil
                    }
                }
            }
            .animation(.spring(response: 0.32, dampingFraction: 0.86), value: expanded)

            if expanded, let index = interaction.hoveredIndex, providers.indices.contains(index) {
                let itemCenter = IslandLayout.itemCenterX(for: index, islandLeft: islandLeft)
                let cardX = min(max(itemCenter - IslandLayout.popoverWidth / 2, 8), 480 - IslandLayout.popoverWidth - 8)
                let pointerX = min(max(itemCenter - cardX, 28), IslandLayout.popoverWidth - 28)

                DetailPopoverCard(state: providers[index], pointerOnLeft: false, verticalPointerX: pointerX)
                    .onHover { hovering in
                        if hovering {
                            controller?.cancelCollapse()
                        } else {
                            controller?.scheduleCollapse()
                        }
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .top)))
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: interaction.isExpanded)
    }

    private var settingsInlineButton: some View {
        Button {
            NotificationCenter.default.post(name: .openNotchlySettings, object: nil)
        } label: {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 36, height: 36)
                    .overlay(Circle().stroke(Color.white.opacity(0.16), lineWidth: 0.8))
                Image(systemName: "gearshape")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .buttonStyle(.plain)
    }
}

extension Notification.Name {
    static let openNotchlySettings = Notification.Name("openNotchlySettings")
}

// MARK: - Rail item (gauge + percentage)

struct RailItemView: View {
    let state: ProviderState
    let isHovered: Bool
    @AppStorage(AppearanceSettings.displayModeKey) private var displayRaw = UsageDisplayMode.remaining.rawValue

    private var remaining: Double? { state.ringRemainingPercent }
    private var displayedPercent: Double {
        let rem = remaining ?? 0
        return AppearanceSettings.displayMode == .remaining ? rem : 100 - rem
    }
    private var gaugeColor: Color {
        guard let rem = remaining else { return state.id.accentColor }
        return UsageWindow(id: "x", label: "", usedPercent: 100 - rem, resetsAt: nil).tierColor
    }

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.14), lineWidth: 4.6)
                if state.isWorking {
                    chronograph
                } else if let rem = remaining {
                    Circle()
                        .trim(from: 0, to: max(0.02, CGFloat(rem / 100)))
                        .stroke(gaugeColor, style: StrokeStyle(lineWidth: 4.6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                if state.hasAttention && !state.isWorking {
                    Circle()
                        .fill(Color(red: 1.0, green: 0.70, blue: 0.12))
                        .frame(width: 8, height: 8)
                        .offset(x: 15, y: -15)
                }
                Image(systemName: state.id.symbolName)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white.opacity(state.status == .ok ? 0.95 : 0.55))
                    .scaleEffect(state.isWorking ? 1.04 : 1.0)
            }
            .frame(width: 38, height: 38)
            .scaleEffect(isHovered ? 1.06 : 1.0)
            .animation(.spring(response: 0.28, dampingFraction: 0.8), value: isHovered)

            Text(remaining != nil ? "\(Int(displayedPercent.rounded()))%" : "—")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
                .frame(width: 52, height: 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Perimeter tracer for an actively running agent.
    private var chronograph: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6
            Circle()
                .trim(from: phase * 0.9, to: phase * 0.9 + 0.28)
                .stroke(Color.white.opacity(0.85), style: StrokeStyle(lineWidth: 3.4, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

// MARK: - Detail popover card

struct DetailPopoverCard: View {
    let state: ProviderState
    let pointerOnLeft: Bool
    var verticalPointerX: CGFloat?
    var pointerY: CGFloat = 70

    private var accent: Color { state.id.accentColor }

    /// Group the provider's windows into account sections.
    private var accountSections: [(title: String?, windows: [UsageWindow])] {
        var order: [String?] = []
        var groups: [String?: [UsageWindow]] = [:]
        for w in state.windows {
            if groups[w.account] == nil { order.append(w.account) }
            groups[w.account, default: []].append(w)
        }
        return order.map { key in
            let title: String? = (state.windows.count(where: { $0.account != nil }) > 1) ? key : nil
            return (title, groups[key] ?? [])
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if state.windows.isEmpty {
                Text(emptyText)
                    .font(.system(size: 11.5, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            } else {
                ForEach(Array(accountSections.enumerated()), id: \.offset) { _, section in
                    accountSection(section)
                }
            }

            if !state.note.isEmpty && !state.windows.isEmpty {
                Text(state.note)
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(.white.opacity(0.4))
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 14)
        .padding(.leading, pointerOnLeft ? 24 : 16)
        .padding(.trailing, pointerOnLeft ? 16 : 24)
        .frame(width: RailLayout.popoverWidth)
        .background(cardBackground)
    }

    private var header: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(accent.opacity(0.22))
                    .frame(width: 24, height: 24)
                Image(systemName: state.id.symbolName)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(accent)
            }
            Text("\(state.id.displayName) Usage")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
            Spacer()
            if state.isWorking {
                statusChip(label: "Running", color: .white, filled: true)
            } else if case .error = state.status {
                statusChip(label: "Action Required", color: Color(red: 1.0, green: 0.72, blue: 0.12), filled: false)
            } else if let countdown = state.windows.first?.resetsInCountdown, state.windows.count == 1 {
                Text(countdown)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.white.opacity(0.48))
            }
        }
    }

    private func statusChip(label: String, color: Color, filled: Bool) -> some View {
        HStack(spacing: 5) {
            if filled {
                Circle().fill(color).frame(width: 5, height: 5)
            } else {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 9.5, weight: .bold))
            }
            Text(label)
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 7.5)
        .padding(.vertical, 3)
        .background(Capsule().fill(color.opacity(0.12)).overlay(Capsule().stroke(color.opacity(0.22), lineWidth: 0.75)))
    }

    @ViewBuilder
    private func accountSection(_ section: (title: String?, windows: [UsageWindow])) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title = section.title {
                Text(title)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.75))
            }
            ForEach(section.windows) { w in
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(section.title == nil ? w.label : windowTitle(w))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.85))
                        Spacer()
                        if let countdown = w.resetsInCountdown {
                            Text(countdown)
                                .font(.system(size: 10.5))
                                .foregroundStyle(Color.white.opacity(0.48))
                        }
                    }
                    progressBar(w)
                    HStack {
                        Text("\(Int(displayedPercent(w).rounded()))% \(AppearanceSettings.displayMode == .remaining ? "Remaining" : "Used")")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.white.opacity(0.6))
                        Spacer()
                        if let reset = w.formattedAbsoluteReset {
                            Text(reset)
                                .font(.system(size: 10.5))
                                .foregroundStyle(Color.white.opacity(0.45))
                        }
                    }
                }
            }
        }
    }

    private func windowTitle(_ w: UsageWindow) -> String {
        // Inside a titled account section, the window label carries the detail.
        w.label
    }

    private func displayedPercent(_ w: UsageWindow) -> Double {
        AppearanceSettings.displayMode == .remaining ? w.remainingPercent : w.usedPercent
    }

    private func progressBar(_ w: UsageWindow) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.14))
                    .frame(height: 5.5)
                Capsule()
                    .fill(w.tierGradient)
                    .frame(width: max(4, geo.size.width * CGFloat(min(100, max(0, displayedPercent(w))) / 100)),
                           height: 5.5)
            }
        }
        .frame(height: 5.5)
    }

    private var emptyText: String {
        switch state.status {
        case .reading: return "Reading…"
        case .signedOut: return state.note.isEmpty ? "Not signed in" : state.note
        case .notInstalled: return state.note.isEmpty ? "Not installed" : state.note
        case .needsSetup: return state.note.isEmpty ? "Setup needed" : state.note
        case .error: return state.note.isEmpty ? "Unavailable" : state.note
        case .ok: return "No usage data yet"
        }
    }

    @ViewBuilder
    private var cardBackground: some View {
        if let pointerX = verticalPointerX {
            let shape = VerticalCalloutShape(pointerX: pointerX)
            ThemedGlass(shape: shape)
                .overlay(shape.stroke(Color.white.opacity(0.12), lineWidth: 1))
                .shadow(color: .black.opacity(0.65), radius: 24, y: 10)
        } else {
            let shape = PopoverCalloutShape(pointerY: pointerY, pointerOnLeft: pointerOnLeft)
            ThemedGlass(shape: shape)
                .overlay(shape.stroke(Color.white.opacity(0.12), lineWidth: 1))
                .shadow(color: .black.opacity(0.65), radius: 24, x: pointerOnLeft ? 8 : -8, y: 10)
        }
    }
}
