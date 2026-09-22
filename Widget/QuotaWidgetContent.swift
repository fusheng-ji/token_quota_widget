import SwiftUI
import WidgetKit

struct QuotaWidgetContent: View {
    let snapshot: UsageSnapshot
    let family: WidgetFamily
    var referenceDate: Date = .now

    var body: some View {
        layout
            .padding(outerPadding)
    }

    @ViewBuilder
    private var layout: some View {
        switch family {
        case .systemSmall:
            VStack(spacing: 5) {
                panel(.codex, density: .strip)
                    .frame(height: 56)
                panel(.cursor, density: .strip)
                deepSeekPanel(density: .strip)
            }
        case .systemMedium:
            VStack(spacing: 7) {
                HStack(spacing: 7) {
                    panel(.codex, density: .compact)
                    panel(.cursor, density: .compact)
                }
                deepSeekPanel(density: .regular)
            }
        case .systemLarge:
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    panel(.codex, density: .regular)
                    panel(.cursor, density: .regular)
                }
                deepSeekPanel(density: .expanded)
            }
        default:
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    panel(.codex, density: .expanded)
                    panel(.cursor, density: .expanded)
                }
                deepSeekPanel(density: .expanded)
            }
        }
    }

    private var outerPadding: CGFloat {
        switch family {
        case .systemSmall: 8
        case .systemMedium: 10
        default: 14
        }
    }

    private func panel(_ provider: QuotaProviderKind, density: QuotaPanelDensity) -> some View {
        QuotaProviderPanel(
            provider: provider,
            data: provider == .codex ? snapshot.codexQuota : snapshot.cursorQuota,
            density: density,
            dailyTokens: provider == .codex ? snapshot.codexTokens : nil,
            referenceDate: referenceDate
        )
    }

    private func deepSeekPanel(density: DeepSeekPanelDensity) -> some View {
        DeepSeekUsagePanel(
            data: snapshot.deepseekUsage,
            density: density,
            referenceDate: referenceDate
        )
    }
}

struct QuotaWidgetBackground: View {
    var body: some View {
        Color(red: 0.065, green: 0.07, blue: 0.085)
    }
}
