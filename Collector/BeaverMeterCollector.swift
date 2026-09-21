import Darwin
import Foundation

@main
struct BeaverMeterCollector {
    static func main() async {
        if CommandLine.arguments.contains("--import-deepseek-browser-session") {
            await importDeepSeekBrowserSession()
            return
        }
        if CommandLine.arguments.contains("--import-deepseek-token-stdin") {
            await importDeepSeekTokenFromStandardInput()
            return
        }

        let outputURL = resolvedOutputURL()
        do {
            let lock = try SnapshotWriter.lock(for: outputURL)
            defer { lock.unlock() }
            if CommandLine.arguments.contains("--codex-only") {
                try await refreshCodexOnly(outputURL: outputURL)
            } else {
                try await refreshAll(outputURL: outputURL)
            }
        } catch {
            fail("Failed to refresh usage: \(error.localizedDescription)", status: 1)
        }
    }

    private static func refreshAll(outputURL: URL) async throws {
        let previous = SnapshotWriter.loadPrevious(from: outputURL)
        let now = Date()
        let scanCacheURL = codexScanCacheURL(for: outputURL)

        async let codexTokens = CodexTokenCollector.collect(
            previous: previous.codexTokens,
            now: now,
            scanCacheURL: scanCacheURL
        )
        async let codexQuota = CodexQuotaCollector.collect(previous: previous.codexQuota, now: now)
        async let cursor = CursorUsageCollector.collect(
            previousCosts: previous.cursorCosts,
            previousQuota: previous.cursorQuota,
            now: now
        )
        async let deepseekUsage = DeepSeekUsageCollector.collect(
            previous: previous.deepseekUsage,
            now: now
        )

        let (resolvedCodexTokens, resolvedCodexQuota, resolvedCursor, resolvedDeepSeek) = await (
            codexTokens,
            codexQuota,
            cursor,
            deepseekUsage
        )
        let snapshot = UsageSnapshot(
            schemaVersion: UsageSnapshot.currentSchemaVersion,
            generatedAt: now,
            codexTokens: resolvedCodexTokens,
            cursorCosts: resolvedCursor.costs,
            cursorQuota: resolvedCursor.quota,
            codexQuota: resolvedCodexQuota,
            deepseekUsage: resolvedDeepSeek
        )

        try SnapshotWriter.write(snapshot, to: outputURL)
        print(outputURL.path)
    }

    private static func refreshCodexOnly(outputURL: URL) async throws {
        let previous = SnapshotWriter.loadPrevious(from: outputURL)
        let now = Date()
        let environment = ProcessInfo.processInfo.environment
        let result = try CodexTokenAggregation.collect(
            now: now,
            environment: environment,
            localCacheURL: codexScanCacheURL(for: outputURL)
        )
        let previousWasMeasuredToday = previous.codexTokens.measuredAt.map {
            Calendar.current.isDate($0, inSameDayAs: now)
        } ?? false
        let totals: CodexTokenTotals
        if let collectedTotals = result.totals {
            if previousWasMeasuredToday,
               let previousTotals = previous.codexTokens.value,
               collectedTotals.totalTokens < previousTotals.totalTokens
            {
                totals = previousTotals
            } else {
                totals = collectedTotals
            }
        } else {
            if previousWasMeasuredToday, previous.codexTokens.value != nil {
                totals = previous.codexTokens.value!
            } else {
                totals = CodexTokenTotals(
                    totalTokens: 0,
                    inputTokens: 0,
                    cachedInputTokens: 0,
                    outputTokens: 0,
                    reasoningTokens: 0,
                    sessionCount: 0
                )
            }
        }
        let status: UsageDataStatus = result.remote.complete ? .ready : .stale
        guard result.changed
                || previous.codexTokens.status != status
                || previous.codexTokens.message != result.remote.message
                || previous.codexTokens.value != totals
        else {
            print(outputURL.path)
            return
        }

        let codexTokens = UsageValue(
            status: status,
            source: UsageDataSource.codexBarLocal,
            measuredAt: now,
            lastAttemptAt: now,
            message: result.remote.message,
            value: totals
        )
        let snapshot = UsageSnapshot(
            schemaVersion: UsageSnapshot.currentSchemaVersion,
            generatedAt: now,
            codexTokens: codexTokens,
            cursorCosts: previous.cursorCosts,
            cursorQuota: previous.cursorQuota,
            codexQuota: previous.codexQuota,
            deepseekUsage: previous.deepseekUsage
        )
        try SnapshotWriter.write(snapshot, to: outputURL)
        print(outputURL.path)
    }

    private static func codexScanCacheURL(for outputURL: URL) -> URL {
        outputURL.deletingLastPathComponent()
            .appendingPathComponent("beaver-meter-codex-scan-v2.json")
    }

    private static func importDeepSeekBrowserSession() async {
        do {
            if try await DeepSeekBrowserSessionImporter.importValidatedSession() {
                print("DeepSeek browser session imported.")
                exit(0)
            }
            fail("No signed-in DeepSeek Chromium browser session was found yet.", status: 3)
        } catch {
            fail("Could not import the DeepSeek browser session: \(error.localizedDescription)", status: 4)
        }
    }

    private static func importDeepSeekTokenFromStandardInput() async {
        do {
            let data = FileHandle.standardInput.readDataToEndOfFile()
            guard data.count <= 64 * 1024,
                  let rawValue = String(data: data, encoding: .utf8),
                  let token = DeepSeekCredentialStore.token(fromLocalStorageValue: rawValue)
            else {
                fail("The DeepSeek session token was invalid.", status: 4)
            }
            try await DeepSeekPlatformClient().validate(token: token)
            try DeepSeekCredentialStore.writeToken(token)
            print("DeepSeek browser session imported.")
            exit(0)
        } catch DeepSeekPlatformError.sessionExpired {
            fail("The DeepSeek browser session is not signed in yet.", status: 3)
        } catch {
            fail("Could not import the DeepSeek browser session: \(error.localizedDescription)", status: 4)
        }
    }

    private static func fail(_ message: String, status: Int32) -> Never {
        FileHandle.standardError.write(Data("\(message)\n".utf8))
        exit(status)
    }

    private static func resolvedOutputURL() -> URL {
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--output"),
           arguments.indices.contains(index + 1) {
            return URL(fileURLWithPath: arguments[index + 1])
        }
        if arguments.count > 1, !arguments[1].hasPrefix("-") {
            return URL(fileURLWithPath: arguments[1])
        }
        return UsageSnapshot.snapshotURL
    }
}
