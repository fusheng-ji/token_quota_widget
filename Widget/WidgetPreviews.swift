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
            )
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
