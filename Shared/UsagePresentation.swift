import Foundation

/// Shared presentation policy; collectors and snapshot serialization remain independent of UI.
struct UsageStatusPresentation: Equatable {
    enum Severity: Equatable {
        case normal
        case warning
        case critical
    }

    let label: String
    let icon: String
    let severity: Severity
    let detail: String

    init<Value>(_ data: UsageValue<Value>, relativeTo now: Date = .now) {
        if data.isStale {
            let isOld = (data.age(at: now) ?? 0) >= 3 * 60 * 60
            label = isOld ? "Old cache" : "Stale"
            icon = "clock.badge.exclamationmark.fill"
            severity = isOld ? .critical : .warning
        } else {
            switch data.status {
            case .ready:
                label = data.source == .preview ? "Demo" : "Live"
                icon = "checkmark.circle.fill"
                severity = .normal
            case .stale:
                label = "Stale"
                icon = "clock.badge.exclamationmark.fill"
                severity = .warning
            case .unauthenticated:
                label = "Sign in"
                icon = "person.crop.circle.badge.exclamationmark"
                severity = .warning
            case .unavailable:
                label = "No data"
                icon = "minus.circle.fill"
                severity = .warning
            case .error:
                label = "Error"
                icon = "exclamationmark.triangle.fill"
                severity = .critical
            }
        }
        detail = [
            label,
            UsageFormatting.source(data.source),
            "updated \(UsageFormatting.relativeAge(data.measuredAt, relativeTo: now))",
            data.message
        ].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

struct CodexDailyTokenPresentation {
    let data: UsageValue<CodexTokenTotals>
    let value: String
    let accessibilityText: String
    let status: UsageStatusPresentation
    let warningLabel: String

    init(_ original: UsageValue<CodexTokenTotals>, relativeTo now: Date = .now, calendar: Calendar = .current) {
        if original.source != .preview,
           let measuredAt = original.measuredAt,
           !calendar.isDate(measuredAt, inSameDayAs: now) {
            data = UsageValue(status: .unavailable, source: .none, measuredAt: nil,
                              lastAttemptAt: original.lastAttemptAt,
                              message: "Today's usage is awaiting refresh.", value: nil)
        } else {
            data = original
        }
        value = UsageFormatting.tokens(data.value?.totalTokens)
        status = UsageStatusPresentation(data, relativeTo: now)
        warningLabel = data.message?.localizedCaseInsensitiveContains("remote") == true
            ? "Remote" : status.label
        let count = data.value.map { "\($0.totalTokens.formatted()) tokens" } ?? "unavailable"
        accessibilityText = "Codex today, \(count), \(status.detail)"
    }
}
