import Foundation

// MARK: - Factory AI (Droid billing limits)

/// The Codex token-cost scan parses gigabytes of session JSONL on first run
/// each day; it must never block the quota fetch, so it warms up in the
/// background and the row picks up the summary on a later cycle.
final class CodexCostCache: @unchecked Sendable {
    static let shared = CodexCostCache()
    private let lock = NSLock()
    private var summary: CostUsageSummary?
    private var started = false

    func current() -> CostUsageSummary? {
        lock.lock()
        let shouldStart = !started
        if shouldStart { started = true }
        let existing = summary
        lock.unlock()

        if shouldStart {
            Task.detached(priority: .utility) { [weak self] in
                let value = TokenUsageScanner.scanCodex()
                self?.store(value)
            }
        }
        return existing
    }

    private func store(_ value: CostUsageSummary) {
        lock.lock()
        summary = value
        lock.unlock()
    }
}

struct FactoryAdapter: ProviderAdapter {
    let provider: ProviderID = .factory
    static let keychainAccount = "factory-api-key"

    func detect() async -> DetectionResult {
        if Self.apiKey() != nil { return DetectionResult(detected: true, source: "Factory API key") }
        let fm = FileManager.default
        let droid = fm.isExecutableFile(atPath: "/usr/local/bin/droid")
            || fm.isExecutableFile(atPath: "/opt/homebrew/bin/droid")
        let sessions = fm.fileExists(atPath: NSHomeDirectory() + "/.factory")
        return DetectionResult(detected: droid || sessions, source: "Factory CLI")
    }

    func fetch() async -> ProviderStatus {
        let detection = await detect()
        guard let key = Self.apiKey(), !key.isEmpty else {
            return .unavailable(
                .factory,
                detected: detection.detected,
                source: detection.source,
                error: detection.detected ? "Add a Factory API key in Settings for live limits." : nil)
        }
        guard let url = URL(string: "https://api.factory.ai/api/billing/limits") else {
            return .unavailable(.factory, detected: true, source: "Factory API", error: "Invalid Factory usage endpoint.")
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw FetchFailure.invalidResponse }
            guard (200...299).contains(http.statusCode) else { throw FetchFailure.http(http.statusCode) }
            let windows = try Self.parseWindows(from: data)
            return ProviderStatus(
                provider: .factory,
                detected: true,
                source: "Factory API",
                primary: windows.first,
                secondary: windows.dropFirst().first,
                error: nil,
                updatedAt: Date())
        } catch is CancellationError {
            return .unavailable(.factory, detected: true, source: "Factory API", error: "Refresh cancelled")
        } catch {
            var message = (error as? FetchFailure)?.description ?? "Could not read Factory usage: \(error.localizedDescription)"
            if message.contains("401") || message.contains("403") {
                message = "API key rejected. Generate a new one at app.factory.ai."
            }
            return .unavailable(.factory, detected: true, source: "Factory API", error: message)
        }
    }

    static func apiKey() -> String? {
        let key = Keychain.get(account: Self.keychainAccount)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (key?.isEmpty == false) ? key : nil
    }

    private enum FetchFailure: Error {
        case invalidResponse
        case http(Int)
        var description: String {
            switch self {
            case .invalidResponse: "Invalid Factory usage response."
            case let .http(code): "Factory usage API returned HTTP \(code)."
            }
        }
    }

    /// Response shape: {"limits": {"standard": {"<windowKey>": {"usedPercent": .., "windowMinutes": .., "resetsAt": ..}}}}
    static func parseWindows(from data: Data) throws -> [UsageWindow] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let limits = root["limits"] as? [String: Any]
        else { throw FetchFailure.invalidResponse }
        var windows: [UsageWindow] = []
        for (bucketKey, tier) in limits.sorted(by: { $0.key < $1.key }) {
            guard let tierMap = tier as? [String: Any] else { continue }
            for (key, value) in tierMap.sorted(by: { $0.key < $1.key }) {
                guard let windowMap = value as? [String: Any],
                      let raw = windowMap["usedPercent"] ?? windowMap["used_percent"] ?? windowMap["utilization"],
                      let used = Self.normalizeUsed(raw)
                else { continue }
                windows.append(UsageWindow(
                    usedPercent: used,
                    windowMinutes: (windowMap["windowMinutes"] as? Int) ?? (windowMap["window_minutes"] as? Int) ?? Self.minutes(for: key),
                    resetsAt: Self.parseDate(windowMap["resetsAt"] ?? windowMap["resets_at"])))
            }
        }
        return windows
    }

    private static func minutes(for key: String) -> Int? {
        switch key.lowercased() {
        case "hourly": 60
        case "daily": 1440
        case "weekly": 10080
        case "monthly": 43200
        default: nil
        }
    }

    private static func normalizeUsed(_ any: Any) -> Double? {
        guard let v = any as? Double else { return nil }
        return max(0, min(100, v <= 1.0 ? v * 100 : v))
    }

    private static func parseDate(_ any: Any?) -> Date? {
        guard let s = any as? String else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }
}

// MARK: - Google AI (Gemini CLI / Antigravity logins, multi-account)

/// Reads the Google Cloud Code quota endpoint with each signed-in Google
/// account: the default `~/.gemini/oauth_creds.json` plus any extra accounts
/// imported in Settings, so several Google AI Pro subscriptions get one row.
struct GeminiAdapter: ProviderAdapter {
    let provider: ProviderID = .gemini

    func detect() async -> DetectionResult {
        let detected = !Self.accountPaths().isEmpty
        return DetectionResult(detected: detected, source: detected ? "Google OAuth" : nil)
    }

    func fetch() async -> ProviderStatus {
        let paths = Self.accountPaths()
        guard !paths.isEmpty else { return .unavailable(.gemini, detected: false) }

        var accounts: [AccountUsage] = []
        var failures = 0
        for (index, path) in paths.enumerated() {
            let label = paths.count > 1 ? "Account \(index + 1)" : "Google AI"
            switch await Self.fetchAccount(credPath: path) {
            case .success(let window):
                accounts.append(AccountUsage(label: label, primary: window, secondary: nil))
            case .failure:
                failures += 1
            }
        }

        guard !accounts.isEmpty else {
            return .unavailable(
                .gemini,
                detected: true,
                source: "Google OAuth",
                error: failures > 0
                    ? "Google quota check failed. Reopen Gemini CLI or Antigravity to refresh the login."
                    : "No usage reported yet for this Google account.")
        }
        if failures > 0 {
            return ProviderStatus(
                provider: .gemini, detected: true, source: "Google OAuth",
                primary: Self.worstWindow(from: accounts), secondary: nil,
                error: "Could not read \(failures) of \(paths.count) Google account(s).",
                updatedAt: Date(), accounts: accounts)
        }
        return ProviderStatus(
            provider: .gemini, detected: true, source: "Google OAuth",
            primary: Self.worstWindow(from: accounts), secondary: nil,
            error: nil, updatedAt: Date(),
            accounts: accounts.count > 1 ? accounts : nil)
    }

    static func accountPaths() -> [String] {
        var paths: [String] = []
        let main = NSHomeDirectory() + "/.gemini/oauth_creds.json"
        if FileManager.default.fileExists(atPath: main) { paths.append(main) }
        let extra = UserDefaults.standard.stringArray(forKey: "notchly.geminiCredPaths") ?? []
        for path in extra where FileManager.default.fileExists(atPath: path) && !paths.contains(path) {
            paths.append(path)
        }
        return paths
    }

    private enum AccountOutcome {
        case success(UsageWindow)
        case failure
    }

    private static func fetchAccount(credPath: String) async -> AccountOutcome {
        guard let data = FileManager.default.contents(atPath: credPath),
              let creds = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = creds["access_token"] as? String, !token.isEmpty
        else { return .failure }
        guard let url = URL(string: "https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuotaSummary") else { return .failure }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return .failure }
            guard let map = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let buckets = map["buckets"] as? [[String: Any]], !buckets.isEmpty
            else { return .failure }
            // The most-constrained bucket across models is what actually caps you.
            var worstRemaining = 1.0
            var resetsAt: Date?
            for bucket in buckets {
                if let remaining = bucket["remainingFraction"] as? Double {
                    worstRemaining = min(worstRemaining, remaining)
                }
                if let reset = bucket["resetTime"] as? String {
                    resetsAt = ISO8601DateFormatter().date(from: reset)
                }
            }
            return .success(UsageWindow(
                usedPercent: max(0, min(100, (1 - worstRemaining) * 100)),
                windowMinutes: nil,
                resetsAt: resetsAt))
        } catch {
            return .failure
        }
    }

    private static func worstWindow(from accounts: [AccountUsage]) -> UsageWindow? {
        guard let worst = accounts.compactMap(\.worstRemaining).min() else { return nil }
        let source = accounts.compactMap(\.primary).first
        return UsageWindow(
            usedPercent: 100 - worst,
            windowMinutes: source?.windowMinutes,
            resetsAt: accounts.compactMap { $0.primary?.resetsAt }.min())
    }
}

// MARK: - Multi-account Claude

/// Extends nootch's ClaudeAdapter with extra signed-in subscriptions: every
/// imported credentials file is polled and the row reports the worst window
/// across accounts, with per-account detail exposed in `accounts`.
struct MultiAccountClaudeAdapter: ProviderAdapter {
    let provider: ProviderID = .claude
    private let base = ClaudeAdapter()

    static func extraAccountPaths() -> [String] {
        (UserDefaults.standard.stringArray(forKey: "notchly.claudeCredPaths") ?? [])
            .filter { FileManager.default.fileExists(atPath: $0) }
    }

    func detect() async -> DetectionResult {
        let detection = await base.detect()
        if detection.detected || !Self.extraAccountPaths().isEmpty {
            return DetectionResult(detected: true, source: detection.source ?? "Claude OAuth")
        }
        return detection
    }

    func fetch() async -> ProviderStatus {
        let extras = Self.extraAccountPaths()
        let baseStatus = await base.fetch()

        guard !extras.isEmpty else { return baseStatus }

        var accounts: [AccountUsage] = []
        if let mainPrimary = baseStatus.primary {
            accounts.append(AccountUsage(label: "Account 1", primary: mainPrimary, secondary: baseStatus.secondary))
        }
        var failures = (baseStatus.primary == nil && baseStatus.error != nil) ? 1 : 0
        for path in extras {
            switch await Self.fetchExtraAccount(credPath: path) {
            case .success(let window):
                accounts.append(AccountUsage(label: "Account \(accounts.count + 1)", primary: window, secondary: nil))
            case .failure:
                failures += 1
            }
        }

        guard !accounts.isEmpty else {
            return .unavailable(.claude, detected: true, source: "Claude OAuth", error: baseStatus.error ?? "Could not read Claude usage.")
        }
        let worstPrimary = accounts.compactMap { $0.primary?.usedPercent }.max()
        let worstWindow = accounts.compactMap(\.primary).first.map { window in
            UsageWindow(usedPercent: worstPrimary ?? window.usedPercent,
                        windowMinutes: window.windowMinutes,
                        resetsAt: accounts.compactMap { $0.primary?.resetsAt }.min())
        }
        let note = failures > 0 ? "Could not read \(failures) Claude account(s)." : nil
        return ProviderStatus(
            provider: .claude,
            detected: true,
            source: accounts.count > 1 ? "Claude OAuth · \(accounts.count) accounts" : baseStatus.source,
            primary: worstWindow,
            secondary: nil,
            error: note,
            updatedAt: Date(),
            costUsage: baseStatus.costUsage,
            accounts: accounts.count > 1 ? accounts : nil)
    }

    private enum ExtraOutcome {
        case success(UsageWindow)
        case failure
    }

    private static func fetchExtraAccount(credPath: String) async -> ExtraOutcome {
        guard let data = FileManager.default.contents(atPath: credPath),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = object["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty
        else { return .failure }
        guard let url = URL(string: "https://api.anthropic.com/api/oauth/usage") else { return .failure }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("claude-code/2.1.0", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return .failure }
            guard let window = try JSONDecoder().decode(ClaudeUsageResponse.self, from: data).fiveHour ?? nil,
                  let usageWindow = window.usageWindow
            else { return .failure }
            return .success(usageWindow)
        } catch {
            return .failure
        }
    }

    private struct ClaudeUsageResponse: Decodable {
        let fiveHour: Window?
        enum CodingKeys: String, CodingKey { case fiveHour = "five_hour" }
    }

    private struct Window: Decodable {
        let utilization: Double?
        let resetsAt: String?
        enum CodingKeys: String, CodingKey { case utilization, resetsAt = "resets_at" }

        var usageWindow: UsageWindow? {
            guard let utilization else { return nil }
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return UsageWindow(
                usedPercent: utilization,
                windowMinutes: 300,
                resetsAt: resetsAt.flatMap { fractional.date(from: $0) ?? ISO8601DateFormatter().date(from: $0) })
        }
    }
}
