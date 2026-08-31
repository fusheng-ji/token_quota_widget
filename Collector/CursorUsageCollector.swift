import CodexBarCore
import Foundation

enum CursorUsageCollector {
    static func collect(
        previousCosts: UsageValue<CursorCostTotals>,
        previousQuota: UsageValue<CompactQuota>,
        now: Date
    ) async -> (costs: UsageValue<CursorCostTotals>, quota: UsageValue<CompactQuota>) {
        do {
            let environment = ProcessInfo.processInfo.environment
            let isFixtureRun = environment["CURSOR_EVENTS_FIXTURE"] != nil
                && environment["CURSOR_SUMMARY_FIXTURE"] != nil
            let cookie = try isFixtureRun
                ? "fixture-session"
                : CursorAppAuthStore().loadSession().cookieHeader
            let client = CursorDashboardClient()
            async let eventsResult = client.fetchTodayEvents(cookieHeader: cookie, now: now)
            async let summaryResult = client.fetchSummary(cookieHeader: cookie)

            let costs: UsageValue<CursorCostTotals>
            do {
                costs = try await makeCosts(events: eventsResult, now: now)
            } catch {
                costs = CollectorSupport.stale(
                    previous: previousCosts,
                    attemptedAt: now,
                    status: CollectorSupport.status(for: error),
                    message: error.localizedDescription
                )
            }

            let quota: UsageValue<CompactQuota>
            do {
                quota = try await makeQuota(summary: summaryResult, now: now)
            } catch {
                quota = CollectorSupport.stale(
                    previous: previousQuota,
                    attemptedAt: now,
                    status: CollectorSupport.status(for: error),
                    message: error.localizedDescription
                )
            }
            return (costs, quota)
        } catch {
            let status = CollectorSupport.status(for: error)
            return (
                CollectorSupport.stale(
                    previous: previousCosts,
                    attemptedAt: now,
                    status: status,
                    message: error.localizedDescription
                ),
                CollectorSupport.stale(
                    previous: previousQuota,
                    attemptedAt: now,
                    status: status,
                    message: error.localizedDescription
                )
            )
        }
    }

    private static func makeCosts(
        events: [CursorUsageEvent],
        now: Date
    ) throws -> UsageValue<CursorCostTotals> {
        let valid = events
            .filter { $0.validTimestampMS != nil }
            .sorted { ($0.validTimestampMS ?? 0) > ($1.validTimestampMS ?? 0) }
        var totalCents = 0.0
        var totalIsComplete = true
        for event in valid {
            guard let cents = event.chargedCents, !event.chargedCentsIsInvalid else {
                totalIsComplete = false
                continue
            }
            let next = totalCents + cents
            guard next.isFinite else {
                totalIsComplete = false
                continue
            }
            totalCents = next
        }

        var occurrence: [String: Int] = [:]
        var recent: [CursorCostEvent] = []
        for event in valid {
            if recent.count == 20 { break }
            let timestamp = event.validTimestampMS ?? 0
            let model = event.model ?? "Unknown model"
            let chargeText: String
            if let chargedCents = event.chargedCents {
                chargeText = String(chargedCents)
            } else {
                chargeText = "unknown"
            }
            let key = "\(timestamp)-\(model)-\(chargeText)"
            let index = occurrence[key, default: 0]
            occurrence[key] = index + 1
            recent.append(
                CursorCostEvent(
                    id: "\(key)-\(index)",
                    occurredAt: Date(timeIntervalSince1970: Double(timestamp) / 1_000),
                    model: model,
                    costUSD: event.chargedCents.map { $0 / 100 },
                    tokenCount: event.tokenUsage?.totalTokens,
                    kind: event.kind
                )
            )
        }
        let value = CursorCostTotals(
            todayCostUSD: totalIsComplete ? totalCents / 100 : nil,
            recentEvents: recent
        )
        let message = totalIsComplete
            ? nil
            : "One or more Cursor calls did not report an actual charge; the daily total is hidden."
        return UsageValue(
            status: .ready,
            source: .cursorDashboard,
            measuredAt: now,
            lastAttemptAt: now,
            message: message,
            value: value
        )
    }

    private static func makeQuota(
        summary: CursorUsageSummary,
        now: Date
    ) throws -> UsageValue<CompactQuota> {
        let plan = summary.individualUsage?.plan
        let overall = summary.individualUsage?.overall
        let usedCents: Int
        let limitCents: Int
        let remainingCents: Int

        if let used = plan?.used, let limit = plan?.limit, limit > 0 {
            usedCents = used
            limitCents = limit
            remainingCents = plan?.remaining ?? max(0, limit - used)
        } else if let used = overall?.used, let limit = overall?.limit, limit > 0 {
            usedCents = used
            limitCents = limit
            remainingCents = overall?.remaining ?? max(0, limit - used)
        } else {
            throw CursorDashboardError.network(
                "Cursor Monthly usage did not include an individual limit."
            )
        }

        let used = Double(usedCents) / 100
        let limit = Double(limitCents) / 100
        let remaining = Double(max(0, remainingCents)) / 100
        let reset = CollectorSupport.parseISODate(summary.billingCycleEnd)
        let start = CollectorSupport.parseISODate(summary.billingCycleStart)
        let duration: Int? = if let start, let reset, reset > start {
            Int(reset.timeIntervalSince(start))
        } else {
            nil
        }
        let detail = "\(CollectorSupport.formatUSD(used)) / \(CollectorSupport.formatUSD(limit))" +
            " · \(CollectorSupport.formatUSD(remaining)) left"
        let quota = CompactQuota(
            label: "Cursor Monthly",
            used: used,
            limit: limit,
            remaining: remaining,
            remainingPercent: min(max(remaining / limit * 100, 0), 100),
            resetAt: reset,
            windowSeconds: duration,
            detail: detail
        )
        return UsageValue(
            status: .ready,
            source: .cursorDashboard,
            measuredAt: now,
            lastAttemptAt: now,
            message: nil,
            value: quota
        )
    }
}
