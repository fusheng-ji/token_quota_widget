import SwiftUI

struct TokenMetric: View {
    let label: String
    let value: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(UsageFormatting.tokens(value)).font(.caption.weight(.semibold)).monospacedDigit()
        }
    }
}

struct CursorEventRow: View {
    let event: CursorCostEvent

    var body: some View {
        HStack(spacing: 10) {
            Text(event.occurredAt.formatted(date: .omitted, time: .shortened))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 54, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.model).font(.callout).lineLimit(1)
                if let tokenCount = event.tokenCount {
                    Text("\(UsageFormatting.tokens(tokenCount)) tokens" + (event.kind.map { " · \($0)" } ?? ""))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            Text(UsageFormatting.usd(event.costUSD, minimumDigits: 2, maximumDigits: 4))
                .font(.callout.weight(.semibold))
                .monospacedDigit()
        }
        .padding(.vertical, 7)
    }
}

struct StatusPill<Value: Codable & Hashable & Sendable>: View {
    let value: UsageValue<Value>

    private var isOldCache: Bool { value.isStale && (value.age() ?? 0) >= 3 * 60 * 60 }
    private var tint: Color {
        value.status == .ready ? .secondary : isOldCache ? .red : value.isStale ? .orange : .red
    }
    private var icon: String {
        value.status == .ready
            ? "checkmark.circle.fill"
            : value.isStale ? "clock.badge.exclamationmark.fill" : "exclamationmark.circle.fill"
    }

    private var label: String {
        value.source == .preview ? "Demo" : (isOldCache ? "Old cache" : UsageFormatting.status(value.status))
    }

    var body: some View {
        Label(label, systemImage: icon)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .help("\(UsageFormatting.source(value.source)) · updated \(UsageFormatting.relativeAge(value.measuredAt))")
    }
}

struct SectionMessage: View {
    let message: String?
    let status: UsageDataStatus

    var body: some View {
        if let message, status != .ready || !message.isEmpty {
            Label(message, systemImage: status == .ready ? "info.circle" : "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundStyle(status == .ready ? Color.secondary : Color.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct EmptyState: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "questionmark.circle")
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 8)
    }
}

struct QuotaLabel: View {
    let systemImage: String
    let tint: Color
    let value: UsageValue<CompactQuota>

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: value.status == .ready ? systemImage : "exclamationmark.circle.fill")
                .foregroundStyle(value.status == .ready ? tint : .orange)
            VStack(alignment: .leading, spacing: 1) {
                Text(value.value?.label ?? "Quota").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                Text(value.value?.detail ?? UsageFormatting.status(value.status))
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .help([value.value.flatMap { UsageFormatting.reset($0.resetAt) }, value.message].compactMap { $0 }.joined(separator: " · "))
    }
}
