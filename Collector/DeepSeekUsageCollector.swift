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

private struct DeepSeekUsagePayload: Decodable, Sendable {
    let monthTokens: Int
    let monthRequests: Int
    let monthCost: Double?
    let currency: String

    func validated() throws -> Self {
        guard monthTokens >= 0,
              monthRequests >= 0,
              monthCost.map({ $0.isFinite && $0 >= 0 }) ?? true,
              !currency.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DeepSeekPlatformError.invalidResponse("DeepSeek usage changed format.")
        }
        return self
    }
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

    private func data(
        path: String,
        token: String,
        fixtureEnvironmentKey: String
    ) async throws -> Data {
        if let fixture = ProcessInfo.processInfo.environment[fixtureEnvironmentKey] {
            return try Data(contentsOf: URL(fileURLWithPath: fixture))
        }
        let url = baseURL.appendingPathComponent(path)
        guard url.host == "platform.deepseek.com" else {
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
}

enum DeepSeekUsageCollector {
    static func collect(
        previous: UsageValue<DeepSeekUsageTotals>,
        now: Date,
        calendar: Calendar = .current
    ) async -> UsageValue<DeepSeekUsageTotals> {
        let environment = ProcessInfo.processInfo.environment
        let environmentToken = environment["DEEPSEEK_PLATFORM_TOKEN"]
        let isFixtureRun = environment["DEEPSEEK_SUMMARY_FIXTURE"] != nil
            && environment["DEEPSEEK_USAGE_FIXTURE"] != nil
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
            let client = DeepSeekPlatformClient()
            async let summary = client.fetchSummary(token: token)
            async let usage = fetchUsage(
                token: token,
                now: now,
                calendar: calendar,
                fixture: environment["DEEPSEEK_USAGE_FIXTURE"]
            )
            let (resolvedSummary, resolvedUsage) = try await (summary, usage)
            return UsageValue(
                status: .ready,
                source: .deepSeekPlatform,
                measuredAt: now,
                lastAttemptAt: now,
                message: nil,
                value: DeepSeekUsageTotals(
                    monthTokens: resolvedUsage.monthTokens,
                    monthRequests: resolvedUsage.monthRequests,
                    monthCosts: resolvedUsage.monthCost.map {
                        [DeepSeekMoney(currency: resolvedUsage.currency, amount: $0)]
                    } ?? [],
                    balances: resolvedSummary.balances,
                    grantedBalances: resolvedSummary.grantedBalances,
                    totalCosts: resolvedSummary.totalCosts
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

    private static func fetchUsage(
        token: String,
        now: Date,
        calendar: Calendar,
        fixture: String?
    ) async throws -> DeepSeekUsagePayload {
        if let fixture {
            do {
                return try JSONDecoder()
                    .decode(
                        DeepSeekUsagePayload.self,
                        from: Data(contentsOf: URL(fileURLWithPath: fixture))
                    )
                    .validated()
            } catch let error as DeepSeekPlatformError {
                throw error
            } catch {
                throw DeepSeekPlatformError.invalidResponse("DeepSeek usage changed format.")
            }
        }

        let usage = try await DeepSeekUsageFetcher.fetchUsageSummary(
            platformToken: token,
            now: now,
            calendar: calendar
        )
        return try DeepSeekUsagePayload(
            monthTokens: usage.currentMonthTokens,
            monthRequests: usage.currentMonthRequestCount,
            monthCost: usage.currentMonthCost,
            currency: usage.currency
        ).validated()
    }
}
