import SwiftUI

enum QuotaProviderKind {
    case codex
    case cursor

    var name: String {
        switch self {
        case .codex: "CODEX"
        case .cursor: "CURSOR"
        }
    }

    var icon: String {
        switch self {
        case .codex: "sparkles"
        case .cursor: "cursorarrow"
        }
    }

    var accent: Color {
        switch self {
        case .codex: Color(red: 0.20, green: 0.88, blue: 0.75)
        case .cursor: Color(red: 0.48, green: 0.42, blue: 1.00)
        }
    }

}

enum QuotaPanelDensity {
    case strip
    case compact
    case regular
    case expanded

    var padding: CGFloat {
        switch self {
        case .strip: 6
        case .compact: 6
        case .regular: 12
        case .expanded: 16
        }
    }

    var spacing: CGFloat {
        switch self {
        case .strip: 2
        case .compact: 2
        case .regular: 6
        case .expanded: 8
        }
    }

    var valueSize: CGFloat {
        switch self {
        case .strip: 17
        case .compact: 20
        case .regular: 30
        case .expanded: 42
        }
    }
}

struct QuotaProviderPanel: View {
    let provider: QuotaProviderKind
    let data: UsageValue<CompactQuota>
    let density: QuotaPanelDensity
    var dailyTokens: UsageValue<CodexTokenTotals>?
    var referenceDate: Date = .now

    private var quota: CompactQuota? { data.value }
    private var cornerRadius: CGFloat { density == .strip || density == .compact ? 13 : 18 }
    private var remainingPercent: Double? {
        UsageFormatting.clampedPercent(quota?.remainingPercent)
    }

    private var progressColor: Color {
        guard let remainingPercent else { return provider.accent }
        if remainingPercent < 20 { return Color(red: 1.00, green: 0.31, blue: 0.31) }
        if remainingPercent < 50 { return Color(red: 1.00, green: 0.68, blue: 0.20) }
        return provider.accent
    }

    private var valueText: String {
        switch provider {
        case .codex:
            guard let remainingPercent else { return "—" }
            return "\(Int(remainingPercent.rounded()))%"
        case .cursor:
            return UsageFormatting.usd(quota?.remaining, minimumDigits: 2, maximumDigits: 2)
        }
    }

    private var detailText: String {
        guard let quota else { return data.message ?? UsageFormatting.status(data.status) }
        switch provider {
        case .codex:
            return quotaPeriod(windowSeconds: quota.windowSeconds)
        case .cursor:
            if let used = quota.used, let limit = quota.limit {
                return "\(UsageFormatting.usdCode(used)) / \(UsageFormatting.usdCode(limit))"
            }
            return quota.detail.isEmpty ? "Monthly quota" : quota.detail
        }
    }

    private var status: UsageStatusPresentation { UsageStatusPresentation(data, relativeTo: referenceDate) }

    var body: some View {
        Group {
            if density == .strip {
                stripBody
            } else {
                standardBody
            }
        }
        .padding(density.padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(panelBackground)
        }
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(provider.name), \(valueText) remaining, \(detailText), " +
                "\(UsageFormatting.resetCountdown(quota?.resetAt, relativeTo: referenceDate)), \(status.detail)" +
                (dailyTokens.map { ", " + CodexDailyTokenPresentation($0, relativeTo: referenceDate).accessibilityText } ?? "")
        )
        .help(status.detail)
    }

    private var stripBody: some View {
        VStack(alignment: .leading, spacing: density.spacing) {
            HStack(spacing: 5) {
                Image(systemName: provider.icon)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(provider.accent)
                Text(provider.name)
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .tracking(0.6)
                    .foregroundStyle(.white.opacity(0.86))
                Spacer(minLength: 3)
                Text(valueText)
                    .font(.system(size: density.valueSize, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }
            HStack(spacing: 4) {
                Image(systemName: status.icon)
                Text(status.severity == .normal ? detailText : status.label)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                Spacer(minLength: 2)
                QuotaProgressBar(percent: remainingPercent, tint: progressColor)
                    .frame(width: 42, height: 3)
            }
            .font(.system(size: 7, weight: .semibold, design: .rounded))
            .foregroundStyle(status.widgetColor)
            dailyTokenLine
        }
    }

    private var standardBody: some View {
        VStack(alignment: .leading, spacing: density.spacing) {
            header
            value

            if density != .compact {
                Text(detailText)
                    .font(.system(size: density == .expanded ? 12 : 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(1)
            }

            if density == .compact {
                HStack(spacing: 4) {
                    resetLine
                    Spacer(minLength: 0)
                    QuotaProgressBar(percent: remainingPercent, tint: progressColor)
                        .frame(width: 30, height: 3)
                }
            } else {
                resetLine
                QuotaProgressBar(percent: remainingPercent, tint: progressColor)
                    .frame(height: density == .expanded ? 6 : 4)
            }
            dailyTokenLine
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: provider.icon)
                .font(.system(size: density == .expanded ? 13 : 10, weight: .bold))
                .foregroundStyle(provider.accent)
            Text(provider.name)
                .font(.system(size: density == .expanded ? 12 : 9, weight: .bold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(.white.opacity(0.88))
            Spacer(minLength: 4)
            Label(status.label, systemImage: status.icon)
                .font(.system(size: density == .expanded ? 10 : 8, weight: .semibold, design: .rounded))
                .foregroundStyle(status.widgetColor)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }

    private var value: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(valueText)
                .font(.system(size: density.valueSize, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if density != .regular {
                Text("remaining")
                    .font(.system(size: density == .expanded ? 13 : 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.52))
            }
            Spacer(minLength: 0)
        }
    }

    private var resetLine: some View {
        HStack(spacing: 5) {
            Image(systemName: "clock")
                .foregroundStyle(provider.accent.opacity(0.88))
            Text(UsageFormatting.resetCountdown(quota?.resetAt, relativeTo: referenceDate))
                .lineLimit(1)
        }
        .font(.system(size: density == .expanded ? 11 : 8, weight: .semibold, design: .rounded))
        .foregroundStyle(.white.opacity(0.70))
    }

    @ViewBuilder
    private var dailyTokenLine: some View {
        if let dailyTokens {
            let presentation = CodexDailyTokenPresentation(dailyTokens, relativeTo: referenceDate)
            HStack(spacing: 3) {
                Text("Today")
                Text("\(presentation.value) tok").fontWeight(.semibold).monospacedDigit()
                Spacer(minLength: 0)
                if presentation.status.severity != .normal {
                    Image(systemName: presentation.status.icon)
                        .foregroundStyle(presentation.status.widgetColor)
                    Text(presentation.warningLabel).foregroundStyle(presentation.status.widgetColor)
                }
            }
            .font(.system(size: density == .strip ? 8 : density == .expanded ? 11 : 9, weight: .medium))
            .foregroundStyle(.white.opacity(0.78))
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .help(presentation.status.detail)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(presentation.accessibilityText)
        }
    }

    private var panelBackground: some ShapeStyle {
        provider.accent.opacity(0.08)
    }

    private func quotaPeriod(windowSeconds: Int?) -> String {
        guard let windowSeconds else { return quota?.label ?? "Quota window" }
        switch windowSeconds {
        case 604_800: return "Weekly quota"
        case 18_000: return "5-hour quota"
        default:
            if windowSeconds.isMultiple(of: 86_400) {
                return "\(windowSeconds / 86_400)-day quota"
            }
            return quota?.label ?? "Quota window"
        }
    }
}

struct QuotaProgressBar: View {
    let percent: Double?
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.10))
                if let percent {
                    Capsule()
                        .fill(tint)
                        .frame(width: fillWidth(total: proxy.size.width, percent: percent))
                } else {
                    Capsule()
                        .fill(.white.opacity(0.16))
                        .frame(width: proxy.size.width * 0.24)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func fillWidth(total: CGFloat, percent: Double) -> CGFloat {
        guard percent > 0 else { return 0 }
        return min(total, max(4, total * percent / 100))
    }
}

extension UsageStatusPresentation {
    var widgetColor: Color {
        switch severity {
        case .normal: .white.opacity(0.68)
        case .warning: Color(red: 1.00, green: 0.74, blue: 0.32)
        case .critical: Color(red: 1.00, green: 0.44, blue: 0.42)
        }
    }
}
