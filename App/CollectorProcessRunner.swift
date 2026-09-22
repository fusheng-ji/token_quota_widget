import Foundation

struct CollectorProcessResult: Sendable {
    let status: Int32
    let message: String
}

enum CollectorProcessRunner {
    private static let missingCollectorMessage =
        "The bundled usage collector is missing. Reinstall BeaverMeter."

    static func refresh(helper: URL, script: URL?, output: String, cancellation: SubprocessCancellation? = nil) -> CollectorProcessResult {
        runCollector(helper: helper, script: script, output: output, mode: nil, cancellation: cancellation)
    }

    static func refreshCodexTokens(
        helper: URL,
        script: URL?,
        output: String,
        cancellation: SubprocessCancellation? = nil
    ) -> CollectorProcessResult {
        runCollector(helper: helper, script: script, output: output, mode: "--codex-only", cancellation: cancellation)
    }

    static func importBrowserSession(helper: URL, cancellation: SubprocessCancellation? = nil) -> CollectorProcessResult {
        guard FileManager.default.isExecutableFile(atPath: helper.path) else {
            return CollectorProcessResult(status: -1, message: missingCollectorMessage)
        }
        return run(
            executable: helper,
            arguments: ["--import-deepseek-browser-session"],
            timeout: 60,
            cancellation: cancellation
        )
    }

    static func importToken(helper: URL, token: String, cancellation: SubprocessCancellation? = nil) -> CollectorProcessResult {
        guard FileManager.default.isExecutableFile(atPath: helper.path) else {
            return CollectorProcessResult(status: -1, message: missingCollectorMessage)
        }
        return run(
            executable: helper,
            arguments: ["--import-deepseek-token-stdin"],
            standardInput: Data(token.utf8),
            timeout: 60,
            cancellation: cancellation
        )
    }

    private static func runCollector(
        helper: URL,
        script: URL?,
        output: String,
        mode: String?,
        cancellation: SubprocessCancellation?
    ) -> CollectorProcessResult {
        let collectorArguments = [mode, "--output", output].compactMap { $0 }
        if let script, FileManager.default.fileExists(atPath: script.path) {
            return run(
                executable: URL(fileURLWithPath: "/bin/zsh"),
                arguments: [script.path] + collectorArguments,
                timeout: 180,
                cancellation: cancellation
            )
        }
        guard FileManager.default.isExecutableFile(atPath: helper.path) else {
            return CollectorProcessResult(status: -1, message: missingCollectorMessage)
        }
        return run(executable: helper, arguments: collectorArguments, timeout: 180, cancellation: cancellation)
    }

    private static func run(
        executable: URL,
        arguments: [String],
        standardInput: Data? = nil,
        timeout: TimeInterval,
        cancellation: SubprocessCancellation?
    ) -> CollectorProcessResult {
        do {
            let result = try SubprocessRunner.run(
                executable: executable,
                arguments: arguments,
                standardInput: standardInput,
                timeout: timeout,
                captureStandardOutput: false,
                cancellation: cancellation
            )
            if result.cancelled {
                return CollectorProcessResult(status: -1, message: "Refresh cancelled.")
            }
            if result.timedOut {
                return CollectorProcessResult(status: -1, message: "Refresh timed out; cached data is still available. Try again.")
            }
            let message = String(
                data: result.standardError,
                encoding: .utf8
            )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return CollectorProcessResult(status: result.status, message: message)
        } catch {
            return CollectorProcessResult(status: -1, message: error.localizedDescription)
        }
    }
}
