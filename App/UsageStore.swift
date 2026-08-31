import Combine
import Foundation
import WidgetKit

@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var snapshot: UsageSnapshot
    @Published private(set) var isRefreshing = false
    @Published private(set) var refreshError: String?

    private var lastAutomaticRefresh: Date?

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
        return "\(tokens) · \(latestCost)"
    }

    func refreshIfNeeded(force: Bool = false) {
        if !force, let lastAutomaticRefresh, Date().timeIntervalSince(lastAutomaticRefresh) < 30 {
            return
        }
        refresh()
    }

    func refresh() {
        guard !isRefreshing else { return }
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
            } else {
                refreshError = result.message.isEmpty
                    ? "Refresh failed; the previous data was preserved."
                    : result.message
            }
        }
    }

    func reloadSnapshot() {
        snapshot = UsageSnapshot.load()
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
            return (-1, "The bundled usage collector is missing. Reinstall Cursor + Codex.")
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
}
