import SwiftUI
import WidgetKit

extension UsageSnapshot {
    static var widgetStalePreview: UsageSnapshot {
        let measuredAt = Date().addingTimeInterval(-4 * 3_600)
        return UsageSnapshot(
            schemaVersion: currentSchemaVersion,
            generatedAt: .now,
            codexTokens: preview.codexTokens,
            cursorCosts: preview.cursorCosts,
            cursorQuota: UsageValue(
                status: .stale,
                source: .cache,
                measuredAt: measuredAt,
                lastAttemptAt: .now,
                message: "Network unavailable.",
                value: preview.cursorQuota.value
            ),
            codexQuota: UsageValue(
                status: .stale,
                source: .cache,
                measuredAt: measuredAt,
                lastAttemptAt: .now,
                message: "Network unavailable.",
                value: preview.codexQuota.value
            ),
            deepseekUsage: UsageValue(
                status: .stale,
                source: .cache,
                measuredAt: measuredAt,
                lastAttemptAt: .now,
                message: "Network unavailable.",
                value: preview.deepseekUsage.value
            )
        )
    }

    static var widgetNoResetPreview: UsageSnapshot {
        let cursor = preview.cursorQuota.value
        let codex = preview.codexQuota.value
        return UsageSnapshot(
            schemaVersion: currentSchemaVersion,
            generatedAt: .now,
            codexTokens: preview.codexTokens,
            cursorCosts: preview.cursorCosts,
            cursorQuota: UsageValue(
                status: .ready,
                source: .cursorDashboard,
                measuredAt: .now,
                lastAttemptAt: .now,
                message: nil,
                value: cursor.map {
                    CompactQuota(
                        label: $0.label,
                        used: $0.used,
                        limit: $0.limit,
                        remaining: $0.remaining,
                        remainingPercent: $0.remainingPercent,
                        resetAt: nil,
                        windowSeconds: $0.windowSeconds,
                        detail: $0.detail
                    )
                }
            ),
            codexQuota: UsageValue(
                status: .ready,
                source: .accountAPI,
                measuredAt: .now,
                lastAttemptAt: .now,
                message: nil,
                value: codex.map {
                    CompactQuota(
                        label: $0.label,
                        used: $0.used,
                        limit: $0.limit,
                        remaining: $0.remaining,
                        remainingPercent: $0.remainingPercent,
                        resetAt: nil,
                        windowSeconds: $0.windowSeconds,
                        detail: $0.detail
                    )
                }
            ),
            deepseekUsage: preview.deepseekUsage
        )
    }

    static var widgetDeepSeekSignedOutPreview: UsageSnapshot {
        replacingDeepSeek(
            UsageValue(
                status: .unauthenticated,
                source: .none,
                measuredAt: nil,
                lastAttemptAt: .now,
                message: "Connect DeepSeek in your browser.",
                value: nil
            )
        )
    }

    static var widgetDeepSeekErrorPreview: UsageSnapshot {
        replacingDeepSeek(
            UsageValue(
                status: .error,
                source: .none,
                measuredAt: nil,
                lastAttemptAt: .now,
                message: "DeepSeek returned an unexpected response.",
                value: nil
            )
        )
    }

    static var widgetDeepSeekLongValuePreview: UsageSnapshot {
        replacingDeepSeek(
            UsageValue(
                status: .ready,
                source: .preview,
                measuredAt: .now,
                lastAttemptAt: .now,
                message: nil,
                value: DeepSeekUsageTotals(
                    monthTokens: 987_654_321,
                    monthRequests: 123_456,
                    monthCosts: [DeepSeekMoney(currency: "EUR", amount: 123_456.789)],
                    balances: [DeepSeekMoney(currency: "EUR", amount: 1_234_567.89)],
                    grantedBalances: [],
                    totalCosts: [],
                    models: []
                )
            )
        )
    }

    private static func replacingDeepSeek(_ value: UsageValue<DeepSeekUsageTotals>) -> UsageSnapshot {
        let base = UsageSnapshot.preview
        return UsageSnapshot(
            schemaVersion: base.schemaVersion,
            generatedAt: base.generatedAt,
            codexTokens: base.codexTokens,
            cursorCosts: base.cursorCosts,
            cursorQuota: base.cursorQuota,
            codexQuota: base.codexQuota,
            deepseekUsage: value
        )
    }
}

#Preview("Small", as: .systemSmall) {
    CodexWeekWidget()
} timeline: {
    CodexWeekEntry(date: .now, snapshot: .preview)
}

#Preview("Medium", as: .systemMedium) {
    CodexWeekWidget()
} timeline: {
    CodexWeekEntry(date: .now, snapshot: .preview)
}

#Preview("Large", as: .systemLarge) {
    CodexWeekWidget()
} timeline: {
    CodexWeekEntry(date: .now, snapshot: .preview)
}

#Preview("Extra Large", as: .systemExtraLarge) {
    CodexWeekWidget()
} timeline: {
    CodexWeekEntry(date: .now, snapshot: .preview)
}

#Preview("Stale", as: .systemLarge) {
    CodexWeekWidget()
} timeline: {
    CodexWeekEntry(date: .now, snapshot: .widgetStalePreview)
}

#Preview("Unavailable", as: .systemLarge) {
    CodexWeekWidget()
} timeline: {
    CodexWeekEntry(date: .now, snapshot: .unavailable)
}

#Preview("No reset", as: .systemLarge) {
    CodexWeekWidget()
} timeline: {
    CodexWeekEntry(date: .now, snapshot: .widgetNoResetPreview)
}

#Preview("DeepSeek signed out", as: .systemMedium) {
    CodexWeekWidget()
} timeline: {
    CodexWeekEntry(date: .now, snapshot: .widgetDeepSeekSignedOutPreview)
}

#Preview("DeepSeek error", as: .systemLarge) {
    CodexWeekWidget()
} timeline: {
    CodexWeekEntry(date: .now, snapshot: .widgetDeepSeekErrorPreview)
}

#Preview("DeepSeek long balance", as: .systemSmall) {
    CodexWeekWidget()
} timeline: {
    CodexWeekEntry(date: .now, snapshot: .widgetDeepSeekLongValuePreview)
}
