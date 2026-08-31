import Foundation

private struct CodexAuthFile: Decodable {
    struct Tokens: Decodable {
        let accessToken: String?
        let accountID: String?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case accountID = "account_id"
        }
    }

    let tokens: Tokens?
}

private struct CodexUsageResponse: Decodable {
    struct RateLimit: Decodable {
        let primaryWindow: Window?
        let secondaryWindow: Window?

        enum CodingKeys: String, CodingKey {
            case primaryWindow = "primary_window"
            case secondaryWindow = "secondary_window"
        }
    }

    struct Window: Decodable {
        let usedPercent: Double?
        let resetAt: Double?
        let resetAfterSeconds: Double?
        let limitWindowSeconds: Int?

        enum CodingKeys: String, CodingKey {
            case usedPercent = "used_percent"
            case resetAt = "reset_at"
            case resetAfterSeconds = "reset_after_seconds"
            case limitWindowSeconds = "limit_window_seconds"
        }
    }

    struct Credits: Decodable {
        let unlimited: Bool?
        let hasCredits: Bool?
        let balance: String?

        enum CodingKeys: String, CodingKey {
            case unlimited
            case hasCredits = "has_credits"
            case balance
        }
    }

    let rateLimit: RateLimit?
    let credits: Credits?

    enum CodingKeys: String, CodingKey {
        case rateLimit = "rate_limit"
        case credits
    }
}

private enum CodexQuotaError: LocalizedError {
    case notLoggedIn

    var errorDescription: String? { "Codex is not signed in." }
}

enum CodexQuotaCollector {
    static func collect(
        previous: UsageValue<CompactQuota>,
        now: Date
    ) async -> UsageValue<CompactQuota> {
        do {
            let response = try await fetchResponse()
            let windows = [
                response.rateLimit?.primaryWindow,
                response.rateLimit?.secondaryWindow
            ].compactMap { $0 }.compactMap { window in
                makeQuota(window: window, now: now)
            }

            let quota: CompactQuota
            if let tightest = windows.min(by: {
                ($0.remainingPercent ?? 101) < ($1.remainingPercent ?? 101)
            }) {
                quota = tightest
            } else if response.credits?.unlimited == true {
                quota = CompactQuota(
                    label: "Codex credits",
                    used: nil,
                    limit: nil,
                    remaining: nil,
                    remainingPercent: nil,
                    resetAt: nil,
                    windowSeconds: nil,
                    detail: "Unlimited"
                )
            } else if response.credits?.hasCredits == true {
                quota = CompactQuota(
                    label: "Codex credits",
                    used: nil,
                    limit: nil,
                    remaining: nil,
                    remainingPercent: nil,
                    resetAt: nil,
                    windowSeconds: nil,
                    detail: "Balance \(response.credits?.balance ?? "available")"
                )
            } else {
                throw URLError(.cannotParseResponse)
            }

            return UsageValue(
                status: .ready,
                source: .accountAPI,
                measuredAt: now,
                lastAttemptAt: now,
                message: nil,
                value: quota
            )
        } catch {
            let status: UsageDataStatus = error is CodexQuotaError ? .unauthenticated : .error
            return CollectorSupport.stale(
                previous: previous,
                attemptedAt: now,
                status: status,
                message: "Codex quota refresh failed: \(error.localizedDescription)"
            )
        }
    }

    private static func fetchResponse() async throws -> CodexUsageResponse {
        if let fixture = ProcessInfo.processInfo.environment["CODEX_USAGE_FIXTURE"] {
            return try JSONDecoder().decode(
                CodexUsageResponse.self,
                from: Data(contentsOf: URL(fileURLWithPath: fixture))
            )
        }

        let codexRoot = ProcessInfo.processInfo.environment["CODEX_HOME"]
            .map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
        let auth = try JSONDecoder().decode(
            CodexAuthFile.self,
            from: Data(contentsOf: codexRoot.appendingPathComponent("auth.json"))
        )
        guard let token = auth.tokens?.accessToken, !token.isEmpty else {
            throw CodexQuotaError.notLoggedIn
        }

        var request = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!)
        request.timeoutInterval = 12
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("codex-cli", forHTTPHeaderField: "User-Agent")
        if let accountID = auth.tokens?.accountID, !accountID.isEmpty {
            request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        }

        let (data, urlResponse) = try await URLSession.shared.data(for: request)
        guard let http = urlResponse as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw CodexQuotaError.notLoggedIn
        }
        guard http.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(CodexUsageResponse.self, from: data)
    }

    private static func makeQuota(
        window: CodexUsageResponse.Window,
        now: Date
    ) -> CompactQuota? {
        guard let seconds = window.limitWindowSeconds,
              seconds > 0,
              let used = window.usedPercent else {
            return nil
        }
        let remaining = min(max(100 - used, 0), 100)
        let reset = window.resetAt.map { Date(timeIntervalSince1970: $0) }
            ?? window.resetAfterSeconds.map { now.addingTimeInterval($0) }
        let label: String
        if seconds == 604_800 {
            label = "Codex Week"
        } else if seconds % 86_400 == 0 {
            label = "Codex \(seconds / 86_400)d"
        } else if seconds % 3_600 == 0 {
            label = "Codex \(seconds / 3_600)h"
        } else {
            label = "Codex quota"
        }
        return CompactQuota(
            label: label,
            used: nil,
            limit: nil,
            remaining: nil,
            remainingPercent: remaining,
            resetAt: reset,
            windowSeconds: seconds,
            detail: "\(Int(remaining.rounded()))% left"
        )
    }
}
