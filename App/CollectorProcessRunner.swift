import Foundation

struct CollectorProcessResult: Sendable {
    let status: Int32
    let message: String
}

enum CollectorProcessRunner {
    private static let missingCollectorMessage =
        "The bundled usage collector is missing. Reinstall BeaverMeter."

    static func refresh(helper: URL, script: URL?, output: String) -> CollectorProcessResult {
        runCollector(helper: helper, script: script, output: output, mode: nil)
    }

    static func refreshCodexTokens(
        helper: URL,
        script: URL?,
        output: String
    ) -> CollectorProcessResult {
        runCollector(helper: helper, script: script, output: output, mode: "--codex-only")
    }

    static func importBrowserSession(helper: URL) -> CollectorProcessResult {
        guard FileManager.default.isExecutableFile(atPath: helper.path) else {
            return CollectorProcessResult(status: -1, message: missingCollectorMessage)
        }
        return run(
            executable: helper,
            arguments: ["--import-deepseek-browser-session"],
            discardsStandardOutput: true
        )
    }

    static func importToken(helper: URL, token: String) -> CollectorProcessResult {
        guard FileManager.default.isExecutableFile(atPath: helper.path) else {
            return CollectorProcessResult(status: -1, message: missingCollectorMessage)
        }
        return run(
            executable: helper,
            arguments: ["--import-deepseek-token-stdin"],
            standardInput: Data(token.utf8),
            discardsStandardOutput: true
        )
    }

    private static func runCollector(
        helper: URL,
        script: URL?,
        output: String,
        mode: String?
    ) -> CollectorProcessResult {
        let collectorArguments = [mode, "--output", output].compactMap { $0 }
        if let script, FileManager.default.fileExists(atPath: script.path) {
            return run(
                executable: URL(fileURLWithPath: "/bin/zsh"),
                arguments: [script.path] + collectorArguments
            )
        }
        guard FileManager.default.isExecutableFile(atPath: helper.path) else {
            return CollectorProcessResult(status: -1, message: missingCollectorMessage)
        }
        return run(executable: helper, arguments: collectorArguments)
    }

    private static func run(
        executable: URL,
        arguments: [String],
        standardInput: Data? = nil,
        discardsStandardOutput: Bool = false
    ) -> CollectorProcessResult {
        let process = Process()
        let errorPipe = Pipe()
        let inputPipe = standardInput.map { _ in Pipe() }

        process.executableURL = executable
        process.arguments = arguments
        process.standardInput = inputPipe
        process.standardError = errorPipe
        if discardsStandardOutput {
            process.standardOutput = FileHandle.nullDevice
        }

        do {
            try process.run()
            if let standardInput, let inputPipe {
                inputPipe.fileHandleForWriting.write(standardInput)
                try inputPipe.fileHandleForWriting.close()
            }
            process.waitUntilExit()
            let message = String(
                data: errorPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return CollectorProcessResult(status: process.terminationStatus, message: message)
        } catch {
            try? inputPipe?.fileHandleForWriting.close()
            return CollectorProcessResult(status: -1, message: error.localizedDescription)
        }
    }
}
