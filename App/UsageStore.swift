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
    @Published private var refreshSchedule = RefreshSchedule()
    @Published private(set) var refreshError: String?
    @Published private(set) var deepSeekConnectionState: DeepSeekConnectionState = .idle

    private var lastAutomaticRefresh: Date?
    private var deepSeekConnectionTask: Task<Void, Never>?
    private var snapshotObservationTask: Task<Void, Never>?
    private var codexActivityRefreshTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private let allowsLiveUpdates: Bool

    var isRefreshing: Bool { refreshSchedule.showsFullRefresh }

    init(snapshot: UsageSnapshot = .load(), observesSnapshotChanges: Bool = true) {
        self.snapshot = snapshot
        allowsLiveUpdates = observesSnapshotChanges
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
            codexActivityRefreshTask = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    do {
                        try await Task.sleep(for: .seconds(45))
                    } catch {
                        return
                    }
                    self?.requestRefresh(.codex)
                }
            }
        }
    }

    deinit {
        snapshotObservationTask?.cancel()
        codexActivityRefreshTask?.cancel()
        refreshTask?.cancel()
        deepSeekConnectionTask?.cancel()
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
        let codex = CodexDailyTokenPresentation(snapshot.codexTokens)
        return "\(codex.accessibilityText), Cursor latest call \(values.latestCost), " +
            "DeepSeek balance \(values.deepSeekBalance)"
    }

    private var menuBarValues: (tokens: String, latestCost: String, deepSeekBalance: String) {
        (
            CodexDailyTokenPresentation(snapshot.codexTokens).value,
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
        requestRefresh(.all)
    }

    private func requestRefresh(_ mode: RefreshSchedule.Mode) {
        guard allowsLiveUpdates, let next = refreshSchedule.request(mode) else { return }
        startRefresh(next)
    }

    private func startRefresh(_ mode: RefreshSchedule.Mode) {
        if mode == .all {
            refreshError = nil
            lastAutomaticRefresh = .now
        }
        let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/BeaverMeterCollector")
        let script = Bundle.main.url(forResource: "collect_beaver_meter", withExtension: "sh")
        let output = UsageSnapshot.snapshotURL.path
        refreshTask = Task { [weak self] in
            let cancellation = SubprocessCancellation()
            let result = await withTaskCancellationHandler {
                await Task.detached(priority: .utility) {
                    switch mode {
                    case .all:
                        CollectorProcessRunner.refresh(helper: helper, script: script, output: output, cancellation: cancellation)
                    case .codex:
                        CollectorProcessRunner.refreshCodexTokens(helper: helper, script: script, output: output, cancellation: cancellation)
                    }
                }.value
            } onCancel: {
                cancellation.cancel()
            }
            guard !Task.isCancelled else { return }
            self?.finishRefresh(mode, result: result)
        }
    }

    private func finishRefresh(_ mode: RefreshSchedule.Mode, result: CollectorProcessResult) {
        // Only a newer snapshot changes the UI or requests a WidgetKit timeline.
        adoptNewerSnapshotFromDisk()
        if result.status != 0 {
            refreshError = result.message.isEmpty
                ? "Refresh failed; the previous data was preserved."
                : result.message
        } else if mode == .all {
            refreshError = nil
        }
        if mode == .all, deepSeekConnectionState == .loadingUsage {
            if result.status == 0, snapshot.deepseekUsage.status == .ready {
                deepSeekConnectionState = .connected
            } else {
                deepSeekConnectionState = .failed(
                    refreshError ?? snapshot.deepseekUsage.message ?? "Could not load DeepSeek usage."
                )
            }
        }
        refreshTask = nil
        if let next = refreshSchedule.finish() { startRefresh(next) }
    }

    func connectDeepSeekInBrowser() {
        guard allowsLiveUpdates else { return }
        guard let url = URL(string: "https://platform.deepseek.com/usage") else { return }
        guard NSWorkspace.shared.open(url) else {
            deepSeekConnectionState = .failed("Could not open the system browser.")
            return
        }
        deepSeekConnectionState = .waitingForLogin
        beginDeepSeekBrowserImport()
    }

    func checkDeepSeekBrowserSession() {
        guard allowsLiveUpdates else { return }
        deepSeekConnectionState = .checkingBrowser
        beginDeepSeekBrowserImport()
    }

    private func beginDeepSeekBrowserImport() {
        deepSeekConnectionTask?.cancel()
        let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/BeaverMeterCollector")

        deepSeekConnectionTask = Task { [weak self] in
            let cancellation = SubprocessCancellation()
            await withTaskCancellationHandler {
                for _ in 0..<100 {
                    guard !Task.isCancelled, self != nil else { return }
                    let result = await Task.detached(priority: .utility) {
                        CollectorProcessRunner.importBrowserSession(helper: helper, cancellation: cancellation)
                    }.value
                    guard !Task.isCancelled else { return }
                    if self?.handleDeepSeekImport(result) != false { return }

                    switch DeepSeekSafariSessionReader.readToken() {
                    case let .token(token):
                        let safariResult = await Task.detached(priority: .utility) {
                            CollectorProcessRunner.importToken(helper: helper, token: token, cancellation: cancellation)
                        }.value
                        guard !Task.isCancelled else { return }
                        if self?.handleDeepSeekImport(safariResult) != false { return }
                    case .notFound:
                        break
                    case let .unavailable(message):
                        self?.deepSeekConnectionState = .failed(message)
                        return
                    }

                    do {
                        try await Task.sleep(for: .seconds(3))
                    } catch {
                        return
                    }
                }
                self?.deepSeekConnectionState = .failed(
                    "No signed-in DeepSeek session was found in the system browser."
                )
            } onCancel: {
                cancellation.cancel()
            }
        }
    }

    /// Exit codes distinguish a successful import, a pending login and a terminal failure.
    private func handleDeepSeekImport(_ result: CollectorProcessResult) -> Bool {
        if result.status == 3 { return false }
        if result.status == 0 {
            deepSeekConnectionState = .loadingUsage
            refresh()
        } else {
            deepSeekConnectionState = .failed(
                result.message.isEmpty ? "Could not import the DeepSeek browser session." : result.message
            )
        }
        return true
    }
}
