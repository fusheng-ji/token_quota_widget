import CryptoKit
import Darwin
import Foundation

enum CodexRemoteUsageCollector {
    struct Result {
        let configured: Bool
        let complete: Bool
        let changed: Bool
        let usageByResponseHash: [String: CodexUsageRecordScanner.AccumulatedUsage]
        let sessionHashes: Set<String>
        let message: String?
    }

    private static let cacheSchemaVersion = 1
    private static let timeout: TimeInterval = 30

    private struct Cache: Codable {
        let schemaVersion: Int
        let dayStart: Date
        let sourceHash: String
        var files: [String: FileState]
    }

    private struct FileState: Codable {
        var offset: Int64
        var records: [String: CodexUsageRecordScanner.AccumulatedUsage]

        static let empty = FileState(offset: 0, records: [:])
    }

    private struct RemoteResponse: Decodable {
        let activeFiles: [String]
        let files: [String: FileDelta]
    }

    private struct FileDelta: Decodable {
        let offset: Int64
        let reset: Bool
        let records: [RemoteRecord]
    }

    private struct RemoteRecord: Decodable {
        let responseHash: String
        let sessionHash: String
        let timestamp: Double
        let inputTokens: Int
        let cachedInputTokens: Int
        let outputTokens: Int
        let reasoningTokens: Int
    }

    static func collect(
        environment: [String: String],
        now: Date,
        calendar: Calendar,
        cacheURL: URL
    ) -> Result {
        guard let host = nonempty(environment["CODEX_REMOTE_SSH_HOST"]) else {
            return Result(
                configured: false,
                complete: true,
                changed: false,
                usageByResponseHash: [:],
                sessionHashes: [],
                message: nil
            )
        }
        let root = nonempty(environment["CODEX_REMOTE_ROOT"])
            ?? "/home/user/.cursor-server/codex-home"
        let python = nonempty(environment["CODEX_REMOTE_PYTHON"])
            ?? "/home/user/miniconda3/bin/python3"
        let sourceHash = hash("\(host)\u{0}\(root)\u{0}\(python)")
        let dayStart = calendar.startOfDay(for: now)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
            return failed(cache: nil, message: "Remote Codex day boundary could not be calculated.")
        }

        let loaded = loadCache(from: cacheURL)
        let cacheIsCurrent = loaded?.schemaVersion == cacheSchemaVersion
            && loaded?.dayStart == dayStart
            && loaded?.sourceHash == sourceHash
        var cache = if cacheIsCurrent, let loaded {
            loaded
        } else {
            Cache(
                schemaVersion: cacheSchemaVersion,
                dayStart: dayStart,
                sourceHash: sourceHash,
                files: [:]
            )
        }
        let resetCache = !cacheIsCurrent

        do {
            let responseData: Data
            if let fixture = nonempty(environment["CODEX_REMOTE_RESPONSE_FIXTURE"]) {
                responseData = try Data(contentsOf: URL(fileURLWithPath: fixture))
            } else {
                responseData = try fetch(
                    host: host,
                    root: root,
                    python: python,
                    dayStart: dayStart,
                    dayEnd: dayEnd,
                    cache: cache,
                    environment: environment
                )
            }
            let response = try JSONDecoder().decode(RemoteResponse.self, from: responseData)
            var changed = resetCache
            let activeFiles = Set(response.activeFiles)
            let removedFiles = Set(cache.files.keys).subtracting(activeFiles)
            if !removedFiles.isEmpty {
                changed = true
                for identity in removedFiles { cache.files.removeValue(forKey: identity) }
            }
            for (identity, delta) in response.files {
                guard activeFiles.contains(identity), delta.offset >= 0 else { continue }
                var state = delta.reset ? .empty : (cache.files[identity] ?? .empty)
                if delta.reset || state.offset != delta.offset || !delta.records.isEmpty {
                    changed = true
                }
                if delta.reset { state.records.removeAll() }
                for record in delta.records {
                    guard record.timestamp >= dayStart.timeIntervalSince1970,
                          record.timestamp < dayEnd.timeIntervalSince1970,
                          isSHA256(record.responseHash),
                          isSHA256(record.sessionHash),
                          record.inputTokens >= 0,
                          record.cachedInputTokens >= 0,
                          record.outputTokens >= 0,
                          record.reasoningTokens >= 0
                    else { continue }
                    if state.records[record.responseHash] == nil {
                        state.records[record.responseHash] = .init(
                            inputTokens: record.inputTokens,
                            cachedInputTokens: record.cachedInputTokens,
                            outputTokens: record.outputTokens,
                            reasoningTokens: record.reasoningTokens,
                            sessionHash: record.sessionHash
                        )
                    }
                }
                state.offset = delta.offset
                cache.files[identity] = state
            }
            try writeCache(cache, to: cacheURL)
            let records = mergedRecords(in: cache)
            return Result(
                configured: true,
                complete: true,
                changed: changed,
                usageByResponseHash: records,
                sessionHashes: Set(records.values.map(\.sessionHash)),
                message: nil
            )
        } catch {
            let records = mergedRecords(in: cache)
            return Result(
                configured: true,
                complete: false,
                changed: false,
                usageByResponseHash: records,
                sessionHashes: Set(records.values.map(\.sessionHash)),
                message: records.isEmpty
                    ? "Remote Codex usage is unavailable; today's total includes local usage only."
                    : "Remote Codex refresh failed; today's total includes the last remote reading."
            )
        }
    }

    private static func fetch(
        host: String,
        root: String,
        python: String,
        dayStart: Date,
        dayEnd: Date,
        cache: Cache,
        environment: [String: String]
    ) throws -> Data {
        guard isSafeHost(host), root.hasPrefix("/"), python.hasPrefix("/"),
              !root.contains("\n"), !python.contains("\n")
        else { throw CocoaError(.fileReadInvalidFileName) }
        guard let scriptURL = resolvedScriptURL(environment: environment),
              let scriptData = try? Data(contentsOf: scriptURL),
              !scriptData.isEmpty
        else { throw CocoaError(.fileNoSuchFile) }

        let code = "import base64;exec(base64.b64decode(\"\(scriptData.base64EncodedString())\"))"
        let command = [
            shellQuote(python), "-c", shellQuote(code), shellQuote(root),
            String(dayStart.timeIntervalSince1970), String(dayEnd.timeIntervalSince1970),
        ].joined(separator: " ")
        let request = try JSONEncoder().encode([
            "files": cache.files.mapValues(\.offset),
        ])
        let ssh = nonempty(environment["BEAVERMETER_SSH"]) ?? "/usr/bin/ssh"
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("beavermeter-remote-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let outputURL = temporaryDirectory.appendingPathComponent("output.json")
        let errorURL = temporaryDirectory.appendingPathComponent("error.txt")
        FileManager.default.createFile(atPath: outputURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
        FileManager.default.createFile(atPath: errorURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
        let outputHandle = try FileHandle(forWritingTo: outputURL)
        let errorHandle = try FileHandle(forWritingTo: errorURL)
        defer {
            try? outputHandle.close()
            try? errorHandle.close()
        }

        let process = Process()
        let input = Pipe()
        process.executableURL = URL(fileURLWithPath: ssh)
        process.arguments = [
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=8",
            "-o", "ServerAliveInterval=5",
            "-o", "ServerAliveCountMax=2",
            "--", host, command,
        ]
        process.standardInput = input
        process.standardOutput = outputHandle
        process.standardError = errorHandle
        try process.run()
        input.fileHandleForWriting.write(request)
        try input.fileHandleForWriting.close()

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning, Date() < deadline { usleep(50_000) }
        if process.isRunning {
            process.terminate()
            let terminationDeadline = Date().addingTimeInterval(1)
            while process.isRunning, Date() < terminationDeadline { usleep(50_000) }
            if process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
            throw CocoaError(.fileReadUnknown)
        }
        guard process.terminationStatus == 0 else { throw CocoaError(.fileReadUnknown) }
        try outputHandle.synchronize()
        return try Data(contentsOf: outputURL)
    }

    private static func resolvedScriptURL(environment: [String: String]) -> URL? {
        if let configured = nonempty(environment["BEAVERMETER_REMOTE_SCRIPT"]) {
            return URL(fileURLWithPath: configured)
        }
        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        return executable.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/remote_codex_usage.py")
    }

    private static func mergedRecords(in cache: Cache) -> [String: CodexUsageRecordScanner.AccumulatedUsage] {
        var records: [String: CodexUsageRecordScanner.AccumulatedUsage] = [:]
        for state in cache.files.values {
            for (hash, usage) in state.records where records[hash] == nil { records[hash] = usage }
        }
        return records
    }

    private static func failed(cache: Cache?, message: String) -> Result {
        let records = cache.map(mergedRecords) ?? [:]
        return Result(
            configured: true,
            complete: false,
            changed: false,
            usageByResponseHash: records,
            sessionHashes: Set(records.values.map(\.sessionHash)),
            message: message
        )
    }

    private static func loadCache(from url: URL) -> Cache? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Cache.self, from: data)
    }

    private static func writeCache(_ cache: Cache, to url: URL) throws {
        let manager = FileManager.default
        let directory = url.deletingLastPathComponent()
        try manager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(cache)
        let temporary = directory.appendingPathComponent(".codex-remote-\(UUID().uuidString).tmp")
        try data.write(to: temporary, options: .withoutOverwriting)
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
        guard Darwin.rename(temporary.path, url.path) == 0 else {
            let code = errno
            try? manager.removeItem(at: temporary)
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }

    private static func isSafeHost(_ host: String) -> Bool {
        !host.isEmpty && host.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0) || ".-_@".unicodeScalars.contains($0)
        }
    }

    private static func isSHA256(_ value: String) -> Bool {
        value.count == 64 && value.allSatisfy { $0.isHexDigit }
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

    private static func hash(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
