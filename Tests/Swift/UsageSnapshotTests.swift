import Foundation
import XCTest

final class UsageSnapshotTests: XCTestCase {
    func testVersionThreeSnapshotRoundTrips() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoded = try XCTUnwrap(UsageSnapshot.decode(encoder.encode(UsageSnapshot.preview)))

        XCTAssertEqual(decoded.schemaVersion, 3)
        XCTAssertEqual(decoded.codexTokens.value?.totalTokens, 100_000)
        XCTAssertEqual(decoded.cursorCosts.value?.recentEvents.count, 3)
        XCTAssertNil(decoded.cursorQuota.value?.used)
    }

    func testV2QuotaSnapshotMigratesWithoutInventingUsage() throws {
        let data = try XCTUnwrap("""
        {
          "schemaVersion": 2,
          "generatedAt": "2026-08-31T10:00:00Z",
          "providers": [
            {
              "id": "cursor",
              "measuredAt": "2026-08-31T10:00:00Z",
              "summaryQuota": {
                "label": "Monthly usage",
                "remainingPercent": 57.5,
                "resetAt": "2026-09-01T00:00:00Z",
                "windowSeconds": 2678400,
                "detail": "Example monthly quota"
              },
              "windows": []
            },
            {
              "id": "codex",
              "measuredAt": "2026-08-31T10:00:00Z",
              "summaryQuota": null,
              "windows": [{
                "label": "Week",
                "remainingPercent": 41,
                "resetAt": "2026-09-03T00:00:00Z",
                "windowSeconds": 604800,
                "detail": null
              }]
            }
          ]
        }
        """.data(using: .utf8))

        let snapshot = try XCTUnwrap(UsageSnapshot.decode(data))
        XCTAssertNil(snapshot.codexTokens.value)
        XCTAssertNil(snapshot.cursorCosts.value)
        XCTAssertEqual(snapshot.cursorQuota.status, .stale)
        XCTAssertEqual(snapshot.cursorQuota.source, .cache)
        XCTAssertEqual(snapshot.codexQuota.value?.remainingPercent, 41)
    }

    func testCachedAgeAndStatusAreExplicit() {
        let measured = Date(timeIntervalSince1970: 1_000)
        let cached = UsageValue(
            status: UsageDataStatus.stale,
            source: UsageDataSource.cache,
            measuredAt: measured,
            lastAttemptAt: Date(timeIntervalSince1970: 2_000),
            message: "offline",
            value: CodexTokenTotals(totalTokens: 10, inputTokens: 8, cachedInputTokens: 3, outputTokens: 2, reasoningTokens: 1, sessionCount: 1)
        )
        XCTAssertTrue(cached.isStale)
        XCTAssertEqual(cached.age(at: Date(timeIntervalSince1970: 12_000)), 11_000)
    }

    func testTokenFormattingIsCompact() {
        XCTAssertEqual(UsageFormatting.tokens(400), "400")
        XCTAssertEqual(UsageFormatting.tokens(400_000), "400K")
        XCTAssertEqual(UsageFormatting.tokens(nil), "—")
    }

    func testQuotaPercentageIsClamped() {
        XCTAssertEqual(UsageFormatting.clampedPercent(-4), 0)
        XCTAssertEqual(UsageFormatting.clampedPercent(42.5), 42.5)
        XCTAssertEqual(UsageFormatting.clampedPercent(104), 100)
        XCTAssertNil(UsageFormatting.clampedPercent(nil))
    }

    func testResetCountdownFormatting() {
        let now = Date(timeIntervalSince1970: 1_000)
        XCTAssertEqual(UsageFormatting.resetCountdown(nil, relativeTo: now), "Reset unavailable")
        XCTAssertEqual(UsageFormatting.resetCountdown(now, relativeTo: now), "Reset pending")
        XCTAssertEqual(UsageFormatting.resetCountdown(now.addingTimeInterval(6 * 86_400 + 13 * 3_600), relativeTo: now), "Resets in 6d 13h")
        XCTAssertEqual(UsageFormatting.resetCountdown(now.addingTimeInterval(2 * 3_600 + 17 * 60), relativeTo: now), "Resets in 2h 17m")
    }

    func testStaleAgeFormatting() {
        let now = Date(timeIntervalSince1970: 20_000)
        XCTAssertEqual(UsageFormatting.cacheAge(now.addingTimeInterval(-4 * 3_600), relativeTo: now), "Stale · 4h old")
    }
}
