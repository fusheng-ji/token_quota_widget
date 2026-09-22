import Foundation
import XCTest

final class UsagePresentationTests: XCTestCase {
    private let now = UsageSnapshot.previewDate

    func testStatusSeverityDoesNotDependOnQuotaValue() {
        let failed = UsagePreviewScenario.error.snapshot.codexQuota
        let presentation = UsageStatusPresentation(failed, relativeTo: now)
        XCTAssertEqual(presentation.label, "Error")
        XCTAssertEqual(presentation.severity, .critical)
        XCTAssertEqual(presentation.icon, "exclamationmark.triangle.fill")
    }

    func testOldCacheBoundaryAndCachedSourceAreConsistent() {
        for (age, expectedLabel, expectedSeverity) in [
            (10_799.0, "Stale", UsageStatusPresentation.Severity.warning),
            (10_800.0, "Old cache", .critical)
        ] {
            let cached = UsageValue(status: .ready, source: .cache,
                                    measuredAt: now.addingTimeInterval(-age), lastAttemptAt: now,
                                    message: "Offline", value: UsageSnapshot.preview.codexQuota.value)
            let presentation = UsageStatusPresentation(cached, relativeTo: now)
            XCTAssertEqual(presentation.label, expectedLabel)
            XCTAssertEqual(presentation.severity, expectedSeverity)
            XCTAssertTrue(presentation.detail.contains("Offline"))
        }
    }

    func testRemoteFailureRetainsTokensWithoutChangingQuotaStatus() {
        let snapshot = UsagePreviewScenario.remoteUnavailable.snapshot
        let tokenPresentation = CodexDailyTokenPresentation(snapshot.codexTokens, relativeTo: now)
        XCTAssertEqual(tokenPresentation.value, "100K")
        XCTAssertEqual(tokenPresentation.status.label, "Stale")
        XCTAssertEqual(tokenPresentation.warningLabel, "Remote")
        XCTAssertEqual(UsageStatusPresentation(snapshot.codexQuota, relativeTo: now).label, "Demo")
        XCTAssertTrue(tokenPresentation.accessibilityText.contains("cached remote usage"))
    }

    func testYesterdayTokensAreNotPresentedAsToday() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let today = calendar.startOfDay(for: now).addingTimeInterval(30)
        let yesterday = UsageValue(status: .ready, source: .codexBarLocal,
                                   measuredAt: today.addingTimeInterval(-60), lastAttemptAt: today,
                                   message: nil, value: UsageSnapshot.preview.codexTokens.value)
        let presentation = CodexDailyTokenPresentation(yesterday, relativeTo: today, calendar: calendar)
        XCTAssertEqual(presentation.value, "—")
        XCTAssertNil(presentation.data.value)
        XCTAssertEqual(presentation.status.label, "No data")
        XCTAssertTrue(presentation.status.detail.contains("awaiting refresh"))
    }

    func testTokenZeroAndUnavailableRemainDistinct() {
        let zero = UsageValue(status: .ready, source: .codexBarLocal, measuredAt: now,
                              lastAttemptAt: now, message: nil,
                              value: CodexTokenTotals(totalTokens: 0, inputTokens: 0, cachedInputTokens: 0,
                                                     outputTokens: 0, reasoningTokens: 0, sessionCount: 0))
        XCTAssertEqual(CodexDailyTokenPresentation(zero, relativeTo: now).value, "0")
        XCTAssertEqual(CodexDailyTokenPresentation(UsagePreviewScenario.unavailable.snapshot.codexTokens,
                                                 relativeTo: now).value, "—")
    }

    func testLargeTokenValuesUseBillionsAndKeepFullAccessibleCount() {
        let presentation = CodexDailyTokenPresentation(UsagePreviewScenario.largeValues.snapshot.codexTokens,
                                                      relativeTo: now)
        XCTAssertEqual(presentation.value, "9.9B")
        XCTAssertTrue(presentation.accessibilityText.contains(9_876_543_210.formatted()))
    }

    func testPreviewScenariosHaveFixedDatesAndPreserveTwentyEvents() {
        for scenario in UsagePreviewScenario.allCases {
            XCTAssertEqual(scenario.snapshot.generatedAt, now)
        }
        XCTAssertEqual(UsagePreviewScenario.longList.snapshot.cursorCosts.value?.recentEvents.count, 20)
        XCTAssertEqual(UsageSnapshot.preview.codexQuota.measuredAt, now)
        XCTAssertEqual(UsageSnapshot.widgetDeepSeekSignedOutPreview.generatedAt, now)
    }
}
