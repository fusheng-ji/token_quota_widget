import Foundation

enum UsagePreviewScenario: String, CaseIterable {
    case normal, stale, unavailable, signedOut, error, refreshError, zero, largeValues, remoteUnavailable, longList

    var snapshot: UsageSnapshot {
        let base = UsageSnapshot.preview
        let now = UsageSnapshot.previewDate
        switch self {
        case .normal: return base
        case .refreshError: return base
        case .stale: return .widgetStalePreview
        case .signedOut: return .widgetDeepSeekSignedOutPreview
        case .unavailable, .error:
            let status: UsageDataStatus = self == .error ? .error : .unavailable
            let message = self == .error ? "Could not refresh. Previous data was preserved." : "No usage data is available yet."
            return UsageSnapshot(
                schemaVersion: UsageSnapshot.currentSchemaVersion, generatedAt: now,
                codexTokens: empty(status, message: message), cursorCosts: empty(status, message: message),
                cursorQuota: empty(status, message: message), codexQuota: empty(status, message: message),
                deepseekUsage: empty(status, message: message)
            )
        case .remoteUnavailable:
            return replacing(base, codexTokens: UsageValue(
                status: .stale, source: .cache, measuredAt: now.addingTimeInterval(-120), lastAttemptAt: now,
                message: "Remote Codex is unavailable. Today's cached remote usage is included.",
                value: base.codexTokens.value
            ))
        case .zero:
            return replacing(base, codexTokens: UsageValue(
                status: .ready, source: .preview, measuredAt: now, lastAttemptAt: now,
                message: nil,
                value: CodexTokenTotals(totalTokens: 0, inputTokens: 0, cachedInputTokens: 0,
                                        outputTokens: 0, reasoningTokens: 0, sessionCount: 0)
            ))
        case .largeValues:
            return replacing(.widgetDeepSeekLongValuePreview, codexTokens: UsageValue(
                status: .ready, source: .preview, measuredAt: now, lastAttemptAt: now, message: nil,
                value: CodexTokenTotals(totalTokens: 9_876_543_210, inputTokens: 9_800_000_000,
                                       cachedInputTokens: 7_654_321_000, outputTokens: 76_543_210,
                                       reasoningTokens: 12_345_678, sessionCount: 128)
            ))
        case .longList:
            return replacing(base, cursorCosts: UsageValue(
                status: .ready, source: .preview, measuredAt: now, lastAttemptAt: now, message: nil,
                value: CursorCostTotals(todayCostUSD: 0.42, recentEvents: (0..<20).map { index in
                    CursorCostEvent(id: "preview-\(index)", occurredAt: now.addingTimeInterval(Double(-index * 180)),
                                    model: index.isMultiple(of: 2) ? "claude-long-model-name-thinking-preview" : "gpt-5.6",
                                    costUSD: 0.021, tokenCount: 120_000 + index, kind: "On-demand")
                })
            ))
        }
    }

    private func empty<Value>(_ status: UsageDataStatus, message: String) -> UsageValue<Value> {
        UsageValue(status: status, source: .none, measuredAt: nil, lastAttemptAt: UsageSnapshot.previewDate,
                   message: message, value: nil)
    }

    private func replacing(_ base: UsageSnapshot, codexTokens: UsageValue<CodexTokenTotals>? = nil,
                           cursorCosts: UsageValue<CursorCostTotals>? = nil) -> UsageSnapshot {
        UsageSnapshot(schemaVersion: base.schemaVersion, generatedAt: base.generatedAt,
                      codexTokens: codexTokens ?? base.codexTokens, cursorCosts: cursorCosts ?? base.cursorCosts,
                      cursorQuota: base.cursorQuota, codexQuota: base.codexQuota, deepseekUsage: base.deepseekUsage)
    }
}

extension UsageSnapshot {
    static var widgetStalePreview: UsageSnapshot {
        let measuredAt = previewDate.addingTimeInterval(-4 * 3_600)
        return UsageSnapshot(
            schemaVersion: currentSchemaVersion,
            generatedAt: previewDate,
            codexTokens: UsageValue(
                status: .stale, source: .cache, measuredAt: measuredAt, lastAttemptAt: previewDate,
                message: "Remote Codex is unavailable. Today's cached usage is included.", value: preview.codexTokens.value
            ),
            cursorCosts: preview.cursorCosts,
            cursorQuota: UsageValue(
                status: .stale,
                source: .cache,
                measuredAt: measuredAt,
                lastAttemptAt: previewDate,
                message: "Network unavailable.",
                value: preview.cursorQuota.value
            ),
            codexQuota: UsageValue(
                status: .stale,
                source: .cache,
                measuredAt: measuredAt,
                lastAttemptAt: previewDate,
                message: "Network unavailable.",
                value: preview.codexQuota.value
            ),
            deepseekUsage: UsageValue(
                status: .stale,
                source: .cache,
                measuredAt: measuredAt,
                lastAttemptAt: previewDate,
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
            generatedAt: previewDate,
            codexTokens: preview.codexTokens,
            cursorCosts: preview.cursorCosts,
            cursorQuota: UsageValue(
                status: .ready,
                source: .cursorDashboard,
                measuredAt: previewDate,
                lastAttemptAt: previewDate,
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
                measuredAt: previewDate,
                lastAttemptAt: previewDate,
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
                lastAttemptAt: previewDate,
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
                lastAttemptAt: previewDate,
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
                measuredAt: previewDate,
                lastAttemptAt: previewDate,
                message: nil,
                value: DeepSeekUsageTotals(
                    monthTokens: 987_654_321,
                    monthRequests: 123_456,
                    monthCosts: [DeepSeekMoney(currency: "EUR", amount: 123_456.789)],
                    balances: [DeepSeekMoney(currency: "EUR", amount: 1_234_567.89)],
                    grantedBalances: [],
                    totalCosts: []
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
