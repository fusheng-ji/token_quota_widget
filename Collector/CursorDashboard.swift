// Portions adapted from CodexBar at commit 5d7c1f29fd11ecbf697b3532340f75b25319f811.
// Copyright (c) 2026 Peter Steinberger. Licensed under the MIT License.

import CodexBarCore
import Foundation

enum CursorDashboardError: LocalizedError {
    case notInstalled
    case notLoggedIn
    case invalidSession(String)
    case network(String)
    case pagination(String)

    var errorDescription: String? {
        switch self {
        case .notInstalled: "Cursor account database was not found."
        case .notLoggedIn: "Cursor is not signed in."
        case let .invalidSession(message): message
        case let .network(message): message
        case let .pagination(message): message
        }
    }
}

struct CursorUsageEventsPage: Decodable {
    let totalUsageEventsCount: Int?
    let usageEventsDisplay: [CursorUsageEvent]

    private enum CodingKeys: String, CodingKey { case totalUsageEventsCount, usageEventsDisplay }
    private struct ResponseKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    init(from decoder: Decoder) throws {
        let responseKeys = try decoder.container(keyedBy: ResponseKey.self).allKeys
        if responseKeys.isEmpty {
            totalUsageEventsCount = 0
            usageEventsDisplay = []
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let count = CursorEventNumber.int64(container, .totalUsageEventsCount).flatMap(Int.init(exactly:))
        if let count, count < 0 {
            throw DecodingError.dataCorruptedError(forKey: .totalUsageEventsCount, in: container, debugDescription: "Cursor event count cannot be negative")
        }
        totalUsageEventsCount = count
        if count != nil, responseKeys.count == 1, responseKeys.first?.stringValue == CodingKeys.totalUsageEventsCount.rawValue {
            usageEventsDisplay = []
        } else {
            usageEventsDisplay = try container.decode([CursorUsageEvent].self, forKey: .usageEventsDisplay)
        }
    }
}

struct CursorUsageEvent: Decodable, Hashable {
    let timestampMS: Int64?
    let model: String?
    let tokenUsage: CursorEventTokenUsage?
    let kind: String?
    let chargedCents: Double?
    let chargedCentsIsInvalid: Bool

    private enum CodingKeys: String, CodingKey { case timestamp, model, tokenUsage, kind, chargedCents }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        timestampMS = CursorEventNumber.int64(container, .timestamp)
        model = (try? container.decode(String.self, forKey: .model)).flatMap { $0.isEmpty ? nil : $0 }
        tokenUsage = try? container.decode(CursorEventTokenUsage.self, forKey: .tokenUsage)
        kind = try? container.decode(String.self, forKey: .kind)
        let cost = CursorEventNumber.optionalDoubleState(container, .chargedCents)
        chargedCents = cost.value
        chargedCentsIsInvalid = cost.invalid
    }

    var validTimestampMS: Int64? {
        guard let timestampMS, timestampMS > 0 else { return nil }
        return timestampMS
    }
}

struct CursorEventTokenUsage: Decodable, Hashable {
    let inputTokens: Int
    let outputTokens: Int
    let cacheWriteTokens: Int
    let cacheReadTokens: Int

    private enum CodingKeys: String, CodingKey { case inputTokens, outputTokens, cacheWriteTokens, cacheReadTokens }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        inputTokens = CursorEventNumber.int(container, .inputTokens)
        outputTokens = CursorEventNumber.int(container, .outputTokens)
        cacheWriteTokens = CursorEventNumber.int(container, .cacheWriteTokens)
        cacheReadTokens = CursorEventNumber.int(container, .cacheReadTokens)
    }

    var totalTokens: Int? {
        var total = 0
        for value in [inputTokens, outputTokens, cacheWriteTokens, cacheReadTokens] {
            guard value >= 0 else { return nil }
            let result = total.addingReportingOverflow(value)
            guard !result.overflow else { return nil }
            total = result.partialValue
        }
        return total
    }
}

enum CursorEventNumber {
    struct OptionalDoubleState { let value: Double?; let invalid: Bool }

    static func int<K: CodingKey>(_ container: KeyedDecodingContainer<K>, _ key: K) -> Int {
        int64(container, key).flatMap(Int.init(exactly:)) ?? 0
    }

    static func int64<K: CodingKey>(_ container: KeyedDecodingContainer<K>, _ key: K) -> Int64? {
        if let value = try? container.decode(Int64.self, forKey: key) { return value }
        if let value = try? container.decode(Double.self, forKey: key) { return Int64(exactly: value) }
        if let value = try? container.decode(String.self, forKey: key) {
            return Int64(value) ?? Double(value).flatMap(Int64.init(exactly:))
        }
        return nil
    }

    static func optionalDoubleState<K: CodingKey>(_ container: KeyedDecodingContainer<K>, _ key: K) -> OptionalDoubleState {
        guard container.contains(key), (try? container.decodeNil(forKey: key)) != true else { return .init(value: nil, invalid: false) }
        let value: Double?
        if let number = try? container.decode(Double.self, forKey: key) { value = number }
        else if let number = try? container.decode(Int.self, forKey: key) { value = Double(number) }
        else if let text = try? container.decode(String.self, forKey: key) { value = Double(text) }
        else { value = nil }
        guard let value, value.isFinite, value >= 0 else { return .init(value: nil, invalid: true) }
        return .init(value: value, invalid: false)
    }
}

struct CursorDashboardClient {
    private let baseURL = URL(string: "https://cursor.com")!
    private let session: URLSession
    private let pageSize = 1000
    private let maxPages = 200

    init(session: URLSession = .shared) { self.session = session }

    func fetchSummary(cookieHeader: String) async throws -> CursorUsageSummary {
        if let fixture = ProcessInfo.processInfo.environment["CURSOR_SUMMARY_FIXTURE"] {
            return try JSONDecoder().decode(CursorUsageSummary.self, from: Data(contentsOf: URL(fileURLWithPath: fixture)))
        }
        var request = URLRequest(url: baseURL.appendingPathComponent("/api/usage-summary"))
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        let data = try await responseData(for: request)
        return try JSONDecoder().decode(CursorUsageSummary.self, from: data)
    }

    func fetchTodayEvents(cookieHeader: String, now: Date, calendar: Calendar = .current) async throws -> [CursorUsageEvent] {
        if let fixture = ProcessInfo.processInfo.environment["CURSOR_EVENTS_FIXTURE"] {
            return try JSONDecoder().decode(CursorUsageEventsPage.self, from: Data(contentsOf: URL(fileURLWithPath: fixture))).usageEventsDisplay
        }
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? now
        var pages: [[CursorUsageEvent]] = []
        var expectedTotal: Int?
        var completed = false
        for page in 1...maxPages {
            let response = try await fetchPage(cookieHeader: cookieHeader, page: page, start: start, end: end)
            if let total = response.totalUsageEventsCount {
                if let expectedTotal, expectedTotal != total {
                    throw CursorDashboardError.pagination("Cursor changed the total event count while paging.")
                }
                expectedTotal = total
            }
            if response.usageEventsDisplay.isEmpty { completed = true; break }
            pages.append(response.usageEventsDisplay)
            if response.usageEventsDisplay.count < pageSize { completed = true; break }
        }
        let raw = pages.flatMap(\.self)
        guard completed else { throw CursorDashboardError.pagination("Cursor pagination reached its safety limit.") }
        guard let expectedTotal else { return raw }
        guard raw.count >= expectedTotal else { throw CursorDashboardError.pagination("Cursor returned only \(raw.count) of \(expectedTotal) events.") }
        guard raw.count > expectedTotal else { return raw }
        var removals = raw.count - expectedTotal
        var result = pages.first ?? []
        for index in pages.indices.dropFirst() {
            let overlap = Self.boundaryOverlap(previous: pages[index - 1], current: pages[index])
            let remove = min(overlap, removals)
            result.append(contentsOf: pages[index].dropFirst(remove))
            removals -= remove
        }
        guard removals == 0, result.count == expectedTotal else {
            throw CursorDashboardError.pagination("Cursor page boundaries could not be reconciled.")
        }
        return result
    }

    private func fetchPage(cookieHeader: String, page: Int, start: Date, end: Date) async throws -> CursorUsageEventsPage {
        var request = URLRequest(url: baseURL.appendingPathComponent("/api/dashboard/get-filtered-usage-events"))
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("https://cursor.com", forHTTPHeaderField: "Origin")
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "page": page,
            "pageSize": pageSize,
            "startDate": String(Int64((start.timeIntervalSince1970 * 1000).rounded())),
            "endDate": String(Int64((end.timeIntervalSince1970 * 1000).rounded()))
        ])
        let data = try await responseData(for: request)
        return try JSONDecoder().decode(CursorUsageEventsPage.self, from: data)
    }

    private func responseData(for request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw CursorDashboardError.network("Cursor returned an invalid response.") }
        if http.statusCode == 401 || http.statusCode == 403 { throw CursorDashboardError.notLoggedIn }
        guard http.statusCode == 200 else { throw CursorDashboardError.network("Cursor returned HTTP \(http.statusCode).") }
        return data
    }

    private static func boundaryOverlap(previous: [CursorUsageEvent], current: [CursorUsageEvent]) -> Int {
        let limit = min(previous.count, current.count)
        guard limit > 0 else { return 0 }
        for count in stride(from: limit, through: 1, by: -1)
            where previous.suffix(count).elementsEqual(current.prefix(count)) { return count }
        return 0
    }
}
