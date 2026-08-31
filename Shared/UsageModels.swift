import Foundation

enum UsageDataStatus: String, Codable, Hashable, Sendable {
    case ready
    case stale
    case unavailable
    case unauthenticated
    case error
}

enum UsageDataSource: String, Codable, Hashable, Sendable {
    case codexBarLocal
    case cursorDashboard
    case accountAPI
    case cache
    case preview
    case none
}

struct UsageValue<Value: Codable & Hashable & Sendable>: Codable, Hashable, Sendable {
    let status: UsageDataStatus
    let source: UsageDataSource
    let measuredAt: Date?
    let lastAttemptAt: Date
    let message: String?
    let value: Value?

    var isStale: Bool { status == .stale || source == .cache }

    func age(at date: Date = .now) -> TimeInterval? {
        measuredAt.map { max(0, date.timeIntervalSince($0)) }
    }

    static func unavailable(_ message: String) -> Self {
        Self(
            status: .unavailable,
            source: .none,
            measuredAt: nil,
            lastAttemptAt: .now,
            message: message,
            value: nil
        )
    }
}

struct CodexTokenTotals: Codable, Hashable, Sendable {
    let totalTokens: Int
    let inputTokens: Int
    let cachedInputTokens: Int
    let outputTokens: Int
    let reasoningTokens: Int
    let sessionCount: Int
}

struct CursorCostEvent: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let occurredAt: Date
    let model: String
    let costUSD: Double?
    let tokenCount: Int?
    let kind: String?
}

struct CursorCostTotals: Codable, Hashable, Sendable {
    let todayCostUSD: Double?
    let recentEvents: [CursorCostEvent]

    var latestEvent: CursorCostEvent? { recentEvents.first }
}

struct CompactQuota: Codable, Hashable, Sendable {
    let label: String
    let used: Double?
    let limit: Double?
    let remaining: Double?
    let remainingPercent: Double?
    let resetAt: Date?
    let windowSeconds: Int?
    let detail: String
}
