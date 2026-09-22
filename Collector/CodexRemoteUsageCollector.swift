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
        let complete: Bool
        let failedFiles: [String]
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
        guard let root = nonempty(environment["CODEX_REMOTE_ROOT"]),
              let python = nonempty(environment["CODEX_REMOTE_PYTHON"]),
              let window = try? CodexDayWindow(now: now, calendar: calendar)
        else {
            return Result(
                configured: true, complete: false, changed: false,
                usageByResponseHash: [:], sessionHashes: [],
                message: "Remote Codex configuration is incomplete; specify a root and Python executable."
            )
        }
        let sourceHash = hash("\(host)\u{0}\(root)\u{0}\(python)")
        let dayStart = window.start

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
                    window: window,
                    cache: cache,
                    environment: environment
                )
            }
            let response = try JSONDecoder().decode(RemoteResponse.self, from: responseData)
            var changed = resetCache
            var cacheChanged = resetCache
            let activeFiles = Set(response.activeFiles)
            var complete = response.complete && response.failedFiles.isEmpty
            // Counts already observed today remain valid if logs are removed,
            // archived or temporarily inaccessible. Day/source changes reset them.
            for (identity, delta) in response.files {
                guard activeFiles.contains(identity), delta.offset >= 0 else {
                    complete = false
                    continue
                }
                var state = delta.reset ? .empty : (cache.files[identity] ?? .empty)
                guard delta.reset || delta.offset >= state.offset else {
                    complete = false
                    continue
                }
                cacheChanged = cacheChanged || state.offset != delta.offset
                cacheChanged = cacheChanged || delta.reset
                for record in delta.records {
                    guard window.contains(Date(timeIntervalSince1970: record.timestamp)),
                          isSHA256(record.responseHash),
                          isSHA256(record.sessionHash),
                          record.inputTokens >= 0,
                          record.cachedInputTokens >= 0,
                          record.outputTokens >= 0,
                          record.reasoningTokens >= 0
                    else { complete = false; continue }
                    if state.records[record.responseHash] == nil {
                        changed = true
                        cacheChanged = true
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
            if cacheChanged { try AtomicFileWriter.writeJSON(cache, to: cacheURL) }
            let records = mergedRecords(in: cache)
            return Result(
                configured: true,
                complete: complete,
                changed: changed,
                usageByResponseHash: records,
                sessionHashes: Set(records.values.map(\.sessionHash)),
                message: complete ? nil : "Some remote Codex records could not be refreshed; today's total includes cached remote usage."
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
        window: CodexDayWindow,
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
            String(window.start.timeIntervalSince1970), String(window.end.timeIntervalSince1970),
            String(window.cutoff.timeIntervalSince1970),
        ].joined(separator: " ")
        let request = try JSONEncoder().encode([
            "files": cache.files.mapValues(\.offset),
        ])
        let ssh = nonempty(environment["BEAVERMETER_SSH"]) ?? "/usr/bin/ssh"
        let result = try SubprocessRunner.run(
            executable: URL(fileURLWithPath: ssh),
            arguments: [
                "-o", "BatchMode=yes", "-o", "ConnectTimeout=8",
                "-o", "ServerAliveInterval=5", "-o", "ServerAliveCountMax=2",
                "--", host, command,
            ],
            standardInput: request,
            timeout: timeout,
            environment: environment
        )
        guard result.status == 0, !result.timedOut, !result.cancelled else {
            throw CocoaError(.fileReadUnknown)
        }
        return result.standardOutput
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

    private static func loadCache(from url: URL) -> Cache? {
        CodexUsageSupport.load(Cache.self, from: url)
    }

    private static func nonempty(_ value: String?) -> String? {
        CodexUsageSupport.nonempty(value)
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
        CodexUsageSupport.hash(value)
    }
}
