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
            VStack(spacing: 8) {
                panel(.codex, density: .compact)
                panel(.cursor, density: .compact)
            }
        case .systemMedium:
            HStack(spacing: 10) {
                panel(.codex, density: .regular)
                panel(.cursor, density: .regular)
            }
        default:
            VStack(spacing: 12) {
                panel(.codex, density: .expanded)
                panel(.cursor, density: .expanded)
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
