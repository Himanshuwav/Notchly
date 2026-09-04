import Foundation

// MARK: - Provider identity

enum ProviderID: String, CaseIterable, Codable {
    case claude
    case codex
    case factory
    case gemini

    var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        case .factory: return "Factory"
        case .gemini: return "Gemini"
        }
    }

    /// SF Symbol drawn inside the ring.
    var symbolName: String {
        switch self {
        case .claude: return "asterisk"
        case .codex: return "chevron.left.forwardslash.chevron.right"
        case .factory: return "hexagon.fill"
        case .gemini: return "sparkle"
        }
    }

    var accent: (Double, Double, Double) {
        switch self {
        case .claude: return (0.851, 0.467, 0.341)   // terracotta
        case .codex: return (0.063, 0.639, 0.498)    // openai green
        case .factory: return (0.545, 0.486, 1.0)    // violet
        case .gemini: return (0.259, 0.522, 0.957)   // google blue
        }
    }
}

// MARK: - Usage windows

struct UsageWindow: Identifiable, Equatable, Codable {
    let id: String            // e.g. "five_hour"
    let label: String         // e.g. "5h window"
    /// 0...100, percent of the limit consumed.
    let usedPercent: Double
    /// When the window resets, if the vendor reports it.
    let resetsAt: Date?

    var remainingPercent: Double { max(0, min(100, 100 - usedPercent)) }
}

enum ProviderStatus: Equatable {
    case reading              // fetch in flight
    case ok                   // have data
    case signedOut            // tool present but not signed in
    case notInstalled         // tool absent on this Mac
    case needsSetup           // factory: no API key yet
    case error(String)
}

struct ProviderState: Equatable {
    var id: ProviderID
    var status: ProviderStatus = .reading
    var windows: [UsageWindow] = []
    var note: String = ""     // one-line human detail for the card
    var updatedAt: Date?

    static func == (lhs: ProviderState, rhs: ProviderState) -> Bool {
        lhs.id == rhs.id && lhs.status == rhs.status && lhs.windows == rhs.windows && lhs.note == rhs.note
    }

    /// Worst (most consumed) window drives the ring.
    var ringUsedPercent: Double? {
        let values = windows.map(\.usedPercent)
        guard !values.isEmpty else { return nil }
        return values.max()
    }
}

// MARK: - Helpers

extension Date {
    /// "4h 12m" style countdown for resets.
    static func resetLabel(for date: Date?, now: Date = Date()) -> String {
        guard let date = date else { return "" }
        let delta = date.timeIntervalSince(now)
        if delta <= 0 { return "now" }
        let hours = Int(delta) / 3600
        let minutes = (Int(delta) % 3600) / 60
        if hours >= 24 {
            let days = hours / 24
            let fmt = DateFormatter()
            fmt.dateFormat = "d MMM"
            return fmt.string(from: date)
        }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(max(1, minutes))m"
    }
}
