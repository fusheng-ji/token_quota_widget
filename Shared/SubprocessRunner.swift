import Darwin
import Foundation

final class SubprocessCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }
}

/// File-backed stdio keeps large SSH requests and error output from filling a pipe.
enum SubprocessRunner {
    struct Result: Sendable {
        let status: Int32
        let standardOutput: Data
        let standardError: Data
        let timedOut: Bool
        let cancelled: Bool
    }

    static func run(
        executable: URL,
        arguments: [String],
        standardInput: Data? = nil,
        timeout: TimeInterval = 30,
        environment: [String: String]? = nil,
        captureStandardOutput: Bool = true,
        cancellation: SubprocessCancellation? = nil
    ) throws -> Result {
        let manager = FileManager.default
        let directory = manager.temporaryDirectory
            .appendingPathComponent("beavermeter-process-\(UUID().uuidString)", isDirectory: true)
        try manager.createDirectory(
            at: directory, withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        defer { try? manager.removeItem(at: directory) }
        let inputURL = directory.appendingPathComponent("input")
        let outputURL = directory.appendingPathComponent("output")
        let errorURL = directory.appendingPathComponent("error")
        try AtomicFileWriter.write(standardInput ?? Data(), to: inputURL)
        try AtomicFileWriter.write(Data(), to: outputURL)
        try AtomicFileWriter.write(Data(), to: errorURL)
        let input = try FileHandle(forReadingFrom: inputURL)
        defer { try? input.close() }
        let output = try FileHandle(forWritingTo: outputURL)
        defer { try? output.close() }
        let error = try FileHandle(forWritingTo: errorURL)
        defer { try? error.close() }

        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        process.standardInput = input
        process.standardOutput = captureStandardOutput ? output : FileHandle.nullDevice
        process.standardError = error
        if cancellation?.isCancelled == true {
            return Result(status: -1, standardOutput: Data(), standardError: Data(), timedOut: false, cancelled: true)
        }
        try process.run()
        let deadline = ProcessInfo.processInfo.systemUptime + max(0, timeout)
        while process.isRunning,
              ProcessInfo.processInfo.systemUptime < deadline,
              cancellation?.isCancelled != true {
            Thread.sleep(forTimeInterval: 0.025)
        }
        let cancelled = cancellation?.isCancelled == true
        let timedOut = process.isRunning && !cancelled
        if process.isRunning {
            process.terminate()
            let stopDeadline = ProcessInfo.processInfo.systemUptime + 1
            while process.isRunning, ProcessInfo.processInfo.systemUptime < stopDeadline {
                Thread.sleep(forTimeInterval: 0.025)
            }
            if process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) }
        }
        process.waitUntilExit()
        try output.synchronize()
        try error.synchronize()
        return Result(
            status: process.terminationStatus,
            standardOutput: captureStandardOutput ? try Data(contentsOf: outputURL) : Data(),
            standardError: try Data(contentsOf: errorURL),
            timedOut: timedOut,
            cancelled: cancelled
        )
    }
}
