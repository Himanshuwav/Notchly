import Foundation
import SwiftUI

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

    /// SF Symbol drawn inside the gauge.
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

    var accentColor: Color {
        Color(red: accent.0, green: accent.1, blue: accent.2)
    }
}

// MARK: - Usage windows

struct UsageWindow: Identifiable, Equatable, Codable {
    let id: String
    let label: String
    /// 0...100, percent of the limit consumed.
    let usedPercent: Double
    let resetsAt: Date?
    /// Set when the window belongs to one account of several.
    var account: String?

    init(id: String, label: String, usedPercent: Double, resetsAt: Date?, account: String? = nil) {
        self.id = id
        self.label = label
        self.usedPercent = max(0, min(100, usedPercent))
        self.resetsAt = resetsAt
        self.account = account
    }

    var remainingPercent: Double { max(0, min(100, 100 - usedPercent)) }

    /// Health-driven gauge color (nootch-style tiers).
    var tierColor: Color {
        if remainingPercent <= 25 {
            return Color(red: 1.0, green: 0.32, blue: 0.15)   // coral
        } else if remainingPercent <= 50 {
            return Color(red: 0.82, green: 0.94, blue: 0.15)  // lime
        } else {
            return Color(red: 0.18, green: 0.85, blue: 0.45)  // emerald
        }
    }

    var tierGradient: LinearGradient {
        if remainingPercent <= 25 {
            return LinearGradient(colors: [Color(red: 1.0, green: 0.42, blue: 0.20),
                                           Color(red: 1.0, green: 0.22, blue: 0.10)],
                                  startPoint: .leading, endPoint: .trailing)
        } else if remainingPercent <= 50 {
            return LinearGradient(colors: [Color(red: 0.88, green: 0.98, blue: 0.22),
                                           Color(red: 0.74, green: 0.88, blue: 0.12)],
                                  startPoint: .leading, endPoint: .trailing)
        } else {
            return LinearGradient(colors: [Color(red: 0.22, green: 0.88, blue: 0.52),
                                           Color(red: 0.14, green: 0.78, blue: 0.38)],
                                  startPoint: .leading, endPoint: .trailing)
        }
    }

    var resetsInCountdown: String? {
        guard let resetsAt else { return nil }
        let interval = resetsAt.timeIntervalSinceNow
        if interval <= 0 { return "Resets soon" }
        let totalMinutes = Int(ceil(interval / 60))
        if totalMinutes < 60 { return "Resets in \(totalMinutes) min" }
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours < 24 {
            return minutes > 0 ? "Resets in \(hours)h \(minutes)m" : "Resets in \(hours)h"
        }
        let days = hours / 24
        let remHours = hours % 24
        return remHours > 0 ? "Resets in \(days)d \(remHours)h" : "Resets in \(days)d"
    }

    var formattedAbsoluteReset: String? {
        guard let resetsAt else { return nil }
        let calendar = Calendar.current
        let formatter = DateFormatter()
        if calendar.isDateInToday(resetsAt) {
            formatter.dateFormat = "'today' h:mm a"
        } else if calendar.isDateInTomorrow(resetsAt) {
            formatter.dateFormat = "'tomorrow' h:mm a"
        } else {
            formatter.dateFormat = "EEE h:mm a"
        }
        return "Resets \(formatter.string(from: resetsAt))"
    }
}

// MARK: - Provider state

enum ProviderStatus: Equatable {
    case reading
    case ok
    case signedOut
    case notInstalled
    case needsSetup
    case error(String)
}

struct ProviderState: Equatable {
    var id: ProviderID
    var status: ProviderStatus = .reading
    var windows: [UsageWindow] = []
    var note: String = ""
    var updatedAt: Date?
    var isWorking = false   // an agent session is active right now

    static func == (lhs: ProviderState, rhs: ProviderState) -> Bool {
        lhs.id == rhs.id && lhs.status == rhs.status && lhs.windows == rhs.windows
            && lhs.note == rhs.note && lhs.isWorking == rhs.isWorking
    }

    /// Worst (most consumed) window drives the ring.
    var ringUsedPercent: Double? {
        let values = windows.map(\.usedPercent)
        guard !values.isEmpty else { return nil }
        return values.max()
    }

    var ringRemainingPercent: Double? {
        ringUsedPercent.map { 100 - $0 }
    }

    var hasAttention: Bool {
        switch status {
        case .error, .signedOut, .needsSetup: return true
        default: return false
        }
    }
}

// MARK: - Appearance settings

enum ThemeColor: String, CaseIterable, Identifiable {
    case skyBlue, blue, purple, pink, red, orange, yellow, green, gray

    var id: Self { self }

    var title: String {
        switch self {
        case .skyBlue: return "Sky"
        case .blue: return "Blue"
        case .purple: return "Purple"
        case .pink: return "Pink"
        case .red: return "Red"
        case .orange: return "Orange"
        case .yellow: return "Yellow"
        case .green: return "Green"
        case .gray: return "Graphite"
        }
    }

    var color: Color {
        switch self {
        case .skyBlue: return Color(red: 0.28, green: 0.72, blue: 0.98)
        case .blue: return Color(red: 0.08, green: 0.48, blue: 1)
        case .purple: return Color(red: 0.62, green: 0.35, blue: 0.98)
        case .pink: return Color(red: 0.95, green: 0.22, blue: 0.56)
        case .red: return Color(red: 1, green: 0.25, blue: 0.28)
        case .orange: return Color(red: 1, green: 0.45, blue: 0.05)
        case .yellow: return Color(red: 1, green: 0.72, blue: 0.02)
        case .green: return Color(red: 0.32, green: 0.72, blue: 0.24)
        case .gray: return Color(white: 0.56)
        }
    }

    var solidColor: Color {
        switch self {
        case .skyBlue: return Color(red: 0.04, green: 0.15, blue: 0.22)
        case .blue: return Color(red: 0.05, green: 0.12, blue: 0.22)
        case .purple: return Color(red: 0.12, green: 0.07, blue: 0.20)
        case .pink: return Color(red: 0.20, green: 0.05, blue: 0.12)
        case .red: return Color(red: 0.22, green: 0.04, blue: 0.05)
        case .orange: return Color(red: 0.22, green: 0.09, blue: 0.02)
        case .yellow: return Color(red: 0.20, green: 0.15, blue: 0.02)
        case .green: return Color(red: 0.05, green: 0.16, blue: 0.07)
        case .gray: return Color(red: 0.14, green: 0.14, blue: 0.15)
        }
    }
}

enum WindowStyle: String, CaseIterable, Identifiable {
    case liquidGlass, translucent, solid
    var id: Self { self }
    var title: String {
        switch self {
        case .liquidGlass: return "Liquid glass"
        case .translucent: return "Translucent"
        case .solid: return "Solid"
        }
    }
}

enum UsageDisplayMode: String, CaseIterable, Identifiable {
    case remaining, used
    var id: Self { self }
    var title: String {
        switch self {
        case .remaining: return "Remaining"
        case .used: return "Used"
        }
    }
}

@MainActor
enum AppearanceSettings {
    static let themeKey = "notchly.theme"
    static let windowStyleKey = "notchly.windowStyle"
    static let displayModeKey = "notchly.usageDisplay"

    static var theme: ThemeColor {
        ThemeColor(rawValue: UserDefaults.standard.string(forKey: themeKey) ?? "") ?? .purple
    }
    static func setTheme(_ t: ThemeColor) { UserDefaults.standard.set(t.rawValue, forKey: "notchly.theme") }

    static var windowStyle: WindowStyle {
        let raw = UserDefaults.standard.string(forKey: "notchly.windowStyle") ?? ""
        let saved = WindowStyle(rawValue: raw) ?? .liquidGlass
        if #available(macOS 26.0, *) { return saved }
        return saved == .liquidGlass ? .translucent : saved
    }
    static func setWindowStyle(_ s: WindowStyle) { UserDefaults.standard.set(s.rawValue, forKey: "notchly.windowStyle") }

    static var displayMode: UsageDisplayMode {
        UsageDisplayMode(rawValue: UserDefaults.standard.string(forKey: "notchly.usageDisplay") ?? "") ?? .remaining
    }
    static func setDisplayMode(_ m: UsageDisplayMode) { UserDefaults.standard.set(m.rawValue, forKey: "notchly.usageDisplay") }
}

// MARK: - Helpers

extension Date {
    /// "4h 12m" style countdown for resets (compact, for small labels).
    static func resetLabel(for date: Date?, now: Date = Date()) -> String {
        guard let date = date else { return "" }
        let delta = date.timeIntervalSince(now)
        if delta <= 0 { return "now" }
        let hours = Int(delta) / 3600
        let minutes = (Int(delta) % 3600) / 60
        if hours >= 24 {
            let fmt = DateFormatter()
            fmt.dateFormat = "d MMM"
            return fmt.string(from: date)
        }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(max(1, minutes))m"
    }
}
