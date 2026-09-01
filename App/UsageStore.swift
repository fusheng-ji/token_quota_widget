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
    private var refreshQueued = false

    init(snapshot: UsageSnapshot = .load()) {
        self.snapshot = snapshot
    }

    var menuBarText: String {
        let tokens = UsageFormatting.tokens(snapshot.codexTokens.value?.totalTokens)
        let latestCost = UsageFormatting.usd(
            snapshot.cursorCosts.value?.latestEvent?.costUSD,
            minimumDigits: 2,
            maximumDigits: 3
        )
        let deepSeekBalance = UsageFormatting.money(
            UsageFormatting.firstValidMoney(snapshot.deepseekUsage.value?.balances ?? [])
        )
        return "\(tokens) · C \(latestCost) · D \(deepSeekBalance)"
    }

    var menuBarAccessibilityText: String {
        let tokens = UsageFormatting.tokens(snapshot.codexTokens.value?.totalTokens)
        let latestCost = UsageFormatting.usd(
            snapshot.cursorCosts.value?.latestEvent?.costUSD,
            minimumDigits: 2,
            maximumDigits: 3
        )
        let deepSeekBalance = UsageFormatting.money(
            UsageFormatting.firstValidMoney(snapshot.deepseekUsage.value?.balances ?? [])
        )
        return "Codex today \(tokens) tokens, Cursor latest call \(latestCost), DeepSeek balance \(deepSeekBalance)"
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

        let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/CodexWeekCollector")
        let script = Bundle.main.url(forResource: "collect_codex_week", withExtension: "sh")
        let output = UsageSnapshot.snapshotURL.path

        Task {
            let result = await Task.detached(priority: .utility) {
                Self.runCollector(helper: helper, script: script, output: output)
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
        let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/CodexWeekCollector")

        deepSeekConnectionTask = Task { [weak self] in
            guard let self else { return }
            for _ in 0..<100 {
                guard !Task.isCancelled else { return }
                let result = await Task.detached(priority: .utility) {
                    Self.runDeepSeekBrowserImporter(helper: helper)
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
                        Self.runDeepSeekTokenImporter(helper: helper, token: token)
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

    nonisolated private static func runCollector(
        helper: URL,
        script: URL?,
        output: String
    ) -> (status: Int32, message: String) {
        let process = Process()
        let errorPipe = Pipe()

        if FileManager.default.isExecutableFile(atPath: helper.path) {
            process.executableURL = helper
            process.arguments = ["--output", output]
        } else if let script {
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = [script.path, output]
        } else {
            return (-1, "The bundled usage collector is missing. Reinstall AI Token Quota.")
        }

        process.standardError = errorPipe
        do {
            try process.run()
            process.waitUntilExit()
            let message = String(
                data: errorPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return (process.terminationStatus, message)
        } catch {
            return (-1, error.localizedDescription)
        }
    }

    nonisolated private static func runDeepSeekBrowserImporter(
        helper: URL
    ) -> (status: Int32, message: String) {
        guard FileManager.default.isExecutableFile(atPath: helper.path) else {
            return (-1, "The bundled usage collector is missing. Reinstall AI Token Quota.")
        }

        let process = Process()
        let errorPipe = Pipe()
        process.executableURL = helper
        process.arguments = ["--import-deepseek-browser-session"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()
            let message = String(
                data: errorPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return (process.terminationStatus, message)
        } catch {
            return (-1, error.localizedDescription)
        }
    }

    nonisolated private static func runDeepSeekTokenImporter(
        helper: URL,
        token: String
    ) -> (status: Int32, message: String) {
        guard FileManager.default.isExecutableFile(atPath: helper.path) else {
            return (-1, "The bundled usage collector is missing. Reinstall AI Token Quota.")
        }

        let process = Process()
        let inputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = helper
        process.arguments = ["--import-deepseek-token-stdin"]
        process.standardInput = inputPipe
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errorPipe

        do {
            try process.run()
            inputPipe.fileHandleForWriting.write(Data(token.utf8))
            try? inputPipe.fileHandleForWriting.close()
            process.waitUntilExit()
            let message = String(
                data: errorPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return (process.terminationStatus, message)
        } catch {
            try? inputPipe.fileHandleForWriting.close()
            return (-1, error.localizedDescription)
        }
    }
}
