import CodexBarCore
import Foundation

enum DeepSeekPlatformError: LocalizedError {
    case notConnected
    case sessionExpired
    case network(String)
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .notConnected:
            "DeepSeek is not connected. Open the menu and choose Connect in browser."
        case .sessionExpired:
            "The DeepSeek session expired. Reconnect in the system browser from the menu."
        case let .network(message), let .invalidResponse(message):
            message
        }
    }
}

private struct DeepSeekSummaryPayload: Sendable {
    let balances: [DeepSeekMoney]
    let grantedBalances: [DeepSeekMoney]
    let totalCosts: [DeepSeekMoney]
}

private struct DeepSeekAmountPayload: Sendable {
    struct Model: Sendable {
        let name: String
        let tokens: Int
        let requests: Int
    }
    let models: [Model]
}

private struct DeepSeekCostPayload: Sendable {
    let totals: [DeepSeekMoney]
    let byModel: [String: [DeepSeekMoney]]
}

struct DeepSeekPlatformClient {
    private let baseURL = URL(string: "https://platform.deepseek.com")!
    private let session: URLSession

    init(session: URLSession = .shared) { self.session = session }

    fileprivate func fetchSummary(token: String) async throws -> DeepSeekSummaryPayload {
        let data = try await data(
            path: "/api/v0/users/get_user_summary",
            token: token,
            fixtureEnvironmentKey: "DEEPSEEK_SUMMARY_FIXTURE"
        )
        let root = try object(data)
        let business = try businessData(root, endpoint: "summary")
        return DeepSeekSummaryPayload(
            balances: try moneyArray(business["normal_wallets"], amountKey: "balance", required: true),
            grantedBalances: try moneyArray(business["bonus_wallets"], amountKey: "balance", required: true),
            totalCosts: try moneyArray(business["total_costs"], amountKey: "amount", required: false)
        )
    }

    func validate(token: String) async throws {
        _ = try await fetchSummary(token: token)
    }

    fileprivate func fetchAmount(token: String, start: Date, end: Date, timezoneSeconds: Int) async throws -> DeepSeekAmountPayload {
        let data = try await data(
            path: "/api/v0/usage/by_api_key/amount",
            token: token,
            query: usageQuery(start: start, end: end, timezoneSeconds: timezoneSeconds),
            fixtureEnvironmentKey: "DEEPSEEK_AMOUNT_FIXTURE"
        )
        let root = try object(data)
        let business = try businessData(root, endpoint: "token usage")
        guard let series = business["series"] as? [[String: Any]] else {
            throw DeepSeekPlatformError.invalidResponse("DeepSeek token usage changed format.")
        }

        var totals: [String: (tokens: Int, requests: Int)] = [:]
        for item in series {
            guard let model = nonempty(item["model"]),
                  let buckets = item["buckets"] as? [[String: Any]] else {
                throw DeepSeekPlatformError.invalidResponse("DeepSeek token usage changed format.")
            }
            for bucket in buckets {
                guard let usage = bucket["usage"] as? [String: Any],
                      let cacheHit = safeIntOptional(usage["PROMPT_CACHE_HIT_TOKEN"]),
                      let cacheMiss = safeIntOptional(usage["PROMPT_CACHE_MISS_TOKEN"]),
                      let response = safeIntOptional(usage["RESPONSE_TOKEN"]),
                      let requests = safeIntOptional(usage["REQUEST"]) else {
                    throw DeepSeekPlatformError.invalidResponse("DeepSeek token usage changed format.")
                }
                let tokens = safeSum([cacheHit, cacheMiss, response])
                let current = totals[model, default: (0, 0)]
                totals[model] = (
                    safeSum([current.tokens, tokens]),
                    safeSum([current.requests, requests])
                )
            }
        }
        return DeepSeekAmountPayload(
            models: totals.map { .init(name: $0.key, tokens: $0.value.tokens, requests: $0.value.requests) }
        )
    }

    fileprivate func fetchCost(token: String, start: Date, end: Date, timezoneSeconds: Int) async throws -> DeepSeekCostPayload {
        let data = try await data(
            path: "/api/v0/usage/by_api_key/cost",
            token: token,
            query: usageQuery(start: start, end: end, timezoneSeconds: timezoneSeconds),
            fixtureEnvironmentKey: "DEEPSEEK_COST_FIXTURE"
        )
        let root = try object(data)
        let business = try businessData(root, endpoint: "cost usage")
        guard let currencyGroups = business["data"] as? [[String: Any]] else {
            throw DeepSeekPlatformError.invalidResponse("DeepSeek cost usage changed format.")
        }

        var totals: [String: Double] = [:]
        var modelTotals: [String: [String: Double]] = [:]
        for group in currencyGroups {
            guard let currency = nonempty(group["currency"]),
                  let series = group["series"] as? [[String: Any]] else {
                throw DeepSeekPlatformError.invalidResponse("DeepSeek cost usage changed format.")
            }
            for item in series {
                guard let model = nonempty(item["model"]),
                      let buckets = item["buckets"] as? [[String: Any]] else {
                    throw DeepSeekPlatformError.invalidResponse("DeepSeek cost usage changed format.")
                }
                for bucket in buckets {
                    guard let cost = safeDouble(bucket["cost"]) else {
                        throw DeepSeekPlatformError.invalidResponse("DeepSeek cost usage changed format.")
                    }
                    totals[currency, default: 0] += cost
                    modelTotals[model, default: [:]][currency, default: 0] += cost
                }
            }
        }
        return DeepSeekCostPayload(
            totals: money(totals),
            byModel: modelTotals.mapValues(money)
        )
    }

    private func usageQuery(start: Date, end: Date, timezoneSeconds: Int) -> [URLQueryItem] {
        [
            URLQueryItem(name: "start", value: String(Int(start.timeIntervalSince1970))),
            URLQueryItem(name: "end", value: String(Int(end.timeIntervalSince1970))),
            URLQueryItem(name: "tz", value: String(timezoneSeconds))
        ]
    }

    private func data(
        path: String,
        token: String,
        query: [URLQueryItem] = [],
        fixtureEnvironmentKey: String
    ) async throws -> Data {
        if let fixture = ProcessInfo.processInfo.environment[fixtureEnvironmentKey] {
            return try Data(contentsOf: URL(fileURLWithPath: fixture))
        }
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url, url.host == "platform.deepseek.com" else {
            throw DeepSeekPlatformError.network("DeepSeek endpoint validation failed.")
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw DeepSeekPlatformError.network("DeepSeek returned an invalid response.")
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw DeepSeekPlatformError.sessionExpired
        }
        guard http.statusCode == 200 else {
            throw DeepSeekPlatformError.network("DeepSeek returned HTTP \(http.statusCode).")
        }
        return data
    }

    private func object(_ data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DeepSeekPlatformError.invalidResponse("DeepSeek returned invalid JSON.")
        }
        return object
    }

    private func businessData(_ root: [String: Any], endpoint: String) throws -> [String: Any] {
        if let code = safeIntOptional(root["code"]), code != 0 {
            if code == 401 || code == 403 { throw DeepSeekPlatformError.sessionExpired }
            throw DeepSeekPlatformError.network("DeepSeek \(endpoint) returned code \(code).")
        }
        guard let data = root["data"] as? [String: Any],
              let business = data["biz_data"] as? [String: Any] else {
            throw DeepSeekPlatformError.invalidResponse("DeepSeek \(endpoint) changed format.")
        }
        return business
    }

    private func moneyArray(_ value: Any?, amountKey: String, required: Bool) throws -> [DeepSeekMoney] {
        if value == nil, !required { return [] }
        guard let values = value as? [[String: Any]] else {
            throw DeepSeekPlatformError.invalidResponse("DeepSeek account summary changed format.")
        }
        return try values.map { item in
            guard let currency = nonempty(item["currency"]),
                  let amount = safeDouble(item[amountKey]) else {
                throw DeepSeekPlatformError.invalidResponse("DeepSeek account summary changed format.")
            }
            return DeepSeekMoney(currency: currency, amount: amount)
        }.sorted { $0.currency < $1.currency }
    }

    private func money(_ values: [String: Double]) -> [DeepSeekMoney] {
        values.compactMap { currency, amount in
            guard amount.isFinite, amount >= 0 else { return nil }
            return DeepSeekMoney(currency: currency, amount: amount)
        }.sorted { $0.currency < $1.currency }
    }

    private func nonempty(_ value: Any?) -> String? {
        guard let text = value as? String, !text.isEmpty else { return nil }
        return text
    }

    private func safeDouble(_ value: Any?) -> Double? {
        let number: Double?
        if value is Bool { number = nil }
        else if let value = value as? NSNumber { number = value.doubleValue }
        else if let value = value as? String { number = Double(value) }
        else { number = nil }
        guard let number, number.isFinite, number >= 0 else { return nil }
        return number
    }

    private func safeIntOptional(_ value: Any?) -> Int? {
        guard let number = safeDouble(value), number.rounded() == number else { return nil }
        return Int(exactly: number)
    }

    private func safeSum(_ values: [Int]) -> Int {
        values.reduce(into: 0) { result, value in
            let addition = result.addingReportingOverflow(max(0, value))
            result = addition.overflow ? Int.max : addition.partialValue
        }
    }
}

enum DeepSeekUsageCollector {
    static func collect(
        previous: UsageValue<DeepSeekUsageTotals>,
        now: Date,
        calendar: Calendar = .current
    ) async -> UsageValue<DeepSeekUsageTotals> {
        let environmentToken = ProcessInfo.processInfo.environment["DEEPSEEK_PLATFORM_TOKEN"]
        let isFixtureRun = ProcessInfo.processInfo.environment["DEEPSEEK_SUMMARY_FIXTURE"] != nil
            && ProcessInfo.processInfo.environment["DEEPSEEK_AMOUNT_FIXTURE"] != nil
            && ProcessInfo.processInfo.environment["DEEPSEEK_COST_FIXTURE"] != nil
        guard let token = isFixtureRun ? "fixture-session" : (environmentToken ?? DeepSeekCredentialStore.readToken()),
              !token.isEmpty else {
            return CollectorSupport.stale(
                previous: previous,
                attemptedAt: now,
                status: .unauthenticated,
                message: DeepSeekPlatformError.notConnected.localizedDescription
            )
        }

        do {
            let interval = calendar.dateInterval(of: .month, for: now)
            let start = interval?.start ?? calendar.startOfDay(for: now)
            let timezoneSeconds = calendar.timeZone.secondsFromGMT(for: now)
            let client = DeepSeekPlatformClient()
            async let summary = client.fetchSummary(token: token)

            if !isFixtureRun {
                async let usage = DeepSeekUsageFetcher.fetchUsageSummary(
                    platformToken: token,
                    now: now,
                    calendar: calendar
                )
                let (account, detailedUsage) = try await (summary, usage)

                return UsageValue(
                    status: .ready,
                    source: .deepSeekPlatform,
                    measuredAt: now,
                    lastAttemptAt: now,
                    message: nil,
                    value: DeepSeekUsageTotals(
                        monthTokens: detailedUsage.currentMonthTokens,
                        monthRequests: detailedUsage.currentMonthRequestCount,
                        monthCosts: detailedUsage.currentMonthCost.map {
                            [DeepSeekMoney(currency: detailedUsage.currency, amount: $0)]
                        } ?? [],
                        balances: account.balances,
                        grantedBalances: account.grantedBalances,
                        totalCosts: account.totalCosts,
                        models: []
                    )
                )
            }

            async let amount = client.fetchAmount(
                token: token,
                start: start,
                end: now,
                timezoneSeconds: timezoneSeconds
            )
            async let cost = client.fetchCost(
                token: token,
                start: start,
                end: now,
                timezoneSeconds: timezoneSeconds
            )
            let (resolvedSummary, resolvedAmount, resolvedCost) = try await (summary, amount, cost)
            let modelCosts = resolvedCost.byModel
            let models = resolvedAmount.models
                .map {
                    DeepSeekModelUsage(
                        model: $0.name,
                        tokens: $0.tokens,
                        requests: $0.requests,
                        costs: modelCosts[$0.name] ?? []
                    )
                }
                .sorted { $0.tokens > $1.tokens }
            let monthTokens = models.reduce(0) { result, model in
                let next = result.addingReportingOverflow(model.tokens)
                return next.overflow ? Int.max : next.partialValue
            }
            let monthRequests = models.reduce(0) { result, model in
                let next = result.addingReportingOverflow(model.requests)
                return next.overflow ? Int.max : next.partialValue
            }
            return UsageValue(
                status: .ready,
                source: .deepSeekPlatform,
                measuredAt: now,
                lastAttemptAt: now,
                message: nil,
                value: DeepSeekUsageTotals(
                    monthTokens: monthTokens,
                    monthRequests: monthRequests,
                    monthCosts: resolvedCost.totals,
                    balances: resolvedSummary.balances,
                    grantedBalances: resolvedSummary.grantedBalances,
                    totalCosts: resolvedSummary.totalCosts,
                    models: models
                )
            )
        } catch {
            let status: UsageDataStatus
            if let deepSeekError = error as? DeepSeekPlatformError,
               case .sessionExpired = deepSeekError {
                status = .unauthenticated
            } else if let deepSeekError = error as? DeepSeekUsageError,
                      deepSeekError == .invalidPlatformToken {
                status = .unauthenticated
            } else {
                status = .error
            }
            return CollectorSupport.stale(
                previous: previous,
                attemptedAt: now,
                status: status,
                message: error.localizedDescription
            )
        }
    }
}
