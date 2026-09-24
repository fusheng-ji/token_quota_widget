import CryptoKit
import Foundation

/// One response's counters. Cached input and reasoning are subsets, not extra tokens.
struct CodexResponseUsage: Codable, Hashable, Sendable {
    let inputTokens: Int
    let cachedInputTokens: Int
    let outputTokens: Int
    let reasoningTokens: Int
    let sessionHash: String
}

struct CodexDayWindow: Sendable {
    let start: Date
    let end: Date
    let cutoff: Date

    init(now: Date, calendar: Calendar) throws {
        start = calendar.startOfDay(for: now)
        guard let nextDay = calendar.date(byAdding: .day, value: 1, to: start) else {
            throw CocoaError(.coderReadCorrupt)
        }
        end = nextDay
        cutoff = now
    }

    func contains(_ timestamp: Date) -> Bool {
        timestamp >= start && timestamp < end && timestamp <= cutoff
    }
}

enum CodexUsageSupport {
    static func hash(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func nonempty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }

    static func homeURL(_ configuredPath: String?) -> URL {
        if let path = nonempty(configuredPath) {
            return URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex", isDirectory: true)
    }

    static func load<Value: Decodable>(_ type: Value.Type, from url: URL) -> Value? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(type, from: data)
    }

    static func adding(_ lhs: Int, _ rhs: Int) throws -> Int {
        let sum = lhs.addingReportingOverflow(rhs)
        guard !sum.overflow else { throw CocoaError(.coderReadCorrupt) }
        return sum.partialValue
    }
}

struct CodexCacheLocations {
    let directory: URL

    init(snapshotURL: URL) {
        directory = snapshotURL.deletingLastPathComponent()
    }

    var local: URL { directory.appendingPathComponent("beaver-meter-codex-scan-v2.json") }
    var remote: URL { directory.appendingPathComponent("beaver-meter-codex-remote-scan-v2.json") }
    var remoteV1: URL { directory.appendingPathComponent("beaver-meter-codex-remote-scan-v1.json") }
    var legacy: URL { directory.appendingPathComponent("beaver-meter-codex-legacy-v1.json") }
    var measurement: URL { directory.appendingPathComponent("beaver-meter-codex-measurement-v1.json") }
}

extension CodexTokenTotals {
    static let zero = CodexTokenTotals(
        totalTokens: 0, inputTokens: 0, cachedInputTokens: 0,
        outputTokens: 0, reasoningTokens: 0, sessionCount: 0
    )
}
