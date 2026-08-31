import CodexBarCore
import Foundation

enum CodexTokenCollector {
    static func collect(
        previous: UsageValue<CodexTokenTotals>,
        now: Date
    ) async -> UsageValue<CodexTokenTotals> {
        do {
            if let fixture = ProcessInfo.processInfo.environment["CODEX_TOKEN_FIXTURE"] {
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

            let codexHome = ProcessInfo.processInfo.environment["CODEX_HOME"]
            let snapshot = try await CostUsageFetcher(calendar: .current).loadTokenSnapshot(
                provider: .codex,
                now: now,
                forceRefresh: true,
                codexHomePath: codexHome,
                historyDays: 1,
                allowPricingRefresh: false,
                refreshPricingInBackground: false,
                includePiSessions: false
            )
            let entry = snapshot.currentDayEntry(calendar: .current)
            let input = max(0, entry?.inputTokens ?? 0)
            let output = max(0, entry?.outputTokens ?? 0)
            let totalResult = input.addingReportingOverflow(output)
            guard !totalResult.overflow else { throw CocoaError(.coderReadCorrupt) }

            let dayStart = Calendar.current.startOfDay(for: now)
            let sessions = snapshot.sessions.filter {
                $0.lastActivity >= dayStart && $0.lastActivity <= now
            }.count
            let totals = CodexTokenTotals(
                totalTokens: totalResult.partialValue,
                inputTokens: input,
                cachedInputTokens: max(0, entry?.cacheReadTokens ?? 0),
                outputTokens: output,
                reasoningTokens: max(0, entry?.reasoningTokens ?? 0),
                sessionCount: sessions == 0 && totalResult.partialValue > 0 ? 1 : sessions
            )
            let isComplete = snapshot.historyCoverageIsEstablished
            return UsageValue(
                status: isComplete ? .ready : .stale,
                source: .codexBarLocal,
                measuredAt: snapshot.updatedAt,
                lastAttemptAt: now,
                message: isComplete
                    ? nil
                    : "Indexing Codex sessions; totals may increase on the next refresh.",
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
