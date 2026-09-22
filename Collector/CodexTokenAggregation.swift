import Foundation

enum CodexTokenAggregation {
    struct Result {
        let local: CodexUsageRecordScanner.Result
        let remote: CodexRemoteUsageCollector.Result
        let totals: CodexTokenTotals?
        let remoteUniqueTotals: CodexTokenTotals?
        let changed: Bool

        func resolvingLocalTotals(_ legacyTotals: CodexTokenTotals?) throws -> CodexTokenTotals {
            let localTotals = local.totals ?? .zero
            let selectedLocal: CodexTokenTotals
            if let legacyTotals, legacyTotals.totalTokens > localTotals.totalTokens {
                selectedLocal = legacyTotals
            } else {
                selectedLocal = localTotals
            }
            return try CodexTokenAggregation.adding(selectedLocal, remoteUniqueTotals)
        }
    }

    static func collect(
        now: Date,
        environment: [String: String],
        localCacheURL: URL?,
        calendar: Calendar = .current
    ) throws -> Result {
        let local: CodexUsageRecordScanner.Result
        do {
            local = try CodexUsageRecordScanner.collect(
                codexHomePath: environment["CODEX_HOME"],
                now: now,
                calendar: calendar,
                cacheURL: localCacheURL
            )
        } catch {
            local = .init(
                totals: nil, changed: false, usageByResponseHash: [:], sessionHashes: [],
                complete: false, message: "Local Codex records could not be refreshed."
            )
        }
        let locations = CodexCacheLocations(snapshotURL: localCacheURL ?? UsageSnapshot.snapshotURL)
        let remote = CodexRemoteUsageCollector.collect(
            environment: environment,
            now: now,
            calendar: calendar,
            cacheURL: locations.remote
        )

        var merged = local.usageByResponseHash
        var remoteUnique: [String: CodexUsageRecordScanner.AccumulatedUsage] = [:]
        for (responseHash, usage) in remote.usageByResponseHash where merged[responseHash] == nil {
            merged[responseHash] = usage
            remoteUnique[responseHash] = usage
        }
        let sessions = local.sessionHashes.union(remote.sessionHashes)
        return Result(
            local: local,
            remote: remote,
            totals: try CodexUsageRecordScanner.totals(for: merged, sessionHashes: sessions),
            remoteUniqueTotals: try CodexUsageRecordScanner.totals(
                for: remoteUnique,
                sessionHashes: Set(remoteUnique.values.map(\.sessionHash)).subtracting(local.sessionHashes)
            ),
            changed: local.changed || remote.changed
        )
    }

    static func adding(_ lhs: CodexTokenTotals, _ rhs: CodexTokenTotals?) throws -> CodexTokenTotals {
        guard let rhs else { return lhs }
        return CodexTokenTotals(
            totalTokens: try adding(lhs.totalTokens, rhs.totalTokens),
            inputTokens: try adding(lhs.inputTokens, rhs.inputTokens),
            cachedInputTokens: try adding(lhs.cachedInputTokens, rhs.cachedInputTokens),
            outputTokens: try adding(lhs.outputTokens, rhs.outputTokens),
            reasoningTokens: try adding(lhs.reasoningTokens, rhs.reasoningTokens),
            sessionCount: try adding(lhs.sessionCount, rhs.sessionCount)
        )
    }

    private static func adding(_ lhs: Int, _ rhs: Int) throws -> Int {
        try CodexUsageSupport.adding(lhs, rhs)
    }
}
