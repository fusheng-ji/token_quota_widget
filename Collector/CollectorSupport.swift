import Foundation

enum CollectorSupport {
    static func stale<Value: Codable & Hashable & Sendable>(
        previous: UsageValue<Value>,
        attemptedAt: Date,
        status: UsageDataStatus,
        message: String
    ) -> UsageValue<Value> {
        guard let value = previous.value else {
            return UsageValue(
                status: status,
                source: .none,
                measuredAt: nil,
                lastAttemptAt: attemptedAt,
                message: message,
                value: nil
            )
        }
        return UsageValue(
            status: .stale,
            source: .cache,
            measuredAt: previous.measuredAt,
            lastAttemptAt: attemptedAt,
            message: message,
            value: value
        )
    }

    static func status(for error: Error) -> UsageDataStatus {
        if case CursorDashboardError.notLoggedIn = error { return .unauthenticated }
        if case CursorDashboardError.notInstalled = error { return .unauthenticated }
        return .error
    }

    static func formatUSD(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.currencySymbol = "US$"
        formatter.minimumFractionDigits = value.rounded() == value ? 0 : 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "US$%.2f", value)
    }

    static func parseISODate(_ string: String?) -> Date? {
        guard let string else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: string) ?? ISO8601DateFormatter().date(from: string)
    }
}
