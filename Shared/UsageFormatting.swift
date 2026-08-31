import Foundation

enum UsageFormatting {
    static func tokens(_ value: Int?) -> String {
        guard let value else { return "—" }
        if value >= 1_000_000 {
            return String(format: value >= 10_000_000 ? "%.0fM" : "%.1fM", Double(value) / 1_000_000)
        }
        if value >= 1_000 {
            return String(format: value >= 100_000 ? "%.0fK" : "%.1fK", Double(value) / 1_000)
        }
        return value.formatted()
    }

    static func usd(_ value: Double?, minimumDigits: Int = 2, maximumDigits: Int = 4) -> String {
        guard let value else { return "—" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.currencySymbol = "$"
        formatter.minimumFractionDigits = minimumDigits
        formatter.maximumFractionDigits = maximumDigits
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "$%.2f", value)
    }

    static func usdCode(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = value.rounded() == value ? 0 : 2
        formatter.maximumFractionDigits = 2
        formatter.groupingSeparator = ","
        return "US$" + (formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value))
    }

    static func clampedPercent(_ value: Double?) -> Double? {
        value.map { min(max($0, 0), 100) }
    }

    static func relativeAge(_ date: Date?) -> String {
        guard let date else { return "never updated" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: .now)
    }

    static func reset(_ date: Date?) -> String? {
        guard let date else { return nil }
        if date <= .now { return "reset pending" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return "resets " + formatter.localizedString(for: date, relativeTo: .now)
    }

    static func resetCountdown(_ date: Date?, relativeTo now: Date = .now) -> String {
        guard let date else { return "Reset unavailable" }
        let interval = date.timeIntervalSince(now)
        guard interval > 0 else { return "Reset pending" }

        let totalMinutes = max(0, Int(interval / 60))
        let days = totalMinutes / (24 * 60)
        let hours = (totalMinutes % (24 * 60)) / 60
        let minutes = totalMinutes % 60

        if days > 0 { return "Resets in \(days)d \(hours)h" }
        if hours > 0 { return "Resets in \(hours)h \(minutes)m" }
        if minutes > 0 { return "Resets in \(minutes)m" }
        return "Resets in <1m"
    }

    static func cacheAge(_ date: Date?, relativeTo now: Date = .now) -> String? {
        guard let date else { return nil }
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 60 { return "Stale · <1m old" }
        if seconds < 3_600 { return "Stale · \(seconds / 60)m old" }
        if seconds < 86_400 { return "Stale · \(seconds / 3_600)h old" }
        return "Stale · \(seconds / 86_400)d old"
    }

    static func source(_ source: UsageDataSource) -> String {
        switch source {
        case .codexBarLocal: "CodexBar local"
        case .cursorDashboard: "Cursor Dashboard"
        case .accountAPI: "Account API"
        case .cache: "Cached"
        case .preview: "Preview"
        case .none: "No data"
        }
    }

    static func status(_ status: UsageDataStatus) -> String {
        switch status {
        case .ready: "Live"
        case .stale: "Stale"
        case .unavailable: "No data"
        case .unauthenticated: "Sign in"
        case .error: "Error"
        }
    }
}
