import Foundation

extension UsageSnapshot {
    static let preview: UsageSnapshot = {
        let now = Date()
        return UsageSnapshot(
            schemaVersion: Self.currentSchemaVersion,
            generatedAt: now,
            codexTokens: UsageValue(
                status: .ready,
                source: .preview,
                measuredAt: now,
                lastAttemptAt: now,
                message: nil,
                value: CodexTokenTotals(
                    totalTokens: 100_000,
                    inputTokens: 90_000,
                    cachedInputTokens: 60_000,
                    outputTokens: 10_000,
                    reasoningTokens: 2_000,
                    sessionCount: 3
                )
            ),
            cursorCosts: UsageValue(
                status: .ready,
                source: .preview,
                measuredAt: now,
                lastAttemptAt: now,
                message: nil,
                value: CursorCostTotals(
                    todayCostUSD: 0.10,
                    recentEvents: [
                        CursorCostEvent(
                            id: "one",
                            occurredAt: now.addingTimeInterval(-180),
                            model: "claude-4.5-sonnet",
                            costUSD: 0.03,
                            tokenCount: 10_000,
                            kind: "Included"
                        ),
                        CursorCostEvent(
                            id: "two",
                            occurredAt: now.addingTimeInterval(-760),
                            model: "gpt-5.6",
                            costUSD: 0.07,
                            tokenCount: 20_000,
                            kind: "On-demand"
                        ),
                        CursorCostEvent(
                            id: "three",
                            occurredAt: now.addingTimeInterval(-1_500),
                            model: "auto",
                            costUSD: 0,
                            tokenCount: 5_000,
                            kind: "Included"
                        )
                    ]
                )
            ),
            cursorQuota: UsageValue(
                status: .ready,
                source: .preview,
                measuredAt: now,
                lastAttemptAt: now,
                message: nil,
                value: CompactQuota(
                    label: "Cursor Monthly",
                    used: nil,
                    limit: nil,
                    remaining: 50,
                    remainingPercent: 50,
                    resetAt: Calendar.current.date(byAdding: .day, value: 1, to: now),
                    windowSeconds: 31 * 86_400,
                    detail: "Demo data · no account values"
                )
            ),
            codexQuota: UsageValue(
                status: .ready,
                source: .preview,
                measuredAt: now,
                lastAttemptAt: now,
                message: nil,
                value: CompactQuota(
                    label: "Codex Week",
                    used: nil,
                    limit: nil,
                    remaining: nil,
                    remainingPercent: 60,
                    resetAt: Calendar.current.date(byAdding: .day, value: 3, to: now),
                    windowSeconds: 604_800,
                    detail: "Demo data · 60% left"
                )
            )
        )
    }()
}
