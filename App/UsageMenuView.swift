import Combine
import SwiftUI

struct UsageMenuView: View {
    @ObservedObject var store: UsageStore
    var automaticRefresh = true
    var scrollsContent = true
    var updatedDescriptionOverride: String?
    private let timer = Timer.publish(every: 300, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            quotaFooter
            Divider()
            actions
        }
        .frame(width: 390, height: 610)
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
        VStack(spacing: 18) {
            codexSection
            Divider()
            cursorSection
        }
        .padding(16)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Cursor + Codex")
                    .font(.headline)
                Text(
                    store.isRefreshing
                        ? "Refreshing…"
                        : "Updated \(updatedDescriptionOverride ?? UsageFormatting.relativeAge(store.snapshot.generatedAt))"
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
            }
        }
        .padding(14)
    }

    private var codexSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Codex today", systemImage: "sparkles")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.teal)
                Spacer()
                StatusPill(value: store.snapshot.codexTokens)
            }
            if let tokens = store.snapshot.codexTokens.value {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(UsageFormatting.tokens(tokens.totalTokens))
                        .font(.system(size: 36, weight: .semibold, design: .rounded))
                    Text("tokens")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(tokens.sessionCount) session\(tokens.sessionCount == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 18) {
                    TokenMetric(label: "Input", value: tokens.inputTokens)
                    TokenMetric(label: "Cached", value: tokens.cachedInputTokens)
                    TokenMetric(label: "Output", value: tokens.outputTokens)
                    TokenMetric(label: "Reasoning", value: tokens.reasoningTokens)
                }
            } else {
                EmptyState(message: store.snapshot.codexTokens.message ?? "No Codex token data yet.")
            }
            SectionMessage(message: store.snapshot.codexTokens.message, status: store.snapshot.codexTokens.status)
        }
    }

    private var cursorSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Cursor today", systemImage: "cursorarrow.rays")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.indigo)
                Spacer()
                StatusPill(value: store.snapshot.cursorCosts)
            }
            if let costs = store.snapshot.cursorCosts.value {
                HStack(alignment: .firstTextBaseline) {
                    Text(UsageFormatting.usd(costs.todayCostUSD, minimumDigits: 2, maximumDigits: 4))
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
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
            } else {
                EmptyState(message: store.snapshot.cursorCosts.message ?? "No Cursor cost data yet.")
            }
            SectionMessage(message: store.snapshot.cursorCosts.message, status: store.snapshot.cursorCosts.status)
        }
    }

    private var quotaFooter: some View {
        HStack(spacing: 12) {
            QuotaLabel(systemImage: "cursorarrow", tint: .indigo, value: store.snapshot.cursorQuota)
            Divider().frame(height: 28)
            QuotaLabel(systemImage: "sparkles", tint: .teal, value: store.snapshot.codexQuota)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var actions: some View {
        HStack {
            Label("Local data · credentials are not saved", systemImage: "lock.fill")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain)
                .font(.caption)
        }
        .padding(12)
        .overlay(alignment: .topLeading) {
            if let error = store.refreshError {
                Text(error).font(.caption2).foregroundStyle(.red).offset(y: -22)
            }
        }
    }
}

#Preview("Menu popover") {
    UsageMenuView(
        store: UsageStore(snapshot: .preview),
        automaticRefresh: false,
        scrollsContent: false,
        updatedDescriptionOverride: "from demo data"
    )
}
