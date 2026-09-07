import SwiftUI
import ServiceManagement

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var side: NotchPanelSide {
        didSet { UserDefaults.standard.set(side.rawValue, forKey: "side") }
    }
    @Published var launchAtLogin: Bool {
        didSet {
            UserDefaults.standard.set(launchAtLogin, forKey: "launchAtLogin")
            do {
                if launchAtLogin {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                // Login item registration is best-effort.
            }
        }
    }

    init() {
        let sideRaw = UserDefaults.standard.string(forKey: "side") ?? NotchPanelSide.right.rawValue
        side = NotchPanelSide(rawValue: sideRaw) ?? .right
        launchAtLogin = UserDefaults.standard.bool(forKey: "launchAtLogin")
    }
}

// MARK: - Root

struct SettingsView: View {
    @ObservedObject var settings = AppSettings.shared
    @ObservedObject var store: UsageStore

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                SettingsSection("General") {
                    sectionRow {
                        Text("Version").font(.system(size: 13))
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    Divider().opacity(0.25).padding(.horizontal, 12)
                    sectionRow {
                        Text("Open Notchly at login").font(.system(size: 13))
                        Spacer()
                        Toggle("", isOn: $settings.launchAtLogin)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                    }
                }

                SettingsSection("Position") {
                    sectionRow {
                        Picker("", selection: $settings.side) {
                            Text("Right edge").tag(NotchPanelSide.right)
                            Text("Left edge").tag(NotchPanelSide.left)
                            Text("Top center").tag(NotchPanelSide.top)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .onChange(of: settings.side) { _, newSide in
                            AppDelegate.shared?.applySide(newSide)
                        }
                    }
                }

                SettingsSection("Appearance") {
                    sectionRow {
                        ThemeSwatchRow()
                    }
                    Divider().opacity(0.25).padding(.horizontal, 12)
                    sectionRow {
                        Text("Gauges show").font(.system(size: 13))
                        Spacer()
                        UsageDisplayPicker()
                    }
                }

                SettingsSection("Accounts") {
                    AccountsList(store: store)
                }

                Text("Reads usage from tools already signed in on this Mac. Tokens never leave your machine.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 6)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
        }
    }

    @ViewBuilder
    private func sectionRow(@ViewBuilder content: () -> some View) -> some View {
        HStack(spacing: 12) { content() }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
    }
}

// MARK: - Section card (nootch-style)

struct SettingsSection<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)

            VStack(spacing: 0) { content }
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor).opacity(0.35))
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.05))
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.18), Color.white.opacity(0.05), Color.black.opacity(0.12)],
                                startPoint: .top, endPoint: .bottom),
                            lineWidth: 0.8)
                )
                .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 3)
        }
    }
}

// MARK: - Appearance controls

struct ThemeSwatchRow: View {
    @AppStorage(AppearanceSettings.themeKey) private var themeRaw = ThemeColor.purple.rawValue

    var body: some View {
        HStack(spacing: 10) {
            ForEach(ThemeColor.allCases) { theme in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { themeRaw = theme.rawValue }
                } label: {
                    Circle()
                        .fill(theme.color)
                        .frame(width: 18, height: 18)
                        .overlay(
                            Circle().strokeBorder(Color.white.opacity(themeRaw == theme.rawValue ? 0.9 : 0.15),
                                                  lineWidth: themeRaw == theme.rawValue ? 2 : 1)
                        )
                        .shadow(color: theme.color.opacity(0.35), radius: themeRaw == theme.rawValue ? 3 : 0)
                }
                .buttonStyle(.plain)
                .help(theme.title)
            }
            Spacer()
            Text(ThemeColor(rawValue: themeRaw)?.title ?? "")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
}

struct UsageDisplayPicker: View {
    @AppStorage(AppearanceSettings.displayModeKey) private var displayRaw = UsageDisplayMode.remaining.rawValue

    var body: some View {
        Picker("", selection: $displayRaw) {
            ForEach(UsageDisplayMode.allCases) { mode in
                Text(mode.title).tag(mode.rawValue)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: 180)
    }
}

// MARK: - Connected accounts

struct AccountsList: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        VStack(spacing: 0) {
            accountBlock(.claude)
            Divider().opacity(0.25).padding(.horizontal, 12)
            accountBlock(.codex)
            Divider().opacity(0.25).padding(.horizontal, 12)
            accountBlock(.factory)
            Divider().opacity(0.25).padding(.horizontal, 12)
            accountBlock(.gemini)
        }
    }

    @ViewBuilder
    private func accountBlock(_ id: ProviderID) -> some View {
        let state = store.states[id] ?? ProviderState(id: id)
        VStack(spacing: 0) {
            // Header: logo, name, live status chip.
            HStack(spacing: 12) {
                ProviderMark(id: id, size: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(id.displayName).font(.system(size: 13, weight: .medium))
                    Text(headerSub(state))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                statusChip(state)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, state.status == .ok ? 4 : 8)

            // Connected accounts (extra/imported ones get a remove button).
            if state.status == .ok, !state.windows.isEmpty {
                ForEach(groupedAccounts(state), id: \.0) { group in
                    HStack(spacing: 8) {
                        Circle().fill(id.accentColor).frame(width: 4, height: 4)
                        Text(group.0)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(group.1)
                            .font(.system(size: 10.5, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                        if group.2 {
                            Button {
                                removeAccount(id, named: group.0)
                            } label: {
                                Image(systemName: "minus.circle")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 3)
                }
            }

            // Connect controls.
            connectControls(id, state: state)
        }
        .padding(.bottom, 8)
        .opacity(state.status == .notInstalled ? 0.5 : 1)
    }

    private func groupedAccounts(_ state: ProviderState) -> [(String, String, Bool)] {
        // (account label, summary, removable)
        var order: [String?] = []
        var groups: [String?: [UsageWindow]] = [:]
        for w in state.windows {
            if groups[w.account] == nil { order.append(w.account) }
            groups[w.account, default: []].append(w)
        }
        let multi = state.windows.count(where: { $0.account != nil }) > 0
        return order.map { key in
            let label = key ?? "Main login"
            let worst = groups[key]?.map(\.usedPercent).max() ?? 0
            let summary = "\(Int(max(0, 100 - worst).rounded()))% left"
            let removable = multi && key != nil
            return (label, summary, removable)
        }
    }

    private func headerSub(_ state: ProviderState) -> String {
        switch state.status {
        case .reading: return "Reading…"
        case .ok:
            if state.isWorking { return "Agent running" }
            return state.note.isEmpty ? "Signed in" : state.note
        case .signedOut: return "Not signed in"
        case .notInstalled: return "Not installed"
        case .needsSetup: return "Setup needed"
        case .error: return state.note.isEmpty ? "Unavailable" : state.note
        }
    }

    private func statusChip(_ state: ProviderState) -> some View {
        let (label, color): (String, Color) = {
            switch state.status {
            case .reading: return ("…", .secondary)
            case .ok:
                if state.isWorking { return ("Running", .white) }
                return ("Connected", Color(red: 0.18, green: 0.85, blue: 0.45))
            case .signedOut: return ("Not signed in", .secondary)
            case .notInstalled: return ("Not installed", .secondary)
            case .needsSetup: return ("Setup needed", Color(red: 1.0, green: 0.72, blue: 0.12))
            case .error: return ("Error", Color(red: 1.0, green: 0.29, blue: 0.33))
            }
        }()
        return Text(label)
            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.12)))
            .overlay(Capsule().strokeBorder(color.opacity(0.25), lineWidth: 0.6))
    }

    @ViewBuilder
    private func connectControls(_ id: ProviderID, state: ProviderState) -> some View {
        switch id {
        case .claude:
            HStack(spacing: 8) {
                Image(systemName: "plus.circle")
                Text("Add another Claude login")
            }
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(id.accentColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .onTapGesture { importCreds("claudeCredPaths", message: "Pick a Claude Code credentials.json for the extra account") }
        case .codex:
            HStack(spacing: 6) {
                Image(systemName: "terminal")
                Text("Sign in with `codex` in Terminal — windows appear after your first run")
            }
            .font(.system(size: 10.5))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        case .factory:
            FactoryKeyRow(store: store)
        case .gemini:
            HStack(spacing: 8) {
                Image(systemName: "plus.circle")
                Text("Add a Google AI Pro account")
            }
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(id.accentColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .onTapGesture { importCreds("geminiCredPaths", message: "Pick an oauth_creds.json signed in with a Google AI Pro account") }
        }
    }

    private func removeAccount(_ id: ProviderID, named label: String) {
        let key = id == .claude ? "claudeCredPaths" : "geminiCredPaths"
        var paths = UserDefaults.standard.stringArray(forKey: key) ?? []
        // Labels were "Account N" — strip by index.
        if let idx = Int(label.replacingOccurrences(of: "Account ", with: "")), idx > 0, idx <= paths.count + 1 {
            let fileIndex = idx - 1
            if id == .gemini, FileManager.default.fileExists(atPath: CredFile.home + "/.gemini/oauth_creds.json") {
                // Account 1 is the default gemini creds; extras start at 2.
                if fileIndex < paths.count { paths.remove(at: fileIndex) }
            } else if fileIndex < paths.count {
                paths.remove(at: fileIndex)
            }
            UserDefaults.standard.set(paths, forKey: key)
            store.refreshAll()
        }
    }

    private func importCreds(_ key: String, message: String) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.json]
        panel.message = message
        if panel.runModal() == .OK, let url = panel.url {
            var paths = UserDefaults.standard.stringArray(forKey: key) ?? []
            paths.append(url.path)
            UserDefaults.standard.set(paths, forKey: key)
            store.refreshAll()
        }
    }
}

struct ProviderMark: View {
    let id: ProviderID
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(id.accentColor.opacity(0.22))
                .frame(width: size, height: size)
            Image(systemName: id.symbolName)
                .font(.system(size: size * 0.46, weight: .bold))
                .foregroundStyle(id.accentColor)
        }
    }
}

struct FactoryKeyRow: View {
    @ObservedObject var store: UsageStore
    @State private var key: String = Keychain.get(account: "factory-api-key") ?? ""
    @State private var saved = false

    var body: some View {
        HStack(spacing: 8) {
            SecureField("API key from app.factory.ai", text: $key)
                .textFieldStyle(.plain)
                .font(.system(size: 11.5))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.white.opacity(0.07)))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.6))
            Button("Save") {
                if key.isEmpty {
                    Keychain.delete(account: "factory-api-key")
                } else {
                    Keychain.set(key, account: "factory-api-key")
                }
                saved = true
                store.refreshAll()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { saved = false }
            }
            .font(.system(size: 11.5, weight: .medium))
            .buttonStyle(.plain)
            .foregroundStyle(ProviderID.factory.accentColor)
            if saved {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color(red: 0.18, green: 0.85, blue: 0.45))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }
}
