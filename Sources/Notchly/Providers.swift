import Foundation

// MARK: - Shared plumbing

struct HTTP {
    static func getJSON(_ url: String, headers: [String: String]) async -> Result<Any, ProviderError> {
        guard let u = URL(string: url) else { return .failure(.badResponse) }
        var req = URLRequest(url: u)
        req.timeoutInterval = 15
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else { return .failure(.badResponse) }
            guard (200..<300).contains(http.statusCode) else { return .failure(.http(http.statusCode)) }
            let obj = try JSONSerialization.jsonObject(with: data)
            return .success(obj)
        } catch {
            return .failure(.network(error))
        }
    }
}

enum ProviderError: Error {
    case badResponse
    case http(Int)
    case network(Error)

    var message: String {
        switch self {
        case .badResponse: return "Bad response"
        case .http(let code): return "HTTP \(code)"
        case .network: return "Network error"
        }
    }
}

enum CredFile {
    static func readJSON(_ path: String) -> [String: Any]? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func writeJSON(_ path: String, _ object: [String: Any]) {
        guard let out = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) else { return }
        let fm = FileManager.default
        try? fm.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        fm.createFile(atPath: path, contents: out, attributes: [.posixPermissions: 0o600])
    }

    static var home: String { NSHomeDirectory() }

    /// Modification time of the most recently touched file under a directory.
    static func newestModification(in dir: String, pathSuffix: String? = nil, directoriesOnly: Bool = false) -> Date? {
        let fm = FileManager.default
        guard let en = fm.enumerator(atPath: dir) else { return nil }
        var newest: Date?
        while let rel = en.nextObject() as? String {
            if let suffix = pathSuffix, !rel.hasSuffix(suffix) { continue }
            let full = dir + "/" + rel
            var isDir: ObjCBool = false
            fm.fileExists(atPath: full, isDirectory: &isDir)
            if directoriesOnly != isDir.boolValue { continue }
            if let attrs = try? fm.attributesOfItem(atPath: full),
               let mtime = attrs[.modificationDate] as? Date {
                if newest == nil || mtime > newest! { newest = mtime }
            }
        }
        return newest
    }

    static func isRecentlyActive(_ date: Date?, within seconds: TimeInterval = 180) -> Bool {
        guard let date else { return false }
        return Date().timeIntervalSince(date) < seconds
    }
}

let isoParser: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()

let isoParserNoFrac = ISO8601DateFormatter()

func parseDate(_ any: Any?) -> Date? {
    guard let s = any as? String else { return nil }
    return isoParser.date(from: s) ?? isoParserNoFrac.date(from: s)
}

/// Normalize a utilization number that may arrive as 0...1 or 0...100.
func normalizeUsed(_ any: Any?) -> Double? {
    guard let v = any as? Double else { return nil }
    let pct = v <= 1.0 ? v * 100 : v
    return max(0, min(100, pct))
}

func friendlyWindowLabel(id: String, minutes: Int?) -> String {
    if let m = minutes {
        switch m {
        case 300: return "5h window"
        case 10080: return "7-day window"
        case 43200: return "30-day window"
        default:
            if m >= 1440 && m % 1440 == 0 { return "\(m / 1440)-day window" }
            if m >= 60 && m % 60 == 0 { return "\(m / 60)h window" }
            return "\(m)m window"
        }
    }
    let lower = id.lowercased()
    if lower.contains("five") || lower == "5h" { return "5h window" }
    if lower.contains("week") { return "7-day window" }
    if lower.contains("month") { return "Monthly" }
    return id
}

// MARK: - Provider protocol

protocol UsageProvider {
    var id: ProviderID { get }
    func refresh() async -> ProviderState
}

extension UsageProvider {
    func baseState() -> ProviderState { ProviderState(id: id, status: .reading) }
}

// MARK: - Claude (multi-account)

struct ClaudeProvider: UsageProvider {
    let id: ProviderID = .claude

    private var mainCredPath: String { CredFile.home + "/.claude/.credentials.json" }

    /// Main Claude Code login plus any extra accounts imported in Settings.
    private var accountPaths: [String] {
        var paths: [String] = []
        if FileManager.default.fileExists(atPath: mainCredPath) { paths.append(mainCredPath) }
        let extra = UserDefaults.standard.stringArray(forKey: "claudeCredPaths") ?? []
        for p in extra where FileManager.default.fileExists(atPath: p) && !paths.contains(p) {
            paths.append(p)
        }
        return paths
    }

    func refresh() async -> ProviderState {
        var state = baseState()
        state.isWorking = CredFile.isRecentlyActive(
            CredFile.newestModification(in: CredFile.home + "/.claude/projects", pathSuffix: ".jsonl"))

        let paths = accountPaths
        guard !paths.isEmpty else {
            state.status = .signedOut
            state.note = "Sign in to Claude Code (terminal) to read usage"
            return state
        }

        var windows: [UsageWindow] = []
        var accountErrors = 0
        for (idx, path) in paths.enumerated() {
            let multi = paths.count > 1
            let accountName = multi ? "Account \(idx + 1)" : nil
            switch await fetchAccount(credPath: path) {
            case .ok(let fetched):
                for var w in fetched {
                    w.account = accountName
                    windows.append(w)
                }
            case .failure(let failure):
                accountErrors += 1
                state.note = failure
                _ = multi
            }
        }

        guard !windows.isEmpty else {
            if accountErrors > 0 {
                state.status = .error("Could not read \(accountErrors) Claude account(s)")
                if state.note.isEmpty { state.note = "Open Claude Code to refresh the login" }
            } else {
                state.status = .signedOut
                state.note = "Sign in to Claude Code to read usage"
            }
            return state
        }

        state.status = .ok
        state.windows = windows
        state.updatedAt = Date()
        if state.note.isEmpty {
            state.note = paths.count > 1 ? "\(paths.count) Claude accounts" : "Live from Anthropic"
        }
        return state
    }

    private enum ClaudeOutcome {
        case ok([UsageWindow])
        case failure(String)
    }

    private func fetchAccount(credPath: String) async -> ClaudeOutcome {
        guard let creds = CredFile.readJSON(credPath),
              let oauth = creds["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String else {
            return .failure("No Claude credentials at \(credPath)")
        }

        var token2 = token
        if let expires = oauth["expiresAt"] as? Double, Date().timeIntervalSince1970 * 1000 > expires - 60_000 {
            if let refreshed = await refreshClaudeToken(oauth: oauth, credPath: credPath) {
                token2 = refreshed
            } else {
                return .failure("Claude login expired — open Claude Code once to refresh")
            }
        }

        let result = await HTTP.getJSON("https://api.anthropic.com/api/oauth/usage", headers: [
            "Authorization": "Bearer \(token2)",
            "anthropic-version": "2023-06-01",
            "anthropic-beta": "oauth-2025-04-20",
        ])
        switch result {
        case .failure(let err):
            if case .http(401) = err { return .failure("Claude Code login is no longer valid") }
            return .failure("Could not reach Anthropic (\(err.message))")
        case .success(let obj):
            guard let map = obj as? [String: Any] else { return .failure("Unexpected Anthropic payload") }
            var windows: [UsageWindow] = []
            for key in ["five_hour", "seven_day", "seven_day_opus", "seven_day_oauth_apps"] {
                guard let w = map[key] as? [String: Any],
                      let used = normalizeUsed(w["utilization"] ?? w["used_percent"]) else { continue }
                windows.append(UsageWindow(
                    id: "\(credPath.hashValue)-\(key)",
                    label: friendlyWindowLabel(id: key, minutes: nil),
                    usedPercent: used,
                    resetsAt: parseDate(w["resets_at"] ?? w["resetsAt"])
                ))
            }
            if windows.isEmpty { return .failure("No usage windows in Anthropic payload") }
            return .ok(windows)
        }
    }

    private func refreshClaudeToken(oauth: [String: Any], credPath: String) async -> String? {
        guard let refreshToken = oauth["refreshToken"] as? String else { return nil }
        guard let url = URL(string: "https://platform.claude.com/v1/oauth/token") else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 15
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": "22422756-60c9-4084-8eb7-27705fd5cf9a",
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let newToken = obj["access_token"] as? String else { return nil }
        var updated = oauth
        updated["accessToken"] = newToken
        if let rt = obj["refresh_token"] as? String { updated["refreshToken"] = rt }
        if let exp = obj["expires_in"] as? Double {
            updated["expiresAt"] = (Date().timeIntervalSince1970 + exp) * 1000
        }
        var file = CredFile.readJSON(credPath) ?? [:]
        file["claudeAiOauth"] = updated
        CredFile.writeJSON(credPath, file)
        return newToken
    }
}

// MARK: - Codex

struct CodexProvider: UsageProvider {
    let id: ProviderID = .codex

    private var sessionsDir: String { CredFile.home + "/.codex/sessions" }

    func refresh() async -> ProviderState {
        var state = baseState()
        state.isWorking = CredFile.isRecentlyActive(
            CredFile.newestModification(in: sessionsDir, pathSuffix: ".jsonl"))

        let fm = FileManager.default
        guard fm.fileExists(atPath: CredFile.home + "/.codex") else {
            state.status = .notInstalled
            state.note = "Codex CLI is not installed on this Mac"
            return state
        }
        guard fm.fileExists(atPath: sessionsDir) else {
            state.status = .signedOut
            state.note = "Sign in to Codex to read your usage"
            return state
        }

        guard let files = latestRollouts(limit: 40), !files.isEmpty else {
            state.status = .ok
            state.note = "No Codex threads on this machine yet"
            return state
        }

        for file in files {
            if let snapshot = Self.rateLimits(inTail: file) {
                var windows: [UsageWindow] = []
                if let primary = snapshot["primary"] as? [String: Any],
                   let used = normalizeUsed(primary["used_percent"]) {
                    windows.append(UsageWindow(
                        id: "primary",
                        label: friendlyWindowLabel(id: "primary", minutes: primary["window_minutes"] as? Int),
                        usedPercent: used,
                        resetsAt: resetsIn(seconds: primary["resets_in_seconds"] as? Double)
                    ))
                }
                if let secondary = snapshot["secondary"] as? [String: Any],
                   let used = normalizeUsed(secondary["used_percent"]) {
                    windows.append(UsageWindow(
                        id: "secondary",
                        label: friendlyWindowLabel(id: "secondary", minutes: secondary["window_minutes"] as? Int),
                        usedPercent: used,
                        resetsAt: resetsIn(seconds: secondary["resets_in_seconds"] as? Double)
                    ))
                }
                if !windows.isEmpty {
                    state.status = .ok
                    state.windows = windows
                    state.updatedAt = Date()
                    state.note = "From Codex rollouts"
                    return state
                }
            }
        }
        state.status = .ok
        state.note = "Codex reported no usage windows yet"
        return state
    }

    private func resetsIn(seconds: Double?) -> Date? {
        guard let seconds = seconds else { return nil }
        return Date().addingTimeInterval(seconds)
    }

    private func latestRollouts(limit: Int) -> [String]? {
        let fm = FileManager.default
        guard let en = fm.enumerator(atPath: sessionsDir) else { return nil }
        var jsonl: [(Date, String)] = []
        while let path = en.nextObject() as? String {
            guard path.hasSuffix(".jsonl") else { continue }
            let full = sessionsDir + "/" + path
            if let attrs = try? fm.attributesOfItem(atPath: full),
               let mtime = attrs[.modificationDate] as? Date {
                jsonl.append((mtime, full))
            }
        }
        return jsonl.sorted { $0.0 > $1.0 }.prefix(limit).map(\.1)
    }

    /// Walk the JSON tree looking for a "rate_limits" dict.
    static func findRateLimits(_ any: Any) -> [String: Any]? {
        if let dict = any as? [String: Any] {
            if let rl = dict["rate_limits"] as? [String: Any], rl["primary"] != nil { return rl }
            for (_, v) in dict { if let found = findRateLimits(v) { return found } }
        } else if let arr = any as? [Any] {
            for v in arr { if let found = findRateLimits(v) { return found } }
        }
        return nil
    }

    static func rateLimits(inTail path: String) -> [String: Any]? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        let read = data.count > 262_144 ? data.suffix(262_144) : data[...]
        guard let text = String(data: read, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n").reversed() {
            guard line.contains("rate_limits") else { continue }
            var s = line
            while s.first != "{" && s.count > 1 { s.removeFirst() }
            guard let obj = try? JSONSerialization.jsonObject(with: Data(s.utf8)) else { continue }
            if let found = findRateLimits(obj) { return found }
        }
        return nil
    }
}

// MARK: - Factory

struct FactoryProvider: UsageProvider {
    let id: ProviderID = .factory

    private var sessionsDir: String { CredFile.home + "/.factory/sessions" }

    func refresh() async -> ProviderState {
        var state = baseState()
        state.isWorking = CredFile.isRecentlyActive(
            CredFile.newestModification(in: sessionsDir, directoriesOnly: true), within: 300)

        let fm = FileManager.default
        let activity = Self.todaySessionCount(in: sessionsDir)

        if let key = Keychain.get(account: "factory-api-key"), !key.isEmpty {
            let result = await HTTP.getJSON("https://api.factory.ai/api/billing/limits", headers: [
                "Authorization": "Bearer \(key)",
            ])
            switch result {
            case .failure(let err):
                if case .http(let code) = err, code == 401 || code == 403 {
                    state.status = .error("API key rejected — generate a new one")
                    state.note = "Check the key at app.factory.ai/settings/api-keys"
                } else {
                    state.status = .error(err.message)
                    state.note = activity > 0 ? "\(activity) droid sessions today (local count)" : "Could not reach Factory"
                }
            case .success(let obj):
                guard let root = obj as? [String: Any],
                      let limits = root["limits"] as? [String: Any],
                      let standard = limits["standard"] as? [String: Any] else {
                    state.status = .error("Unexpected Factory payload")
                    return state
                }
                var windows: [UsageWindow] = []
                for (key, value) in standard {
                    guard let w = value as? [String: Any] else { continue }
                    guard let used = normalizeUsed(w["usedPercent"] ?? w["used_percent"] ?? w["utilization"]) else { continue }
                    windows.append(UsageWindow(
                        id: key,
                        label: friendlyWindowLabel(id: key, minutes: w["windowMinutes"] as? Int ?? w["window_minutes"] as? Int),
                        usedPercent: used,
                        resetsAt: parseDate(w["resetsAt"] ?? w["resets_at"])
                    ))
                }
                guard !windows.isEmpty else {
                    state.status = .error("No windows in Factory payload")
                    return state
                }
                windows.sort { $0.id < $1.id }
                state.status = .ok
                state.windows = windows
                state.updatedAt = Date()
                state.note = "Live from Factory billing"
                return state
            }
            return state
        }

        state.status = .needsSetup
        state.note = activity > 0
            ? "\(activity) droid sessions today — add an API key for live limits"
            : "Add a Factory API key in Settings for live limits"
        return state
    }

    static func todaySessionCount(in dir: String) -> Int {
        let fm = FileManager.default
        guard let en = fm.enumerator(atPath: dir) else { return 0 }
        let cal = Calendar.current
        var seen = Set<String>()
        while let path = en.nextObject() as? String {
            let parts = path.split(separator: "/")
            if let first = parts.first, !first.hasPrefix(".") { seen.insert(String(first)) }
        }
        var today = 0
        for name in seen {
            let full = dir + "/" + name
            if let attrs = try? fm.attributesOfItem(atPath: full),
               let mtime = attrs[.modificationDate] as? Date, cal.isDateInToday(mtime) {
                today += 1
            }
        }
        return today
    }
}

// MARK: - Gemini / Antigravity (Google AI Pro, multi-account)

struct GeminiProvider: UsageProvider {
    let id: ProviderID = .gemini

    private var defaultCredPath: String { CredFile.home + "/.gemini/oauth_creds.json" }

    private var accountPaths: [String] {
        var paths: [String] = []
        if FileManager.default.fileExists(atPath: defaultCredPath) { paths.append(defaultCredPath) }
        let extra = UserDefaults.standard.stringArray(forKey: "geminiCredPaths") ?? []
        for p in extra where FileManager.default.fileExists(atPath: p) && !paths.contains(p) {
            paths.append(p)
        }
        return paths
    }

    func refresh() async -> ProviderState {
        var state = baseState()
        let paths = accountPaths
        guard !paths.isEmpty else {
            state.status = .signedOut
            state.note = "Sign in to Antigravity or Gemini CLI, then add the account in Settings"
            return state
        }

        var windows: [UsageWindow] = []
        var failures = 0
        for (idx, path) in paths.enumerated() {
            guard let creds = CredFile.readJSON(path),
                  let token = creds["access_token"] as? String else {
                failures += 1
                continue
            }
            let result = await HTTP.getJSON(
                "https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuotaSummary",
                headers: ["Authorization": "Bearer \(token)", "Content-Type": "application/json"]
            )
            switch result {
            case .failure:
                failures += 1
            case .success(let obj):
                guard let map = obj as? [String: Any],
                      let buckets = map["buckets"] as? [[String: Any]] else { failures += 1; continue }
                var worst = 1.0
                for b in buckets {
                    if let rem = b["remainingFraction"] as? Double { worst = min(worst, rem) }
                }
                windows.append(UsageWindow(
                    id: "gemini-\(idx)",
                    label: paths.count > 1 ? "Account \(idx + 1)" : "Gemini quota",
                    usedPercent: max(0, min(100, (1 - worst) * 100)),
                    resetsAt: parseDate(map["resetTime"] ?? map["nextReset"]),
                    account: paths.count > 1 ? "Account \(idx + 1)" : nil
                ))
            }
        }

        guard !windows.isEmpty else {
            if failures > 0 {
                state.status = .error("Google quota check failed for \(failures) account(s)")
                state.note = "Reopen Antigravity to refresh the Google login"
            } else {
                state.status = .signedOut
                state.note = "No readable Google accounts yet"
            }
            return state
        }
        state.status = .ok
        state.windows = windows
        state.updatedAt = Date()
        state.note = paths.count > 1 ? "\(paths.count) Google accounts" : "Live from Google Cloud Code"
        return state
    }
}
