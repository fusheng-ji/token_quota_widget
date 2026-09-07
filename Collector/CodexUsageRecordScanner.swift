import Foundation

/// Reads the per-response usage records emitted by recent Codex Desktop builds.
/// CodexBar currently reads the accompanying legacy `token_count` events; these
/// records provide a reliable fallback when a long-running task crosses a day
/// boundary and the legacy events are not materialized into the daily report.
enum CodexUsageRecordScanner {
    private static let activeSessionLookbackDays = 30
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

    static func collect(
        codexHomePath: String?,
        now: Date,
        calendar: Calendar = .current
    ) throws -> CodexTokenTotals? {
        let codexHome = resolvedCodexHome(codexHomePath)
        let dayStart = calendar.startOfDay(for: now)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
            throw CocoaError(.coderReadCorrupt)
        }

        let candidates = recentlyModifiedRollouts(
            codexHome: codexHome,
            dayStart: dayStart,
            calendar: calendar
        )
        guard !candidates.isEmpty else { return nil }

        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let standardFormatter = ISO8601DateFormatter()
        standardFormatter.formatOptions = [.withInternetDateTime]

        var inputTokens = 0
        var cachedInputTokens = 0
        var outputTokens = 0
        var reasoningTokens = 0
        var responseIDs: Set<String> = []
        var sessionIDs: Set<String> = []
        var recordCount = 0

        for fileURL in candidates {
            let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
            try forEachUsageRecord(in: data) { record in
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

                let identity = record.payload.responseID
                    ?? "\(fileURL.path):\(record.timestamp):\(recordCount)"
                guard responseIDs.insert(identity).inserted else { return }

                inputTokens = try adding(inputTokens, usage.inputTokens)
                cachedInputTokens = try adding(cachedInputTokens, usage.cachedInputTokens ?? 0)
                outputTokens = try adding(outputTokens, usage.outputTokens)
                reasoningTokens = try adding(reasoningTokens, usage.reasoningOutputTokens ?? 0)
                sessionIDs.insert(record.payload.sessionID ?? fileURL.path)
                recordCount += 1
            }
        }

        guard recordCount > 0 else { return nil }
        return CodexTokenTotals(
            totalTokens: try adding(inputTokens, outputTokens),
            inputTokens: inputTokens,
            cachedInputTokens: cachedInputTokens,
            outputTokens: outputTokens,
            reasoningTokens: reasoningTokens,
            sessionCount: sessionIDs.count
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
    ) -> [URL] {
        let sessionsRoot = codexHome.appendingPathComponent("sessions", isDirectory: true)
        var candidates: [URL] = []
        var seenPaths: Set<String> = []

        func appendJSONLFiles(in directory: URL, recursively: Bool = false) {
            let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey]
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
                      modifiedAt >= dayStart
                else { continue }
                let path = fileURL.standardizedFileURL.path
                guard seenPaths.insert(path).inserted else { continue }
                candidates.append(fileURL)
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
        return candidates.sorted { $0.path < $1.path }
    }

    private static func forEachUsageRecord(
        in data: Data,
        body: (Record) throws -> Void
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
                try body(record)
            }
            searchStart = lineEnd < data.endIndex ? data.index(after: lineEnd) : data.endIndex
        }
    }

    private static func adding(_ lhs: Int, _ rhs: Int) throws -> Int {
        let result = lhs.addingReportingOverflow(rhs)
        guard !result.overflow else { throw CocoaError(.coderReadCorrupt) }
        return result.partialValue
    }
}
