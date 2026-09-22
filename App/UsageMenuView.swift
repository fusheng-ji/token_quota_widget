import Combine
import SwiftUI

struct UsageMenuView: View {
    @ObservedObject var store: UsageStore
    var automaticRefresh = true
    var scrollsContent = true
    var updatedDescriptionOverride: String?
    var viewHeight: CGFloat = 700
    var referenceDate: Date?
    var refreshErrorOverride: String?
    private var presentationDate: Date { referenceDate ?? .now }
    private let timer = Timer.publish(every: 300, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            quotaFooter
            if let error = refreshErrorOverride ?? store.refreshError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
            }
            Divider()
            actions
        }
        .frame(width: 410, height: viewHeight)
        .onAppear {
            if automaticRefresh { store.refreshIfNeeded() }
        }
        .onReceive(timer) { _ in
            if automaticRefresh { store.refreshIfNeeded(force: true) }
        }
    }

    @ViewBuilder
    private var content: some View {
        if scrollsContent {
            ScrollView { sections }
        } else {
            sections
        }
    }

    private var sections: some View {
        VStack(spacing: 14) {
            codexSection
            Divider()
            cursorSection
            Divider()
            deepseekSection
        }
        .padding(16)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("BeaverMeter")
                    .font(.headline)
                Text(
                    store.isRefreshing
                        ? "Refreshing…"
                        : "Updated \(updatedDescriptionOverride ?? UsageFormatting.relativeAge(store.snapshot.generatedAt, relativeTo: presentationDate))"
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if store.isRefreshing {
                ProgressView().controlSize(.small)
            } else {
                Button { store.refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain)
                    .help("Refresh now")
                    .accessibilityLabel("Refresh usage now")
            }
        }
        .padding(14)
    }

    private var dailyCodexTokens: UsageValue<CodexTokenTotals> {
        CodexDailyTokenPresentation(store.snapshot.codexTokens, relativeTo: presentationDate).data
    }

    private var codexSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            UsageSectionHeader(title: "Codex today", systemImage: "sparkles", tint: .teal,
                               value: dailyCodexTokens, referenceDate: presentationDate)
            if let tokens = dailyCodexTokens.value {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(UsageFormatting.tokens(tokens.totalTokens))
                        .font(.system(size: 36, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .accessibilityLabel("\(tokens.totalTokens.formatted()) tokens today")
                    Text("tokens")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(tokens.sessionCount) session\(tokens.sessionCount == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 10) {
                    TokenMetric(label: "Input", value: tokens.inputTokens)
                    TokenMetric(label: "Cached", value: tokens.cachedInputTokens)
                    TokenMetric(label: "Output", value: tokens.outputTokens)
                    TokenMetric(label: "Reasoning", value: tokens.reasoningTokens)
                }
                SectionMessage(message: dailyCodexTokens.message, status: dailyCodexTokens.status)
            } else {
                EmptyState(message: dailyCodexTokens.message ?? "No Codex token data yet.")
            }
        }
    }

    private var cursorSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            UsageSectionHeader(title: "Cursor today", systemImage: "cursorarrow.rays", tint: .indigo,
                               value: store.snapshot.cursorCosts, referenceDate: presentationDate)
            if let costs = store.snapshot.cursorCosts.value {
                HStack(alignment: .firstTextBaseline) {
                    Text(UsageFormatting.usd(costs.todayCostUSD, minimumDigits: 2, maximumDigits: 4))
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text("actual charge")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                Text("Recent model calls")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                if costs.recentEvents.isEmpty {
                    Text("No Cursor model calls today.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 10)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(costs.recentEvents) { event in
                            CursorEventRow(event: event)
                            if event.id != costs.recentEvents.last?.id { Divider() }
                        }
                    }
                }
                SectionMessage(message: store.snapshot.cursorCosts.message, status: store.snapshot.cursorCosts.status)
            } else {
                EmptyState(message: store.snapshot.cursorCosts.message ?? "No Cursor cost data yet.")
            }
        }
    }

    private var deepseekSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            UsageSectionHeader(title: "DeepSeek this month", systemImage: "waveform.path.ecg.rectangle", tint: .blue,
                               value: store.snapshot.deepseekUsage, referenceDate: presentationDate)

            if let usage = store.snapshot.deepseekUsage.value {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(UsageFormatting.money(UsageFormatting.firstValidMoney(usage.balances)))
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                    Text("balance")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }

                HStack(spacing: 12) {
                    DeepSeekMetric(label: "Month cost", value: UsageFormatting.moneyList(usage.monthCosts))
                    DeepSeekMetric(label: "Tokens", value: UsageFormatting.tokens(usage.monthTokens))
                    DeepSeekMetric(label: "Requests", value: usage.monthRequests?.formatted() ?? "—")
                }

                let additionalBalances = Array(usage.balances.dropFirst())
                if !additionalBalances.isEmpty {
                    DeepSeekDetailLine(
                        label: "Other balances",
                        value: UsageFormatting.moneyList(additionalBalances)
                    )
                }
                if !usage.grantedBalances.isEmpty {
                    DeepSeekDetailLine(
                        label: "Granted balance",
                        value: UsageFormatting.moneyList(usage.grantedBalances)
                    )
                }
                if !usage.totalCosts.isEmpty {
                    DeepSeekDetailLine(
                        label: "Total cost",
                        value: UsageFormatting.moneyList(usage.totalCosts)
                    )
                }

            } else {
                EmptyState(message: store.snapshot.deepseekUsage.message ?? "No DeepSeek usage yet.")
            }

            HStack {
                if store.snapshot.deepseekUsage.value != nil {
                    SectionMessage(message: store.snapshot.deepseekUsage.message, status: store.snapshot.deepseekUsage.status)
                }
                Spacer()
                if store.deepSeekConnectionState == .loadingUsage {
                    Button("Loading…") {}
                        .controlSize(.small)
                        .disabled(true)
                } else if store.isConnectingDeepSeek {
                    Button("Check now") { store.checkDeepSeekBrowserSession() }
                        .controlSize(.small)
                } else if store.snapshot.deepseekUsage.status == .unauthenticated
                    || store.snapshot.deepseekUsage.value == nil {
                    Button("Connect in browser…") { store.connectDeepSeekInBrowser() }
                        .controlSize(.small)
                } else {
                    Button("Reconnect in browser…") { store.connectDeepSeekInBrowser() }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
            }

            if let message = store.deepSeekConnectionMessage {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if store.isConnectingDeepSeek {
                        ProgressView().controlSize(.mini)
                    } else if case .failed = store.deepSeekConnectionState {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                    Text(message)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var quotaFooter: some View {
        HStack(spacing: 12) {
            QuotaLabel(systemImage: "cursorarrow", tint: .indigo, value: store.snapshot.cursorQuota, referenceDate: presentationDate)
            Divider().frame(height: 28)
            QuotaLabel(systemImage: "sparkles", tint: .teal, value: store.snapshot.codexQuota, referenceDate: presentationDate)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var actions: some View {
        HStack {
            Label("Credentials stay local · snapshots contain no credentials", systemImage: "lock.fill")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain)
                .font(.caption)
        }
        .padding(12)
    }
}

#Preview("Menu popover") {
    UsageMenuView(
        store: UsageStore(snapshot: .preview, observesSnapshotChanges: false),
        automaticRefresh: false,
        scrollsContent: false,
        updatedDescriptionOverride: "from demo data",
        referenceDate: UsageSnapshot.previewDate
    )
}
