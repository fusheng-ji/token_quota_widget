import CodexBarCore
import Foundation

/// Both refresh modes use this service, including legacy local compatibility.
enum CodexTokenCollector {
    private struct LegacyCache: Codable {
        let schemaVersion: Int
        let dayStart: Date
        let homeHash: String
        let totals: CodexTokenTotals
    }

    private struct Measurement: Codable, Equatable {
        let dayStart: Date
        let sourceHash: String
        let measuredAt: Date
    }

    static func collect(
        previous: UsageValue<CodexTokenTotals>,
        now: Date,
        scanCacheURL: URL? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        calendar: Calendar = .current
    ) async -> UsageValue<CodexTokenTotals> {
        do {
            // Full-provider fixtures intentionally bypass local and remote IO.
            if let fixture = environment["CODEX_TOKEN_FIXTURE"] {
                return value(try readTotalsFixture(fixture), now: now, complete: true, messages: [])
            }
            let locations = CodexCacheLocations(snapshotURL: scanCacheURL ?? UsageSnapshot.snapshotURL)
            let aggregation = try CodexTokenAggregation.collect(
                now: now,
                environment: environment,
                localCacheURL: scanCacheURL ?? locations.local,
                calendar: calendar
            )
            let window = try CodexDayWindow(now: now, calendar: calendar)
            let homeHash = CodexUsageSupport.hash(CodexUsageSupport.homeURL(environment["CODEX_HOME"]).path)
            let loaded = CodexUsageSupport.load(LegacyCache.self, from: locations.legacy)
            let cached = loaded.flatMap { cache in
                cache.schemaVersion == 1 && cache.dayStart == window.start && cache.homeHash == homeHash
                    ? cache.totals : nil
            }
            var legacyTotals = cached
            var legacyComplete = true
            var messages = [aggregation.local.message, aggregation.remote.message].compactMap { $0 }
            do {
                let reading = try await legacyReading(now: now, calendar: calendar, environment: environment)
                // Only a matching source's same-day cache can protect against a
                // partial legacy scan. Never reuse the previous combined snapshot.
                let selectedLegacy = maxTotals(reading.totals, cached)
                legacyTotals = selectedLegacy
                legacyComplete = reading.complete
                if selectedLegacy != cached {
                    try AtomicFileWriter.writeJSON(
                        LegacyCache(schemaVersion: 1, dayStart: window.start, homeHash: homeHash, totals: selectedLegacy),
                        to: locations.legacy
                    )
                }
                if !reading.complete {
                    messages.append("Indexing legacy Codex sessions; today's total may increase on the next refresh.")
                }
            } catch {
                legacyComplete = false
                messages.append("Legacy local Codex usage could not be refreshed; today's cached reading is retained when available.")
            }
            var totals = try aggregation.resolvingLocalTotals(legacyTotals)
            var complete = aggregation.local.complete && aggregation.remote.complete && legacyComplete
            let sourceHash = CodexUsageSupport.hash([
                homeHash,
                environment["CODEX_REMOTE_SSH_HOST"] ?? "",
                environment["CODEX_REMOTE_ROOT"] ?? "",
                environment["CODEX_REMOTE_PYTHON"] ?? "",
            ].joined(separator: "\u{0}"))
            let measurement = CodexUsageSupport.load(Measurement.self, from: locations.measurement)
            var measuredAt = complete ? now : (
                measurement?.sourceHash == sourceHash && measurement?.dayStart == window.start
                    ? measurement?.measuredAt ?? window.start : window.start
            )
            if complete,
               measurement?.sourceHash == sourceHash,
               measurement?.dayStart == window.start,
               previous.status == .ready,
               previous.value == totals {
                measuredAt = previous.measuredAt ?? measurement?.measuredAt ?? now
            }
            if measurement?.sourceHash == sourceHash,
               measurement?.dayStart == window.start,
               let previousTotals = previous.value,
               previous.measuredAt.map({ calendar.isDate($0, inSameDayAs: now) }) == true,
               previousTotals.totalTokens > totals.totalTokens {
                totals = previousTotals
                complete = false
                measuredAt = previous.measuredAt ?? window.start
                messages.append("Today's Codex total retains the last same-source reading while the scan recovers.")
            }
            let updatedMeasurement = Measurement(
                dayStart: window.start, sourceHash: sourceHash, measuredAt: measuredAt
            )
            if measurement != updatedMeasurement {
                // Source identity is needed even when CodexBar is still
                // indexing and the first reading is incomplete.
                try? AtomicFileWriter.writeJSON(updatedMeasurement, to: locations.measurement)
            }
            return value(
                totals,
                now: now,
                complete: complete,
                messages: messages,
                measuredAt: measuredAt
            )
        } catch {
            // The previous snapshot has no source identity. Carrying it forward
            // could mix days or accounts after configuration changes.
            return value(.zero, now: now, complete: false, messages: ["Codex usage could not be refreshed."])
        }
    }

    private static func legacyReading(
        now: Date,
        calendar: Calendar,
        environment: [String: String]
    ) async throws -> (totals: CodexTokenTotals, complete: Bool) {
        if let fixture = environment["CODEX_LEGACY_TOKEN_FIXTURE"] {
            return (try readTotalsFixture(fixture), true)
        }
        let snapshot = try await CostUsageFetcher(
            cacheRoot: environment["CODEX_TOKEN_CACHE_ROOT"].map { URL(fileURLWithPath: $0) },
            calendar: calendar
        ).loadTokenSnapshot(
            provider: .codex,
            now: now,
            forceRefresh: true,
            codexHomePath: environment["CODEX_HOME"],
            historyDays: 1,
            allowPricingRefresh: false,
            refreshPricingInBackground: false,
            includePiSessions: false
        )
        let entry = snapshot.currentDayEntry(calendar: calendar)
        let input = max(0, entry?.inputTokens ?? 0)
        let output = max(0, entry?.outputTokens ?? 0)
        let total = try CodexUsageSupport.adding(input, output)
        let window = try CodexDayWindow(now: now, calendar: calendar)
        let sessions = snapshot.sessions.filter { window.contains($0.lastActivity) }.count
        return (
            CodexTokenTotals(
                totalTokens: total,
                inputTokens: input,
                cachedInputTokens: max(0, entry?.cacheReadTokens ?? 0),
                outputTokens: output,
                reasoningTokens: max(0, entry?.reasoningTokens ?? 0),
                sessionCount: sessions == 0 && total > 0 ? 1 : sessions
            ),
            snapshot.historyCoverageIsEstablished
        )
    }

    private static func readTotalsFixture(_ path: String) throws -> CodexTokenTotals {
        try JSONDecoder().decode(CodexTokenTotals.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
    }

    private static func maxTotals(_ current: CodexTokenTotals, _ cached: CodexTokenTotals?) -> CodexTokenTotals {
        if let cached, cached.totalTokens > current.totalTokens { return cached }
        return current
    }

    private static func value(
        _ totals: CodexTokenTotals,
        now: Date,
        complete: Bool,
        messages: [String],
        measuredAt: Date? = nil
    ) -> UsageValue<CodexTokenTotals> {
        UsageValue(
            status: complete ? .ready : .stale,
            source: .codexBarLocal,
            measuredAt: measuredAt ?? now,
            lastAttemptAt: now,
            message: messages.isEmpty ? nil : messages.joined(separator: " "),
            value: totals
        )
    }
}
