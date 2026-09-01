import SwiftUI

enum DeepSeekPanelDensity {
    case strip
    case regular
    case expanded
}

struct DeepSeekUsagePanel: View {
    let data: UsageValue<DeepSeekUsageTotals>
    let density: DeepSeekPanelDensity
    var showsModels = false

    private let accent = Color(red: 0.22, green: 0.58, blue: 1.00)
    private var usage: DeepSeekUsageTotals? { data.value }
    private var primaryBalance: DeepSeekMoney? {
        UsageFormatting.firstValidMoney(usage?.balances ?? [])
    }
    private var cornerRadius: CGFloat { density == .strip ? 13 : 18 }

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
        Group {
            if density == .strip {
                stripBody
            } else {
                standardBody
            }
        }
        .padding(density == .strip ? 6 : density == .expanded ? 16 : 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [accent.opacity(0.20), Color(red: 0.07, green: 0.16, blue: 0.38).opacity(0.72)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(accent.opacity(0.22), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var stripBody: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Image(systemName: "waveform.path.ecg.rectangle")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(accent)
                Text("DEEPSEEK")
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .tracking(0.6)
                    .foregroundStyle(.white.opacity(0.86))
                Spacer(minLength: 3)
                Text(UsageFormatting.money(primaryBalance))
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
            }
            HStack(spacing: 4) {
                Image(systemName: statusIcon)
                Text(data.status == .ready ? compactSummary : statusText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
                Spacer(minLength: 0)
            }
            .font(.system(size: 7, weight: .semibold, design: .rounded))
            .foregroundStyle(data.status == .ready ? .white.opacity(0.62) : accent)
        }
    }

    private var standardBody: some View {
        VStack(alignment: .leading, spacing: density == .expanded ? 9 : 5) {
            header
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(UsageFormatting.money(primaryBalance))
                    .font(.system(size: density == .expanded ? 40 : 25, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
                Text("balance")
                    .font(.system(size: density == .expanded ? 13 : 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.52))
                Spacer(minLength: 0)
            }

            HStack(spacing: density == .expanded ? 18 : 10) {
                metric("MONTH COST", UsageFormatting.moneyList(usage?.monthCosts ?? []))
                metric("TOKENS", UsageFormatting.tokens(usage?.monthTokens))
                metric("REQUESTS", usage?.monthRequests?.formatted() ?? "—")
            }

            if density == .expanded {
                additionalBalances
                if showsModels, let models = usage?.models, !models.isEmpty {
                    modelSummary(models)
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "waveform.path.ecg.rectangle")
                .font(.system(size: density == .expanded ? 13 : 10, weight: .bold))
                .foregroundStyle(accent)
            Text("DEEPSEEK")
                .font(.system(size: density == .expanded ? 12 : 9, weight: .bold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(.white.opacity(0.88))
            Spacer(minLength: 4)
            Label(statusText, systemImage: statusIcon)
                .font(.system(size: density == .expanded ? 10 : 8, weight: .semibold, design: .rounded))
                .foregroundStyle(data.status == .ready ? .white.opacity(0.62) : accent)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: density == .expanded ? 9 : 7, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.45))
            Text(value)
                .font(.system(size: density == .expanded ? 13 : 10, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.82))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var additionalBalances: some View {
        let additional = Array((usage?.balances ?? []).dropFirst())
        if !additional.isEmpty {
            Text("Other balances · \(UsageFormatting.moneyList(additional))")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.56))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private func modelSummary(_ models: [DeepSeekModelUsage]) -> some View {
        HStack(spacing: 8) {
            ForEach(Array(models.prefix(3))) { model in
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.model)
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                    Text("\(UsageFormatting.tokens(model.tokens)) · \(UsageFormatting.moneyList(model.costs))")
                        .font(.system(size: 8, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.54))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .foregroundStyle(.white.opacity(0.82))
    }

    private var compactSummary: String {
        "Month \(UsageFormatting.moneyList(usage?.monthCosts ?? [])) · \(UsageFormatting.tokens(usage?.monthTokens)) tok"
    }

    private var accessibilityText: String {
        let value = UsageFormatting.money(primaryBalance)
        return "DeepSeek, \(value) balance, \(compactSummary), \(statusText)"
    }
}
