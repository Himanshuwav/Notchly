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

struct SettingsView: View {
    @ObservedObject var settings = AppSettings.shared
    @ObservedObject var store: UsageStore

    var body: some View {
        TabView {
            GeneralTab()
                .tabItem { Label("General", systemImage: "gearshape") }
            AppearanceTab()
                .tabItem { Label("Appearance", systemImage: "paintpalette") }
            ProvidersTab(store: store)
                .tabItem { Label("Accounts", systemImage: "circle.grid.2x2") }
            AboutTab()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 460, height: 360)
    }
}

// MARK: - General

struct GeneralTab: View {
    @ObservedObject var settings = AppSettings.shared

    var body: some View {
        Form {
            Picker("Notch position", selection: $settings.side) {
                Text("Right edge").tag(NotchPanelSide.right)
                Text("Left edge").tag(NotchPanelSide.left)
                Text("Top center").tag(NotchPanelSide.top)
            }
            .pickerStyle(.segmented)
            .onChange(of: settings.side) { _, newSide in
                AppDelegate.shared?.applySide(newSide)
            }

            Toggle("Open Notchly at login", isOn: $settings.launchAtLogin)

            Text("A grip pokes out of the edge — hover it and the notch unfolds. Hover a gauge for its detail card; click a gauge to pin it open.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(20)
    }
}

// MARK: - Appearance

struct AppearanceTab: View {
    @AppStorage(AppearanceSettings.themeKey) private var themeRaw = ThemeColor.purple.rawValue
    @AppStorage(AppearanceSettings.windowStyleKey) private var styleRaw = WindowStyle.liquidGlass.rawValue
    @AppStorage(AppearanceSettings.displayModeKey) private var displayRaw = UsageDisplayMode.remaining.rawValue

    var body: some View {
        Form {
            Picker("Accent", selection: $themeRaw) {
                ForEach(ThemeColor.allCases) { theme in
                    HStack(spacing: 6) {
                        Circle().fill(theme.color).frame(width: 10, height: 10)
                        Text(theme.title)
                    }.tag(theme.rawValue)
                }
            }

            Picker("Material", selection: $styleRaw) {
                ForEach(WindowStyle.allCases) { style in
                    Text(style.title).tag(style.rawValue)
                }
            }

            Picker("Gauges show", selection: $displayRaw) {
                ForEach(UsageDisplayMode.allCases) { mode in
                    Text(mode.title).tag(mode.rawValue)
                }
            }
            .pickerStyle(.segmented)

            Text("Liquid glass uses the native macOS 26 effect. Gauges turn lime under 50% remaining and coral under 25%.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(20)
    }
}

// MARK: - Accounts

struct ProvidersTab: View {
    @ObservedObject var store: UsageStore

    @State private var factoryKey: String = Keychain.get(account: "factory-api-key") ?? ""
    @State private var claudePaths: [String] = UserDefaults.standard.stringArray(forKey: "claudeCredPaths") ?? []
    @State private var geminiPaths: [String] = UserDefaults.standard.stringArray(forKey: "geminiCredPaths") ?? []

    var body: some View {
        Form {
            Section("Claude — extra accounts") {
                if claudePaths.isEmpty {
                    Text("Your main Claude Code login is read automatically. Add extra ~/.claude/.credentials.json files here to watch several accounts at once.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                accountRows(paths: claudePaths) { removed in
                    claudePaths = claudePaths.filter { $0 != removed }
                    UserDefaults.standard.set(claudePaths, forKey: "claudeCredPaths")
                    store.refreshAll()
                }
                Button("Add Claude account…") { importCreds("claudeCredPaths") }
            }

            Section("Factory AI") {
                HStack {
                    SecureField("API key from app.factory.ai", text: $factoryKey)
                    Button("Save") {
                        if factoryKey.isEmpty {
                            Keychain.delete(account: "factory-api-key")
                        } else {
                            Keychain.set(factoryKey, account: "factory-api-key")
                        }
                        store.refreshAll()
                    }
                }
                Text("Create a key at app.factory.ai/settings/api-keys for live billing limits. Without a key, Notchly counts local droid sessions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Gemini / Google AI Pro — up to nine accounts") {
                if geminiPaths.isEmpty {
                    Text("Sign in once in Antigravity or Gemini CLI, then add its oauth_creds.json here. Repeat per account.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                accountRows(paths: geminiPaths) { removed in
                    geminiPaths = geminiPaths.filter { $0 != removed }
                    UserDefaults.standard.set(geminiPaths, forKey: "geminiCredPaths")
                    store.refreshAll()
                }
                Button("Add Google account…") { importCreds("geminiCredPaths") }
            }
        }
        .padding(20)
    }

    @ViewBuilder
    private func accountRows(paths: [String], onRemove: @escaping (String) -> Void) -> some View {
        ForEach(paths, id: \.self) { path in
            HStack {
                Image(systemName: "person.crop.circle")
                Text(path)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .font(.caption)
                Spacer()
                Button(role: .destructive) {
                    onRemove(path)
                } label: {
                    Image(systemName: "minus.circle")
                }
            }
        }
    }

    private func importCreds(_ key: String) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.json]
        panel.message = "Pick a credentials file for the extra account"
        if panel.runModal() == .OK, let url = panel.url {
            var paths = UserDefaults.standard.stringArray(forKey: key) ?? []
            paths.append(url.path)
            UserDefaults.standard.set(paths, forKey: key)
            if key == "claudeCredPaths" { claudePaths = paths } else { geminiPaths = paths }
            store.refreshAll()
        }
    }
}

// MARK: - About

struct AboutTab: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "circle.righthalf.filled")
                .font(.system(size: 36))
            Text("Notchly").font(.title2.bold())
            Text("Your agents' limits, living in the notch.")
                .foregroundStyle(.secondary)
            Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                .font(.caption).foregroundStyle(.secondary)
            Text("Design language inspired by nootch and CodeNotch. Reads usage from tools already signed in on this Mac; tokens never leave your machine.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
