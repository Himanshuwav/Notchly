import SwiftUI

// MARK: - Root

struct NotchRootView: View {
    @ObservedObject var store: UsageStore
    weak var panel: NotchPanel?

    var body: some View {
        Group {
            if store.expanded {
                ExpandedContent(store: store)
            } else {
                CollapsedBar(store: store)
            }
        }
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 20,
                bottomTrailingRadius: 20,
                topTrailingRadius: 0
            )
            .fill(Color.black.opacity(0.97))
            .shadow(color: .black.opacity(0.35), radius: 6, y: 3)
        )
        .overlay(
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 20,
                bottomTrailingRadius: 20,
                topTrailingRadius: 0
            )
            .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
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

// MARK: - Collapsed: rings in a row

struct CollapsedBar: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        HStack(spacing: 16) {
            ForEach(ProviderID.allCases, id: \.self) { id in
                RingView(state: store.states[id] ?? ProviderState(id: id), size: 26)
            }
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 6)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: store.states)
    }
}

// MARK: - Expanded: rings + cards

struct ExpandedContent: View {
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

// MARK: - Ring

struct RingView: View {
    let state: ProviderState
    let size: CGFloat
    var showPercent = false

    private var used: Double? { state.ringUsedPercent }
    private var fraction: Double { (used ?? 0) / 100 }
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
                    .stroke(Color.white.opacity(0.14), lineWidth: 3)
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
                    .foregroundStyle(.white.opacity(state.status == .ok ? 0.92 : 0.4))
            }
            .frame(width: size, height: size)
            .onAppear { pulse = true }

            if showPercent {
                Text(used != nil ? "\(Int((100 - used!).rounded()))% left" : "—")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
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

// MARK: - Expanded card per provider

struct ProviderCard: View {
    let state: ProviderState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Circle()
                    .fill(accent)
                    .frame(width: 5, height: 5)
                Text(state.id.displayName)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))
                Spacer()
            }

            if state.windows.isEmpty {
                Text(stateText)
                    .font(.system(size: 9.5, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            } else {
                ForEach(state.windows) { w in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(w.label)
                                .font(.system(size: 9, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.6))
                            Spacer()
                            Text(resetText(w))
                                .font(.system(size: 9, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.45))
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.12))
                                Capsule().fill(barColor(w.usedPercent))
                                    .frame(width: max(3, geo.size.width * CGFloat(w.usedPercent / 100)))
                            }
                        }
                        .frame(height: 3)
                    }
                }
                if !state.note.isEmpty {
                    Text(state.note)
                        .font(.system(size: 8.5, design: .rounded))
                        .foregroundStyle(.white.opacity(0.35))
                        .lineLimit(1)
                }
            }
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05))
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
