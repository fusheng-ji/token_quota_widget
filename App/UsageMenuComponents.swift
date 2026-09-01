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

struct DeepSeekMetric: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.blue.opacity(0.07), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

struct DeepSeekDetailLine: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .fontWeight(.semibold)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .font(.caption)
    }
}

struct DeepSeekModelRow: View {
    let model: DeepSeekModelUsage

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.model).font(.callout).lineLimit(1)
                Text("\(UsageFormatting.tokens(model.tokens)) tokens · \(model.requests) requests")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(UsageFormatting.moneyList(model.costs))
                .font(.callout.weight(.semibold))
                .monospacedDigit()
        }
        .padding(.vertical, 6)
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
