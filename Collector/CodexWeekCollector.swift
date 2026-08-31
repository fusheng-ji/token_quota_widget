import Darwin
import Foundation

@main
struct CodexWeekCollector {
    static func main() async {
        let outputURL = resolvedOutputURL()
        let previous = SnapshotWriter.loadPrevious(from: outputURL)
        let now = Date()

        async let codexTokens = CodexTokenCollector.collect(previous: previous.codexTokens, now: now)
        async let codexQuota = CodexQuotaCollector.collect(previous: previous.codexQuota, now: now)
        async let cursor = CursorUsageCollector.collect(
            previousCosts: previous.cursorCosts,
            previousQuota: previous.cursorQuota,
            now: now
        )

        let (resolvedCodexTokens, resolvedCodexQuota, resolvedCursor) = await (
            codexTokens,
            codexQuota,
            cursor
        )
        let snapshot = UsageSnapshot(
            schemaVersion: UsageSnapshot.currentSchemaVersion,
            generatedAt: now,
            codexTokens: resolvedCodexTokens,
            cursorCosts: resolvedCursor.costs,
            cursorQuota: resolvedCursor.quota,
            codexQuota: resolvedCodexQuota
        )

        do {
            try SnapshotWriter.write(snapshot, to: outputURL)
            print(outputURL.path)
        } catch {
            FileHandle.standardError.write(
                Data("Failed to write snapshot: \(error.localizedDescription)\n".utf8)
            )
            exit(1)
        }
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
