import CryptoKit
import Darwin
import Foundation

/// Reads the per-response usage records emitted by recent Codex Desktop builds.
/// The private scan cache stores only hashes and byte offsets, so frequent live
/// refreshes consume appended JSONL tails instead of rereading whole rollouts.
enum CodexUsageRecordScanner {
    struct AccumulatedUsage: Codable, Hashable, Sendable {
        let inputTokens: Int
        let cachedInputTokens: Int
        let outputTokens: Int
        let reasoningTokens: Int
        let sessionHash: String
    }

    struct Result {
        let totals: CodexTokenTotals?
        let changed: Bool
        let usageByResponseHash: [String: AccumulatedUsage]
        let sessionHashes: Set<String>
    }

    private static let activeSessionLookbackDays = 30
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
        let codexHome = resolvedCodexHome(codexHomePath)
        let codexHomeHash = hash(codexHome.standardizedFileURL.path)
        let dayStart = calendar.startOfDay(for: now)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
            throw CocoaError(.coderReadCorrupt)
        }

        let candidates = recentlyModifiedRollouts(
            codexHome: codexHome,
            dayStart: dayStart,
            calendar: calendar
        )
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
        var resetCache = !cacheIsCurrent

        if !resetCache {
            for candidate in candidates {
                if let state = cache.files[candidate.identity], candidate.size < state.offset {
                    resetCache = true
                    break
                }
            }
        }
        if resetCache {
            cache = ScanCache(
                schemaVersion: cacheSchemaVersion,
                dayStart: dayStart,
                codexHomeHash: codexHomeHash,
                files: [:]
            )
        }

        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let standardFormatter = ISO8601DateFormatter()
        standardFormatter.formatOptions = [.withInternetDateTime]

        var knownResponses = Set(cache.files.values.flatMap { $0.records.keys })
        var addedRecords = 0

        for candidate in candidates {
            var state = cache.files[candidate.identity] ?? .empty
            guard candidate.size > state.offset else { continue }

            let appendedData: Data
            do {
                let handle = try FileHandle(forReadingFrom: candidate.url)
                defer { try? handle.close() }
                try handle.seek(toOffset: UInt64(state.offset))
                appendedData = try handle.readToEnd() ?? Data()
            }
            guard let finalNewline = appendedData.lastIndex(of: 0x0A) else { continue }
            let completeEnd = appendedData.index(after: finalNewline)
            let completeData = appendedData[..<completeEnd]
            let baseOffset = state.offset

            try forEachUsageRecord(in: completeData) { record, lineOffset in
                guard record.type == "token_usage_record",
                      let timestamp = fractionalFormatter.date(from: record.timestamp)
                        ?? standardFormatter.date(from: record.timestamp),
                      timestamp >= dayStart,
                      timestamp < dayEnd,
                      timestamp <= now
                else { return }

                let usage = record.payload.usage
                guard usage.inputTokens >= 0,
                      (usage.cachedInputTokens ?? 0) >= 0,
                      usage.outputTokens >= 0,
                      (usage.reasoningOutputTokens ?? 0) >= 0
                else { return }

                let responseIdentity = record.payload.responseID
                    ?? "\(candidate.identity):\(baseOffset + lineOffset):\(record.timestamp)"
                let responseHash = hash(responseIdentity)
                guard knownResponses.insert(responseHash).inserted else { return }

                state.records[responseHash] = AccumulatedUsage(
                    inputTokens: usage.inputTokens,
                    cachedInputTokens: usage.cachedInputTokens ?? 0,
                    outputTokens: usage.outputTokens,
                    reasoningTokens: usage.reasoningOutputTokens ?? 0,
                    sessionHash: hash(record.payload.sessionID ?? candidate.identity)
                )
                addedRecords += 1
            }

            state.offset = try adding(state.offset, completeData.count)
            cache.files[candidate.identity] = state
        }

        if let cacheURL {
            try? writeCache(cache, to: cacheURL)
        }

        var usageByResponseHash: [String: AccumulatedUsage] = [:]
        for state in cache.files.values {
            for (responseHash, usage) in state.records where usageByResponseHash[responseHash] == nil {
                usageByResponseHash[responseHash] = usage
            }
        }
        let sessionHashes = Set(usageByResponseHash.values.map(\.sessionHash))
        let totals = try totals(for: usageByResponseHash, sessionHashes: sessionHashes)
        return Result(
            totals: totals,
            changed: resetCache || addedRecords > 0,
            usageByResponseHash: usageByResponseHash,
            sessionHashes: sessionHashes
        )
    }

    static func totals(
        for records: [String: AccumulatedUsage],
        sessionHashes: Set<String>? = nil
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
            sessionCount: (sessionHashes ?? Set(records.values.map(\.sessionHash))).count
        )
    }

    private static func resolvedCodexHome(_ configuredPath: String?) -> URL {
        if let configuredPath = configuredPath?.trimmingCharacters(in: .whitespacesAndNewlines),
           !configuredPath.isEmpty
        {
            return URL(fileURLWithPath: configuredPath, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
    }

    private static func recentlyModifiedRollouts(
        codexHome: URL,
        dayStart: Date,
        calendar: Calendar
    ) -> [Candidate] {
        let sessionsRoot = codexHome.appendingPathComponent("sessions", isDirectory: true)
        var candidates: [Candidate] = []
        var seenIdentities: Set<String> = []

        func appendJSONLFiles(in directory: URL, recursively: Bool = false) {
            let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]
            let fileURLs: [URL]
            if recursively {
                guard let enumerator = FileManager.default.enumerator(
                    at: directory,
                    includingPropertiesForKeys: keys,
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                ) else { return }
                fileURLs = enumerator.compactMap { $0 as? URL }
            } else {
                fileURLs = (try? FileManager.default.contentsOfDirectory(
                    at: directory,
                    includingPropertiesForKeys: keys,
                    options: [.skipsHiddenFiles]
                )) ?? []
            }

            for fileURL in fileURLs where fileURL.pathExtension.lowercased() == "jsonl" {
                let values = try? fileURL.resourceValues(forKeys: Set(keys))
                guard values?.isRegularFile == true,
                      let modifiedAt = values?.contentModificationDate,
                      modifiedAt >= dayStart,
                      let fileSize = values?.fileSize,
                      fileSize >= 0,
                      let identity = fileIdentity(fileURL),
                      seenIdentities.insert(identity).inserted
                else { continue }
                candidates.append(Candidate(url: fileURL, identity: identity, size: fileSize))
            }
        }

        for dayOffset in 0...activeSessionLookbackDays {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: dayStart) else { continue }
            let components = calendar.dateComponents([.year, .month, .day], from: date)
            guard let year = components.year, let month = components.month, let day = components.day else { continue }
            let directory = sessionsRoot
                .appendingPathComponent(String(format: "%04d", year), isDirectory: true)
                .appendingPathComponent(String(format: "%02d", month), isDirectory: true)
                .appendingPathComponent(String(format: "%02d", day), isDirectory: true)
            appendJSONLFiles(in: directory)
        }

        appendJSONLFiles(in: sessionsRoot)
        appendJSONLFiles(
            in: codexHome.appendingPathComponent("archived_sessions", isDirectory: true),
            recursively: true
        )
        return candidates.sorted { $0.identity < $1.identity }
    }

    private static func fileIdentity(_ url: URL) -> String? {
        var information = stat()
        guard lstat(url.path, &information) == 0 else { return nil }
        return "\(information.st_dev):\(information.st_ino)"
    }

    private static func forEachUsageRecord(
        in data: Data.SubSequence,
        body: (Record, Int) throws -> Void
    ) throws {
        var searchStart = data.startIndex
        while searchStart < data.endIndex,
              let markerRange = data.range(of: recordMarker, in: searchStart..<data.endIndex)
        {
            let lineStart = data[..<markerRange.lowerBound].lastIndex(of: 0x0A)
                .map { data.index(after: $0) }
                ?? data.startIndex
            let lineEnd = data[markerRange.upperBound...].firstIndex(of: 0x0A)
                ?? data.endIndex
            if lineStart < lineEnd,
               let record = try? JSONDecoder().decode(Record.self, from: data[lineStart..<lineEnd])
            {
                try body(record, data.distance(from: data.startIndex, to: lineStart))
            }
            searchStart = lineEnd < data.endIndex ? data.index(after: lineEnd) : data.endIndex
        }
    }

    private static func loadCache(from url: URL) -> ScanCache? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(ScanCache.self, from: data)
    }

    private static func writeCache(_ cache: ScanCache, to url: URL) throws {
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
        let temporary = directory.appendingPathComponent(".codex-scan-\(UUID().uuidString).tmp")
        try data.write(to: temporary, options: .withoutOverwriting)
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
        guard Darwin.rename(temporary.path, url.path) == 0 else {
            let code = errno
            try? manager.removeItem(at: temporary)
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private static func hash(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func adding(_ lhs: Int, _ rhs: Int) throws -> Int {
        let result = lhs.addingReportingOverflow(rhs)
        guard !result.overflow else { throw CocoaError(.coderReadCorrupt) }
        return result.partialValue
    }
}
