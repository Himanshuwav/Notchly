import SwiftUI
import ServiceManagement

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var side: NotchPanel.Side {
        didSet { UserDefaults.standard.set(side == .right ? "right" : "left", forKey: "side") }
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
        let sideRaw = UserDefaults.standard.string(forKey: "side") ?? "right"
        side = sideRaw == "left" ? .left : .right
        launchAtLogin = UserDefaults.standard.bool(forKey: "launchAtLogin")
    }
}

struct SettingsView: View {
    @ObservedObject var settings = AppSettings.shared
    @ObservedObject var store: UsageStore

    var body: some View {
        TabView {
            GeneralTab(settings: settings)
                .tabItem { Label("General", systemImage: "gearshape") }
            ProvidersTab(store: store)
                .tabItem { Label("Providers", systemImage: "circle.grid.2x2") }
            AboutTab()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 420, height: 300)
    }
}

// MARK: - General

struct GeneralTab: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Picker("Notch side", selection: $settings.side) {
                Text("Right").tag(NotchPanel.Side.right)
                Text("Left").tag(NotchPanel.Side.left)
            }
            .pickerStyle(.segmented)

            Toggle("Open Notchly at login", isOn: $settings.launchAtLogin)

            Text("Hover the notch to expand usage cards. Right-click it for refresh and settings.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(20)
    }
}

// MARK: - Providers

struct ProvidersTab: View {
    @ObservedObject var store: UsageStore

    @State private var factoryKey: String = Keychain.get(account: "factory-api-key") ?? ""
    @State private var geminiPaths: [String] = UserDefaults.standard.stringArray(forKey: "geminiCredPaths") ?? []

    var body: some View {
        Form {
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
                Text("Create a key at app.factory.ai/settings/api-keys, then paste it here for live limits. Without a key, Notchly counts local droid sessions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Google AI Pro (Gemini / Antigravity)") {
                if geminiPaths.isEmpty {
                    Text("No accounts added yet. Sign in once in Antigravity or Gemini CLI, then add its oauth_creds.json here. Repeat per account — all nine can live side by side.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(geminiPaths, id: \.self) { path in
                    HStack {
                        Image(systemName: "person.crop.circle")
                        Text(path).lineLimit(1).truncationMode(.middle).font(.caption)
                        Spacer()
                        Button(role: .destructive) {
                            geminiPaths.removeAll { $0 == path }
                            UserDefaults.standard.set(geminiPaths, forKey: "geminiCredPaths")
                            store.refreshAll()
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                    }
                }
                Button("Add Google account…") {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = true
                    panel.canChooseDirectories = false
                    panel.allowedContentTypes = [.json]
                    panel.message = "Pick a Gemini/Antigravity oauth_creds.json"
                    if panel.runModal() == .OK, let url = panel.url {
                        geminiPaths.append(url.path)
                        UserDefaults.standard.set(geminiPaths, forKey: "geminiCredPaths")
                        store.refreshAll()
                    }
                }
            }
        }
        .padding(20)
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
            Text("Reads usage from tools already signed in on this Mac. Never asks for passwords; tokens never leave your machine.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
