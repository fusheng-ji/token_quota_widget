import SwiftUI
import WidgetKit

struct QuotaWidgetContent: View {
    let snapshot: UsageSnapshot
    let family: WidgetFamily

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
                deepSeekPanel(density: .expanded, showsModels: true)
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
            density: density
        )
    }

    private func deepSeekPanel(
        density: DeepSeekPanelDensity,
        showsModels: Bool = false
    ) -> some View {
        DeepSeekUsagePanel(
            data: snapshot.deepseekUsage,
            density: density,
            showsModels: showsModels
        )
    }
}

struct QuotaWidgetBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(red: 0.035, green: 0.04, blue: 0.07),
                Color(red: 0.08, green: 0.07, blue: 0.13)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
