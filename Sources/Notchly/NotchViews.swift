import SwiftUI

// MARK: - Root

struct NotchRootView: View {
    @ObservedObject var store: UsageStore
    @EnvironmentObject var settings: AppSettings
    weak var panel: NotchPanel?

    private var side: NotchPanel.Side { settings.side }

    /// Rounded corners live on the free edge; the attached edge stays square.
    private var notchShape: UnevenRoundedRectangle {
        switch side {
        case .top:
            return UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 20,
                                          bottomTrailingRadius: 20, topTrailingRadius: 0)
        case .right:
            return UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: 20,
                                          bottomTrailingRadius: 0, topTrailingRadius: 0)
        case .left:
            return UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 0,
                                          bottomTrailingRadius: 20, topTrailingRadius: 20)
        }
    }

    var body: some View {
        Group {
            if store.expanded {
                ExpandedContent(store: store, side: side)
            } else {
                CollapsedContent(store: store, side: side)
            }
        }
        .background(
            notchShape
                .fill(Color.black.opacity(0.97))
                .shadow(color: .black.opacity(0.35), radius: 6, y: 3)
        )
        .overlay(
            notchShape
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
        )
        .onHover { hovering in
            panel?.setExpanded(hovering)
        }
        .contextMenu {
            Button("Refresh now") { store.refreshAll() }
            Button("Settings…") { AppDelegate.shared?.openSettings() }
            Divider()
            Button("Quit Notchly") { NSApp.terminate(nil) }
        }
    }
}

// MARK: - Collapsed

struct CollapsedContent: View {
    @ObservedObject var store: UsageStore
    let side: NotchPanel.Side

    var body: some View {
        switch side {
        case .top: CollapsedBar(store: store)
        case .right, .left: CollapsedColumn(store: store, side: side)
        }
    }
}

/// Top-center: rings side by side with a downward grip.
struct CollapsedBar: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        HStack(spacing: 16) {
            ForEach(ProviderID.allCases, id: \.self) { id in
                RingView(state: store.states[id] ?? ProviderState(id: id), size: 26)
            }
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.35))
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 6)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: store.states)
    }
}

/// Side edges: rings stacked vertically with a grip pointing inward.
struct CollapsedColumn: View {
    @ObservedObject var store: UsageStore
    let side: NotchPanel.Side

    private var grip: String {
        side == .right ? "chevron.left" : "chevron.right"
    }

    var body: some View {
        HStack(spacing: 8) {
            if side == .right {
                Image(systemName: grip)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.4))
            }
            VStack(spacing: 14) {
                ForEach(ProviderID.allCases, id: \.self) { id in
                    RingView(state: store.states[id] ?? ProviderState(id: id), size: 20)
                }
            }
            if side == .left {
                Image(systemName: grip)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, side == .right ? 6 : 6)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: store.states)
    }
}

// MARK: - Expanded

struct ExpandedContent: View {
    @ObservedObject var store: UsageStore
    let side: NotchPanel.Side

    var body: some View {
        switch side {
        case .top: ExpandedHorizontal(store: store)
        case .right, .left: ExpandedVertical(store: store)
        }
    }
}

/// Top-center expansion: rings on top, cards side by side.
struct ExpandedHorizontal: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 20) {
                ForEach(ProviderID.allCases, id: \.self) { id in
                    RingView(state: store.states[id] ?? ProviderState(id: id), size: 34, showPercent: true)
                }
            }
            .padding(.top, 12)

            Divider().background(Color.white.opacity(0.12))

            HStack(spacing: 8) {
                ForEach(ProviderID.allCases, id: \.self) { id in
                    ProviderCard(state: store.states[id] ?? ProviderState(id: id))
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)

            Spacer(minLength: 0)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: store.states)
    }
}

/// Side expansion: one readable row per provider.
struct ExpandedVertical: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        VStack(spacing: 8) {
            ForEach(ProviderID.allCases, id: \.self) { id in
                ProviderRow(state: store.states[id] ?? ProviderState(id: id))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: store.states)
    }
}

// MARK: - Ring

struct RingView: View {
    let state: ProviderState
    let size: CGFloat
    var showPercent = false

    private var used: Double? { state.ringUsedPercent }
    private var color: Color {
        guard let used = used else { return accentColor }
        let remaining = 100 - used
        if remaining <= 10 { return Color(red: 1.0, green: 0.29, blue: 0.33) }
        if remaining <= 25 { return Color(red: 1.0, green: 0.62, blue: 0.04) }
        return accentColor
    }
    private var accentColor: Color {
        let (r, g, b) = state.id.accent
        return Color(red: r, green: g, blue: b)
    }

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.16), lineWidth: 3)
                if state.status == .reading {
                    Circle()
                        .trim(from: 0.1, to: 0.55)
                        .stroke(color.opacity(0.6), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(pulse ? 360 : 0))
                        .animation(.linear(duration: 1.1).repeatForever(autoreverses: false), value: pulse)
                } else if let used = used {
                    Circle()
                        .trim(from: 0, to: CGFloat(used / 100))
                        .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                Image(systemName: state.status == .ok ? state.id.symbolName : "minus")
                    .font(.system(size: size * 0.32, weight: .bold))
                    .foregroundStyle(.white.opacity(state.status == .ok ? 0.95 : 0.45))
            }
            .frame(width: size, height: size)
            .onAppear { pulse = true }

            if showPercent {
                Text(used != nil ? "\(Int((100 - used!).rounded()))% left" : "—")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .help(hoverText)
    }

    @State private var pulse = false

    private var hoverText: String {
        switch state.status {
        case .ok: return used != nil ? "\(state.id.displayName): \(Int((100 - used!).rounded()))% left" : state.id.displayName
        case .reading: return "\(state.id.displayName): reading…"
        case .signedOut: return "\(state.id.displayName): not signed in"
        case .notInstalled: return "\(state.id.displayName): not installed"
        case .needsSetup: return "\(state.id.displayName): setup needed"
        case .error(let msg): return "\(state.id.displayName): \(msg)"
        }
    }
}

// MARK: - Expanded row (side layout)

struct ProviderRow: View {
    let state: ProviderState

    var body: some View {
        HStack(spacing: 10) {
            RingView(state: state, size: 30)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(state.id.displayName)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.95))
                    Spacer()
                    if let used = state.ringUsedPercent {
                        Text("\(Int((100 - used).rounded()))% left")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(barColor(used))
                    } else {
                        Text("—")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                }
                if state.windows.isEmpty {
                    Text(stateText)
                        .font(.system(size: 10.5, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                } else {
                    ForEach(Array(state.windows.prefix(2))) { w in
                        windowBar(w)
                    }
                    if !state.note.isEmpty {
                        Text(state.note)
                            .font(.system(size: 9.5, design: .rounded))
                            .foregroundStyle(.white.opacity(0.4))
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func windowBar(_ w: UsageWindow) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(w.label)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                if let at = w.resetsAt {
                    Text("↻ \(Date.resetLabel(for: at))")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.14))
                    Capsule().fill(barColor(w.usedPercent))
                        .frame(width: max(3, geo.size.width * CGFloat(w.usedPercent / 100)))
                }
            }
            .frame(height: 3.5)
        }
    }

    private var accent: Color {
        let (r, g, b) = state.id.accent
        return Color(red: r, green: g, blue: b)
    }

    private var stateText: String {
        switch state.status {
        case .reading: return "Reading…"
        case .signedOut: return state.note.isEmpty ? "Not signed in" : state.note
        case .notInstalled: return state.note.isEmpty ? "Not installed" : state.note
        case .needsSetup: return state.note.isEmpty ? "Setup needed" : state.note
        case .error: return state.note.isEmpty ? "Unavailable" : state.note
        case .ok: return "No usage data yet"
        }
    }

    private func barColor(_ used: Double) -> Color {
        let remaining = 100 - used
        if remaining <= 10 { return Color(red: 1.0, green: 0.29, blue: 0.33) }
        if remaining <= 25 { return Color(red: 1.0, green: 0.62, blue: 0.04) }
        return accent
    }
}

// MARK: - Expanded card (top layout)

struct ProviderCard: View {
    let state: ProviderState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Circle()
                    .fill(accent)
                    .frame(width: 5, height: 5)
                Text(state.id.displayName)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.95))
                Spacer()
            }

            if state.windows.isEmpty {
                Text(stateText)
                    .font(.system(size: 10.5, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            } else {
                ForEach(Array(state.windows.prefix(2))) { w in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(w.label)
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.7))
                            Spacer()
                            Text(resetText(w))
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.14))
                                Capsule().fill(barColor(w.usedPercent))
                                    .frame(width: max(3, geo.size.width * CGFloat(w.usedPercent / 100)))
                            }
                        }
                        .frame(height: 3.5)
                    }
                }
                if !state.note.isEmpty {
                    Text(state.note)
                        .font(.system(size: 9.5, design: .rounded))
                        .foregroundStyle(.white.opacity(0.4))
                        .lineLimit(1)
                }
            }
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var accent: Color {
        let (r, g, b) = state.id.accent
        return Color(red: r, green: g, blue: b)
    }

    private var stateText: String {
        switch state.status {
        case .reading: return "Reading…"
        case .signedOut: return state.note.isEmpty ? "Not signed in" : state.note
        case .notInstalled: return state.note.isEmpty ? "Not installed" : state.note
        case .needsSetup: return state.note.isEmpty ? "Setup needed" : state.note
        case .error: return state.note.isEmpty ? "Unavailable" : state.note
        case .ok: return "No usage data yet"
        }
    }

    private func resetText(_ w: UsageWindow) -> String {
        guard let at = w.resetsAt else { return "" }
        return "↻ \(Date.resetLabel(for: at))"
    }

    private func barColor(_ used: Double) -> Color {
        let remaining = 100 - used
        if remaining <= 10 { return Color(red: 1.0, green: 0.29, blue: 0.33) }
        if remaining <= 25 { return Color(red: 1.0, green: 0.62, blue: 0.04) }
        return accent
    }
}
