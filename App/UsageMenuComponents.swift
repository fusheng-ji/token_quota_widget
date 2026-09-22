import SwiftUI

struct UsageSectionHeader<Value: Codable & Hashable & Sendable>: View {
    let title: String
    let systemImage: String
    let tint: Color
    let value: UsageValue<Value>
    let referenceDate: Date

    var body: some View {
        HStack {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            StatusPill(value: value, referenceDate: referenceDate)
        }
    }
}

struct TokenMetric: View {
    let label: String
    let value: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(UsageFormatting.tokens(value)).font(.caption.weight(.semibold)).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), \(value.formatted()) tokens")
    }
}

struct CursorEventRow: View {
    let event: CursorCostEvent
    @Environment(\.locale) private var locale
    @Environment(\.timeZone) private var timeZone

    var body: some View {
        HStack(spacing: 10) {
            Text(event.occurredAt.formatted(Date.FormatStyle(date: .omitted, time: .shortened,
                                                           locale: locale, timeZone: timeZone)))
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
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

struct DeepSeekMetric: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .accessibilityElement(children: .combine)
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

struct StatusPill<Value: Codable & Hashable & Sendable>: View {
    let value: UsageValue<Value>
    var referenceDate: Date = .now

    private var presentation: UsageStatusPresentation { UsageStatusPresentation(value, relativeTo: referenceDate) }
    private var tint: Color {
        switch presentation.severity {
        case .normal: .secondary
        case .warning: .orange
        case .critical: .red
        }
    }

    var body: some View {
        Label(presentation.label, systemImage: presentation.icon)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .help(presentation.detail)
            .accessibilityLabel(presentation.detail)
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
    var referenceDate: Date = .now

    private var presentation: UsageStatusPresentation { UsageStatusPresentation(value, relativeTo: referenceDate) }

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: presentation.severity == .normal ? systemImage : presentation.icon)
                .foregroundStyle(presentation.severity == .normal ? tint : presentation.severity == .critical ? .red : .orange)
            VStack(alignment: .leading, spacing: 1) {
                Text(value.value?.label ?? "Quota").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                Text(value.value?.detail ?? UsageFormatting.status(value.status))
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .help([value.value.flatMap { UsageFormatting.reset($0.resetAt) }, presentation.detail].compactMap { $0 }.joined(separator: " · "))
        .accessibilityElement(children: .combine)
    }
}
