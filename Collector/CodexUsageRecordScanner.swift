import Darwin
import Foundation

/// Reads the per-response usage records emitted by recent Codex Desktop builds.
/// The private scan cache stores only hashed identifiers, counters and byte offsets, so frequent live
/// refreshes consume appended JSONL tails instead of rereading whole rollouts.
enum CodexUsageRecordScanner {
    typealias AccumulatedUsage = CodexResponseUsage

    struct Result {
        let totals: CodexTokenTotals?
        let usageByResponseHash: [String: AccumulatedUsage]
        let sessionHashes: Set<String>
        let complete: Bool
        let message: String?
    }

    private static let cacheSchemaVersion = 2
    private static let recordMarker = Data(#""token_usage_record""#.utf8)

    private struct Record: Decodable {
        let type: String
        let timestamp: String
        let payload: Payload
    }

    private struct Payload: Decodable {
        let responseID: String?
        let sessionID: String?
        let usage: Usage

        enum CodingKeys: String, CodingKey {
            case responseID = "response_id"
            case sessionID = "session_id"
            case usage
        }
    }

    private struct Usage: Decodable {
        let inputTokens: Int
        let cachedInputTokens: Int?
        let outputTokens: Int
        let reasoningOutputTokens: Int?

        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case cachedInputTokens = "cached_input_tokens"
            case outputTokens = "output_tokens"
            case reasoningOutputTokens = "reasoning_output_tokens"
        }
    }

    private struct ScanCache: Codable {
        let schemaVersion: Int
        let dayStart: Date
        let codexHomeHash: String
        var files: [String: FileState]
    }

    private struct FileState: Codable {
        var offset: Int
        var records: [String: AccumulatedUsage]

        static let empty = FileState(
            offset: 0,
            records: [:]
        )
    }

    private struct Candidate {
        let url: URL
        let identity: String
        let size: Int
    }

    static func collect(
        codexHomePath: String?,
        now: Date,
        calendar: Calendar = .current,
        cacheURL: URL? = nil
    ) throws -> Result {
        let codexHome = CodexUsageSupport.homeURL(codexHomePath)
        let codexHomeHash = hash(codexHome.standardizedFileURL.path)
        let window = try CodexDayWindow(now: now, calendar: calendar)
        let dayStart = window.start

        let enumeration = recentlyModifiedRollouts(
            codexHome: codexHome,
            dayStart: dayStart
        )
        let candidates = enumeration.candidates
        var complete = enumeration.complete
        let loadedCache = cacheURL.flatMap(loadCache)
        let cacheIsCurrent = loadedCache?.schemaVersion == cacheSchemaVersion
            && loadedCache?.dayStart == dayStart
            && loadedCache?.codexHomeHash == codexHomeHash
        var cache = if cacheIsCurrent, let loadedCache {
            loadedCache
        } else {
            ScanCache(
                schemaVersion: cacheSchemaVersion,
                dayStart: dayStart,
                codexHomeHash: codexHomeHash,
                files: [:]
            )
        }
        let resetCache = !cacheIsCurrent
        var cacheChanged = resetCache

        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let standardFormatter = ISO8601DateFormatter()
        standardFormatter.formatOptions = [.withInternetDateTime]

        for candidate in candidates {
            var state = cache.files[candidate.identity] ?? .empty
            let previousState = cache.files[candidate.identity]
            let truncated = candidate.size < state.offset
            if truncated {
                // The old byte range no longer exists. Rebuild this file's
                // records from its replacement; the public same-source daily
                // reading guards against a temporary lower total.
                state = .empty
            }
            guard candidate.size > state.offset else {
                if truncated {
                    cache.files[candidate.identity] = state
                    cacheChanged = true
                }
                continue
            }

            let baseOffset = state.offset
            var retryOffset: Int?
            var candidateChanged = false
            let consumedCount: Int
            do {
                let handle = try FileHandle(forReadingFrom: candidate.url)
                defer { try? handle.close() }
                try handle.seek(toOffset: UInt64(state.offset))
                consumedCount = try forEachUsageRecord(in: handle) { record, lineOffset in
                    guard record.type == "token_usage_record",
                          let timestamp = fractionalFormatter.date(from: record.timestamp)
                            ?? standardFormatter.date(from: record.timestamp),
                          timestamp >= dayStart,
                          timestamp < window.end
                    else { return }
                    guard timestamp <= window.cutoff else {
                        // Retry records beyond this refresh's cutoff on the next scan.
                        retryOffset = min(retryOffset ?? lineOffset, lineOffset)
                        return
                    }

                    let usage = record.payload.usage
                    guard usage.inputTokens >= 0,
                          (usage.cachedInputTokens ?? 0) >= 0,
                          usage.outputTokens >= 0,
                          (usage.reasoningOutputTokens ?? 0) >= 0
                    else { return }

                    let responseIdentity = CodexUsageSupport.nonempty(record.payload.responseID)
                        ?? "\(candidate.identity):\(baseOffset + lineOffset):\(record.timestamp)"
                    let responseHash = hash(responseIdentity)
                    guard state.records[responseHash] == nil else { return }

                    state.records[responseHash] = AccumulatedUsage(
                        inputTokens: usage.inputTokens,
                        cachedInputTokens: usage.cachedInputTokens ?? 0,
                        outputTokens: usage.outputTokens,
                        reasoningTokens: usage.reasoningOutputTokens ?? 0,
                        sessionHash: hash(CodexUsageSupport.nonempty(record.payload.sessionID) ?? candidate.identity)
                    )
                    candidateChanged = true
                }
            } catch {
                complete = false
                continue
            }
            state.offset = try adding(baseOffset, retryOffset ?? consumedCount)
            cacheChanged = cacheChanged || truncated || candidateChanged || state.offset != previousState?.offset
            cache.files[candidate.identity] = state
        }

        if let cacheURL, cacheChanged {
            do {
                try AtomicFileWriter.writeJSON(cache, to: cacheURL)
            } catch {
                complete = false
            }
        }

        var usageByResponseHash: [String: AccumulatedUsage] = [:]
        for state in cache.files.values {
            for (responseHash, usage) in state.records where usageByResponseHash[responseHash] == nil {
                usageByResponseHash[responseHash] = usage
            }
        }
        let sessionHashes = Set(usageByResponseHash.values.lazy.map(\.sessionHash))
        let totals = try totals(for: usageByResponseHash, sessionHashes: sessionHashes)
        return Result(
            totals: totals,
            usageByResponseHash: usageByResponseHash,
            sessionHashes: sessionHashes,
            complete: complete,
            message: complete ? nil : "Some local Codex records could not be refreshed; today's total may be incomplete."
        )
    }

    static func totals(
        for records: [String: AccumulatedUsage],
        sessionHashes: Set<String>
    ) throws -> CodexTokenTotals? {
        guard !records.isEmpty else { return nil }
        var inputTokens = 0
        var cachedInputTokens = 0
        var outputTokens = 0
        var reasoningTokens = 0
        for usage in records.values {
            inputTokens = try adding(inputTokens, usage.inputTokens)
            cachedInputTokens = try adding(cachedInputTokens, usage.cachedInputTokens)
            outputTokens = try adding(outputTokens, usage.outputTokens)
            reasoningTokens = try adding(reasoningTokens, usage.reasoningTokens)
        }
        return CodexTokenTotals(
            totalTokens: try adding(inputTokens, outputTokens),
            inputTokens: inputTokens,
            cachedInputTokens: cachedInputTokens,
            outputTokens: outputTokens,
            reasoningTokens: reasoningTokens,
            sessionCount: sessionHashes.count
        )
    }

    private static func recentlyModifiedRollouts(
        codexHome: URL,
        dayStart: Date
    ) -> (candidates: [Candidate], complete: Bool) {
        var candidates: [Candidate] = []
        var seenIdentities: Set<String> = []
        var complete = true

        func appendJSONLFiles(in directory: URL) {
            let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]
            guard FileManager.default.fileExists(atPath: directory.path) else { return }
            guard let enumerator = FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { _, _ in complete = false; return true }
            ) else { complete = false; return }

            for case let fileURL as URL in enumerator where fileURL.pathExtension.lowercased() == "jsonl" {
                let values: URLResourceValues
                do {
                    values = try fileURL.resourceValues(forKeys: Set(keys))
                } catch {
                    complete = false
                    continue
                }
                guard values.isRegularFile == true,
                      let modifiedAt = values.contentModificationDate,
                      modifiedAt >= dayStart,
                      let fileSize = values.fileSize,
                      fileSize >= 0,
                      let identity = fileIdentity(fileURL),
                      seenIdentities.insert(identity).inserted
                else { continue }
                candidates.append(Candidate(url: fileURL, identity: identity, size: fileSize))
            }
        }

        if !FileManager.default.fileExists(atPath: codexHome.path) { complete = false }
        appendJSONLFiles(in: codexHome.appendingPathComponent("sessions", isDirectory: true))
        appendJSONLFiles(in: codexHome.appendingPathComponent("archived_sessions", isDirectory: true))
        return (candidates.sorted { $0.identity < $1.identity }, complete)
    }

    private static func fileIdentity(_ url: URL) -> String? {
        var information = stat()
        guard lstat(url.path, &information) == 0 else { return nil }
        return "\(information.st_dev):\(information.st_ino)"
    }

    private static func forEachUsageRecord(
        in handle: FileHandle,
        body: (Record, Int) throws -> Void
    ) throws -> Int {
        let decoder = JSONDecoder()
        var pending = Data()
        var completedBytes = 0
        while let chunk = try handle.read(upToCount: 64 * 1024), !chunk.isEmpty {
            var buffer = pending
            buffer.append(chunk)
            var lineStart = buffer.startIndex
            while let newline = buffer[lineStart...].firstIndex(of: 0x0A) {
                let line = buffer[lineStart..<newline]
                if line.range(of: recordMarker) != nil,
                   let record = try? decoder.decode(Record.self, from: line) {
                    try body(record, completedBytes)
                }
                completedBytes = try adding(completedBytes, buffer.distance(
                    from: lineStart, to: buffer.index(after: newline)
                ))
                lineStart = buffer.index(after: newline)
            }
            pending = Data(buffer[lineStart...])
        }
        return completedBytes
    }

    private static func loadCache(from url: URL) -> ScanCache? {
        CodexUsageSupport.load(ScanCache.self, from: url)
    }

    private static func hash(_ value: String) -> String {
        CodexUsageSupport.hash(value)
    }

    private static func adding(_ lhs: Int, _ rhs: Int) throws -> Int {
        try CodexUsageSupport.adding(lhs, rhs)
    }
}
