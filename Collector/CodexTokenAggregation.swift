import Foundation

enum CodexTokenAggregation {
    struct Result {
        let local: CodexUsageRecordScanner.Result
        let remote: CodexRemoteUsageCollector.Result
        let totals: CodexTokenTotals?
        let remoteUniqueTotals: CodexTokenTotals?
        let changed: Bool
    }

    static func collect(
        now: Date,
        environment: [String: String],
        localCacheURL: URL?
    ) throws -> Result {
        let local = try CodexUsageRecordScanner.collect(
            codexHomePath: environment["CODEX_HOME"],
            now: now,
            calendar: .current,
            cacheURL: localCacheURL
        )
        let remoteCacheURL = (localCacheURL
            ?? UsageSnapshot.snapshotURL.deletingLastPathComponent()
                .appendingPathComponent("beaver-meter-codex-scan-v2.json"))
            .deletingLastPathComponent()
            .appendingPathComponent("beaver-meter-codex-remote-scan-v1.json")
        let remote = CodexRemoteUsageCollector.collect(
            environment: environment,
            now: now,
            calendar: .current,
            cacheURL: remoteCacheURL
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
            remoteUniqueTotals: try CodexUsageRecordScanner.totals(for: remoteUnique),
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
        let result = lhs.addingReportingOverflow(rhs)
        guard !result.overflow else { throw CocoaError(.coderReadCorrupt) }
        return result.partialValue
    }
}
