import CodexBarCore
import Foundation

enum CodexTokenCollector {
    static func collect(
        previous: UsageValue<CodexTokenTotals>,
        now: Date,
        scanCacheURL: URL? = nil
    ) async -> UsageValue<CodexTokenTotals> {
        do {
            let environment = ProcessInfo.processInfo.environment
            if let fixture = environment["CODEX_TOKEN_FIXTURE"] {
                let decoder = JSONDecoder()
                let value = try decoder.decode(
                    CodexTokenTotals.self,
                    from: Data(contentsOf: URL(fileURLWithPath: fixture))
                )
                return UsageValue(
                    status: .ready,
                    source: .codexBarLocal,
                    measuredAt: now,
                    lastAttemptAt: now,
                    message: nil,
                    value: value
                )
            }

            let codexHome = environment["CODEX_HOME"]
            let aggregation = try? CodexTokenAggregation.collect(
                now: now,
                environment: environment,
                localCacheURL: scanCacheURL
            )
            let cacheRoot = environment["CODEX_TOKEN_CACHE_ROOT"]
                .map { URL(fileURLWithPath: $0) }
            let snapshot: CostUsageTokenSnapshot
            do {
                snapshot = try await CostUsageFetcher(
                    cacheRoot: cacheRoot,
                    calendar: .current
                ).loadTokenSnapshot(
                    provider: .codex,
                    now: now,
                    forceRefresh: true,
                    codexHomePath: codexHome,
                    historyDays: 1,
                    allowPricingRefresh: false,
                    refreshPricingInBackground: false,
                    includePiSessions: false
                )
            } catch {
                if let desktopTotals = aggregation?.totals {
                    return UsageValue(
                        status: aggregation?.remote.complete == false ? .stale : .ready,
                        source: .codexBarLocal,
                        measuredAt: now,
                        lastAttemptAt: now,
                        message: aggregation?.remote.message,
                        value: desktopTotals
                    )
                }
                throw error
            }
            let entry = snapshot.currentDayEntry(calendar: .current)
            let input = max(0, entry?.inputTokens ?? 0)
            let output = max(0, entry?.outputTokens ?? 0)
            let totalResult = input.addingReportingOverflow(output)
            guard !totalResult.overflow else { throw CocoaError(.coderReadCorrupt) }

            let dayStart = Calendar.current.startOfDay(for: now)
            let sessions = snapshot.sessions.filter {
                $0.lastActivity >= dayStart && $0.lastActivity <= now
            }.count
            let codexBarTotals = CodexTokenTotals(
                totalTokens: totalResult.partialValue,
                inputTokens: input,
                cachedInputTokens: max(0, entry?.cacheReadTokens ?? 0),
                outputTokens: output,
                reasoningTokens: max(0, entry?.reasoningTokens ?? 0),
                sessionCount: sessions == 0 && totalResult.partialValue > 0 ? 1 : sessions
            )
            let totals: CodexTokenTotals
            let usesDesktopRecords: Bool
            if let aggregation, let desktopTotals = aggregation.totals,
               desktopTotals.totalTokens > codexBarTotals.totalTokens
            {
                totals = desktopTotals
                usesDesktopRecords = true
            } else {
                totals = try CodexTokenAggregation.adding(
                    codexBarTotals,
                    aggregation?.remoteUniqueTotals
                )
                usesDesktopRecords = aggregation?.remoteUniqueTotals != nil
            }
            let isComplete = snapshot.historyCoverageIsEstablished
            let remoteIsComplete = aggregation?.remote.complete ?? true
            return UsageValue(
                status: remoteIsComplete && (usesDesktopRecords || isComplete) ? .ready : .stale,
                source: .codexBarLocal,
                measuredAt: usesDesktopRecords ? now : snapshot.updatedAt,
                lastAttemptAt: now,
                message: aggregation?.remote.message ?? (usesDesktopRecords || isComplete
                    ? nil
                    : "Indexing Codex sessions; totals may increase on the next refresh."),
                value: totals
            )
        } catch {
            return CollectorSupport.stale(
                previous: previous,
                attemptedAt: now,
                status: .error,
                message: "Codex session scan failed: \(error.localizedDescription)"
            )
        }
    }
}
