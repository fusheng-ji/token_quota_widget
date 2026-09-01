import Darwin
import Foundation

@main
struct CodexWeekCollector {
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
        let previous = SnapshotWriter.loadPrevious(from: outputURL)
        let now = Date()

        async let codexTokens = CodexTokenCollector.collect(previous: previous.codexTokens, now: now)
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

    private static func importDeepSeekBrowserSession() async {
        do {
            if try await DeepSeekBrowserSessionImporter.importValidatedSession() {
                print("DeepSeek browser session imported.")
                exit(0)
            }
            FileHandle.standardError.write(
                Data("No signed-in DeepSeek Chromium browser session was found yet.\n".utf8)
            )
            exit(3)
        } catch {
            FileHandle.standardError.write(
                Data("Could not import the DeepSeek browser session: \(error.localizedDescription)\n".utf8)
            )
            exit(4)
        }
    }

    private static func importDeepSeekTokenFromStandardInput() async {
        do {
            let data = FileHandle.standardInput.readDataToEndOfFile()
            guard data.count <= 64 * 1024,
                  let rawValue = String(data: data, encoding: .utf8),
                  let token = DeepSeekCredentialStore.token(fromLocalStorageValue: rawValue)
            else {
                FileHandle.standardError.write(Data("The DeepSeek session token was invalid.\n".utf8))
                exit(4)
            }
            try await DeepSeekPlatformClient().validate(token: token)
            try DeepSeekCredentialStore.writeToken(token)
            print("DeepSeek browser session imported.")
            exit(0)
        } catch DeepSeekPlatformError.sessionExpired {
            FileHandle.standardError.write(Data("The DeepSeek browser session is not signed in yet.\n".utf8))
            exit(3)
        } catch {
            FileHandle.standardError.write(
                Data("Could not import the DeepSeek browser session: \(error.localizedDescription)\n".utf8)
            )
            exit(4)
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
