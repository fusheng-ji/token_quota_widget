import Darwin
import Foundation

extension UsageSnapshot {
    static var snapshotURL: URL {
        let home: URL = {
            guard let entry = getpwuid(getuid()) else {
                return FileManager.default.homeDirectoryForCurrentUser
            }
            return URL(fileURLWithPath: String(cString: entry.pointee.pw_dir), isDirectory: true)
        }()
        return home.appendingPathComponent("Library/Application Support/CodexWeek/codex-week-snapshot.json")
    }

    static func load() -> UsageSnapshot {
        guard let data = try? Data(contentsOf: snapshotURL) else { return .unavailable }
        return decode(data) ?? .unavailable
    }

    static func decode(_ data: Data) -> UsageSnapshot? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let snapshot = try? decoder.decode(UsageSnapshot.self, from: data),
           snapshot.schemaVersion == Self.currentSchemaVersion {
            return snapshot
        }
        if let previous = try? decoder.decode(PreviousUsageSnapshot.self, from: data),
           previous.schemaVersion == 3 {
            return previous.migrated
        }
        if let legacy = try? decoder.decode(LegacyQuotaSnapshot.self, from: data) {
            return legacy.migrated
        }
        return nil
    }
}

private struct PreviousUsageSnapshot: Codable {
    let schemaVersion: Int
    let generatedAt: Date
    let codexTokens: UsageValue<CodexTokenTotals>
    let cursorCosts: UsageValue<CursorCostTotals>
    let cursorQuota: UsageValue<CompactQuota>
    let codexQuota: UsageValue<CompactQuota>

    var migrated: UsageSnapshot {
        UsageSnapshot(
            schemaVersion: UsageSnapshot.currentSchemaVersion,
            generatedAt: generatedAt,
            codexTokens: codexTokens,
            cursorCosts: cursorCosts,
            cursorQuota: cursorQuota,
            codexQuota: codexQuota,
            deepseekUsage: .unavailable("Connect DeepSeek in your browser to load account usage and balance.")
        )
    }
}

private enum LegacyProviderID: String, Codable {
    case cursor
    case codex
}

private struct LegacyQuotaValue: Codable {
    let label: String
    let remainingPercent: Double?
    let resetAt: Date?
    let windowSeconds: Int?
    let detail: String?
}

private struct LegacyProviderQuota: Codable {
    let id: LegacyProviderID
    let measuredAt: Date?
    let summaryQuota: LegacyQuotaValue?
    let windows: [LegacyQuotaValue]

    var effectiveSummary: LegacyQuotaValue? {
        summaryQuota ?? windows
            .filter { $0.remainingPercent != nil }
            .min { ($0.remainingPercent ?? 101) < ($1.remainingPercent ?? 101) }
    }
}

private struct LegacyQuotaSnapshot: Codable {
    let schemaVersion: Int
    let generatedAt: Date
    let providers: [LegacyProviderQuota]

    var migrated: UsageSnapshot {
        UsageSnapshot(
            schemaVersion: UsageSnapshot.currentSchemaVersion,
            generatedAt: generatedAt,
            codexTokens: .unavailable("Refresh to calculate today's Codex tokens."),
            cursorCosts: .unavailable("Refresh to load today's Cursor model calls."),
            cursorQuota: migrateQuota(
                providers.first { $0.id == .cursor },
                defaultLabel: "Cursor Monthly"
            ),
            codexQuota: migrateQuota(
                providers.first { $0.id == .codex },
                defaultLabel: "Codex quota"
            ),
            deepseekUsage: .unavailable("Connect DeepSeek in your browser to load account usage and balance.")
        )
    }

    private func migrateQuota(
        _ provider: LegacyProviderQuota?,
        defaultLabel: String
    ) -> UsageValue<CompactQuota> {
        guard let provider, let quota = provider.effectiveSummary else {
            return .unavailable("Refresh to load this quota.")
        }
        let remaining = quota.remainingPercent.map { min(max($0, 0), 100) }
        return UsageValue(
            status: .stale,
            source: .cache,
            measuredAt: provider.measuredAt ?? generatedAt,
            lastAttemptAt: generatedAt,
            message: "Migrated from the previous quota-only snapshot.",
            value: CompactQuota(
                label: quota.label.isEmpty ? defaultLabel : quota.label,
                used: nil,
                limit: nil,
                remaining: nil,
                remainingPercent: remaining,
                resetAt: quota.resetAt,
                windowSeconds: quota.windowSeconds,
                detail: quota.detail ?? remaining.map { "\(Int($0.rounded()))% left" } ?? "Quota available"
            )
        )
    }
}
