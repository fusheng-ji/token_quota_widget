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

    var gradientEnd: Color {
        switch self {
        case .codex: Color(red: 0.05, green: 0.31, blue: 0.30)
        case .cursor: Color(red: 0.20, green: 0.16, blue: 0.46)
        }
    }
}

enum QuotaPanelDensity {
    case compact
    case regular
    case expanded

    var padding: CGFloat {
        switch self {
        case .compact: 8
        case .regular: 12
        case .expanded: 16
        }
    }

    var spacing: CGFloat {
        switch self {
        case .compact: 3
        case .regular: 6
        case .expanded: 8
        }
    }

    var valueSize: CGFloat {
        switch self {
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

    private var quota: CompactQuota? { data.value }
    private var cornerRadius: CGFloat { density == .compact ? 13 : 18 }
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

    private var statusText: String {
        if data.source == .preview { return "Demo" }
        if data.status == .stale {
            return UsageFormatting.cacheAge(data.measuredAt) ?? "Stale"
        }
        return UsageFormatting.status(data.status)
    }

    private var statusIcon: String {
        switch data.status {
        case .ready: "checkmark.circle.fill"
        case .stale: "clock.badge.exclamationmark.fill"
        case .unauthenticated: "person.crop.circle.badge.exclamationmark"
        case .unavailable: "minus.circle.fill"
        case .error: "exclamationmark.triangle.fill"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: density.spacing) {
            header
            value

            if density != .compact {
                Text(detailText)
                    .font(.system(size: density == .expanded ? 12 : 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(1)
            }

            resetLine
            QuotaProgressBar(percent: remainingPercent, tint: progressColor)
                .frame(height: density == .expanded ? 6 : 4)
        }
        .padding(density.padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(panelBackground)
        }
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(provider.accent.opacity(0.20), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(provider.name), \(valueText) remaining, \(detailText), " +
                "\(UsageFormatting.resetCountdown(quota?.resetAt)), \(statusText)"
        )
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
            Label(statusText, systemImage: statusIcon)
                .font(.system(size: density == .expanded ? 10 : 8, weight: .semibold, design: .rounded))
                .foregroundStyle(data.status == .ready ? .white.opacity(0.62) : progressColor)
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
            Text("remaining")
                .font(.system(size: density == .expanded ? 13 : 9, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.52))
            Spacer(minLength: 0)
        }
    }

    private var resetLine: some View {
        HStack(spacing: 5) {
            Image(systemName: "clock")
                .foregroundStyle(provider.accent.opacity(0.88))
            Text(UsageFormatting.resetCountdown(quota?.resetAt))
                .lineLimit(1)
            if density == .compact {
                Spacer(minLength: 3)
                Text(detailText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }
        }
        .font(.system(size: density == .expanded ? 11 : 8, weight: .semibold, design: .rounded))
        .foregroundStyle(.white.opacity(0.70))
    }

    private var panelBackground: some ShapeStyle {
        LinearGradient(
            colors: [provider.accent.opacity(0.18), provider.gradientEnd.opacity(0.54)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
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
                        .shadow(color: tint.opacity(0.35), radius: 4)
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
