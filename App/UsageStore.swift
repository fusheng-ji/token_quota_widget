import AppKit
import Combine
import Foundation
import WidgetKit

enum DeepSeekConnectionState: Equatable {
    case idle
    case waitingForLogin
    case checkingBrowser
    case loadingUsage
    case connected
    case failed(String)

    var isBusy: Bool {
        switch self {
        case .waitingForLogin, .checkingBrowser, .loadingUsage: true
        default: false
        }
    }

    var message: String? {
        switch self {
        case .idle: nil
        case .waitingForLogin: "Finish signing in in your browser. Waiting for the DeepSeek session…"
        case .checkingBrowser: "Checking the system browser session…"
        case .loadingUsage: "Connected. Loading current DeepSeek usage…"
        case .connected: "Connected · DeepSeek usage is up to date."
        case let .failed(message): message
        }
    }
}

@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var snapshot: UsageSnapshot
    @Published private(set) var isRefreshing = false
    @Published private(set) var refreshError: String?
    @Published private(set) var deepSeekConnectionState: DeepSeekConnectionState = .idle

    private var lastAutomaticRefresh: Date?
    private var deepSeekConnectionTask: Task<Void, Never>?
    private var snapshotObservationTask: Task<Void, Never>?
    private var refreshQueued = false

    init(snapshot: UsageSnapshot = .load(), observesSnapshotChanges: Bool = true) {
        self.snapshot = snapshot
        if observesSnapshotChanges {
            snapshotObservationTask = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    do {
                        try await Task.sleep(for: .seconds(15))
                    } catch {
                        return
                    }
                    self?.adoptNewerSnapshotFromDisk()
                }
            }
        }
    }

    private func adoptNewerSnapshotFromDisk() {
        guard let data = try? Data(contentsOf: UsageSnapshot.snapshotURL),
              let latest = UsageSnapshot.decode(data),
              latest.generatedAt > snapshot.generatedAt
        else { return }

        snapshot = latest
        WidgetCenter.shared.reloadAllTimelines()
    }

    var menuBarText: String {
        let values = menuBarValues
        return "\(values.tokens) · C \(values.latestCost) · D \(values.deepSeekBalance)"
    }

    var menuBarAccessibilityText: String {
        let values = menuBarValues
        return "Codex today \(values.tokens) tokens, Cursor latest call \(values.latestCost), " +
            "DeepSeek balance \(values.deepSeekBalance)"
    }

    private var menuBarValues: (tokens: String, latestCost: String, deepSeekBalance: String) {
        (
            UsageFormatting.tokens(snapshot.codexTokens.value?.totalTokens),
            UsageFormatting.usd(
                snapshot.cursorCosts.value?.latestEvent?.costUSD,
                minimumDigits: 2,
                maximumDigits: 3
            ),
            UsageFormatting.money(
                UsageFormatting.firstValidMoney(snapshot.deepseekUsage.value?.balances ?? [])
            )
        )
    }

    var isConnectingDeepSeek: Bool {
        deepSeekConnectionState.isBusy
    }

    var deepSeekConnectionMessage: String? {
        deepSeekConnectionState.message
    }

    func refreshIfNeeded(force: Bool = false) {
        if !force, let lastAutomaticRefresh, Date().timeIntervalSince(lastAutomaticRefresh) < 30 {
            return
        }
        refresh()
    }

    func refresh() {
        guard !isRefreshing else {
            refreshQueued = true
            return
        }
        isRefreshing = true
        refreshError = nil
        lastAutomaticRefresh = .now

        let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/BeaverMeterCollector")
        let script = Bundle.main.url(forResource: "collect_codex_week", withExtension: "sh")
        let output = UsageSnapshot.snapshotURL.path

        Task {
            let result = await Task.detached(priority: .utility) {
                CollectorProcessRunner.refresh(helper: helper, script: script, output: output)
            }.value

            snapshot = UsageSnapshot.load()
            isRefreshing = false
            if result.status == 0 {
                WidgetCenter.shared.reloadAllTimelines()
                if deepSeekConnectionState == .loadingUsage {
                    switch snapshot.deepseekUsage.status {
                    case .ready:
                        deepSeekConnectionState = .connected
                    case .stale:
                        deepSeekConnectionState = .failed(
                            snapshot.deepseekUsage.message ?? "DeepSeek refresh failed; cached data is shown."
                        )
                    default:
                        deepSeekConnectionState = .failed(
                            snapshot.deepseekUsage.message ?? "Could not load DeepSeek usage."
                        )
                    }
                }
            } else {
                refreshError = result.message.isEmpty
                    ? "Refresh failed; the previous data was preserved."
                    : result.message
                if deepSeekConnectionState == .loadingUsage {
                    deepSeekConnectionState = .failed(
                        result.message.isEmpty ? "Could not load DeepSeek usage." : result.message
                    )
                }
            }
            if refreshQueued {
                refreshQueued = false
                refresh()
            }
        }
    }

    func connectDeepSeekInBrowser() {
        guard let url = URL(string: "https://platform.deepseek.com/usage") else { return }
        guard NSWorkspace.shared.open(url) else {
            deepSeekConnectionState = .failed("Could not open the system browser.")
            return
        }
        deepSeekConnectionState = .waitingForLogin
        beginDeepSeekBrowserImport()
    }

    func checkDeepSeekBrowserSession() {
        deepSeekConnectionState = .checkingBrowser
        beginDeepSeekBrowserImport()
    }

    private func beginDeepSeekBrowserImport() {
        deepSeekConnectionTask?.cancel()
        let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/BeaverMeterCollector")

        deepSeekConnectionTask = Task { [weak self] in
            guard let self else { return }
            for _ in 0..<100 {
                guard !Task.isCancelled else { return }
                let result = await Task.detached(priority: .utility) {
                    CollectorProcessRunner.importBrowserSession(helper: helper)
                }.value

                guard !Task.isCancelled else { return }
                if result.status == 0 {
                    self.deepSeekConnectionState = .loadingUsage
                    self.refresh()
                    return
                }
                if result.status != 3 {
                    self.deepSeekConnectionState = .failed(
                        result.message.isEmpty
                            ? "Could not import the DeepSeek browser session."
                            : result.message
                    )
                    return
                }

                switch DeepSeekSafariSessionReader.readToken() {
                case let .token(token):
                    let safariResult = await Task.detached(priority: .utility) {
                        CollectorProcessRunner.importToken(helper: helper, token: token)
                    }.value
                    if safariResult.status == 0 {
                        self.deepSeekConnectionState = .loadingUsage
                        self.refresh()
                        return
                    }
                    if safariResult.status != 3 {
                        self.deepSeekConnectionState = .failed(
                            safariResult.message.isEmpty
                                ? "Could not validate the DeepSeek Safari session."
                                : safariResult.message
                        )
                        return
                    }
                case .notFound:
                    break
                case let .unavailable(message):
                    self.deepSeekConnectionState = .failed(message)
                    return
                }

                do {
                    try await Task.sleep(nanoseconds: 3_000_000_000)
                } catch {
                    return
                }
            }
            self.deepSeekConnectionState = .failed(
                "No signed-in DeepSeek session was found in the system browser."
            )
        }
    }
}
