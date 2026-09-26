import Foundation

enum CodexTokenAggregation {
    struct Result {
        let local: CodexUsageRecordScanner.Result
        let remote: CodexRemoteUsageCollector.Result
        let totals: CodexTokenTotals?
        let remoteUniqueTotals: CodexTokenTotals?

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
                totals: nil, usageByResponseHash: [:], sessionHashes: [],
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

        // The source collectors already deduplicate their own records. Sum only
        // remote responses absent locally, without copying both record maps.
        var inputTokens = 0
        var cachedInputTokens = 0
        var outputTokens = 0
        var reasoningTokens = 0
        var uniqueSessions: Set<String> = []
        var hasUniqueRemote = false
        for (responseHash, usage) in remote.usageByResponseHash
        where local.usageByResponseHash[responseHash] == nil {
            hasUniqueRemote = true
            inputTokens = try adding(inputTokens, usage.inputTokens)
            cachedInputTokens = try adding(cachedInputTokens, usage.cachedInputTokens)
            outputTokens = try adding(outputTokens, usage.outputTokens)
            reasoningTokens = try adding(reasoningTokens, usage.reasoningTokens)
            uniqueSessions.insert(usage.sessionHash)
        }
        let remoteUniqueTotals: CodexTokenTotals? = if hasUniqueRemote {
            CodexTokenTotals(
                totalTokens: try adding(inputTokens, outputTokens),
                inputTokens: inputTokens,
                cachedInputTokens: cachedInputTokens,
                outputTokens: outputTokens,
                reasoningTokens: reasoningTokens,
                sessionCount: uniqueSessions.subtracting(local.sessionHashes).count
            )
        } else {
            nil
        }
        let totals: CodexTokenTotals? = if local.totals != nil || remoteUniqueTotals != nil {
            try adding(local.totals ?? .zero, remoteUniqueTotals)
        } else {
            nil
        }
        return Result(
            local: local,
            remote: remote,
            totals: totals,
            remoteUniqueTotals: remoteUniqueTotals
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
