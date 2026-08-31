import SwiftUI
import WidgetKit

struct CodexWeekWidgetView: View {
    let entry: CodexWeekEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        QuotaWidgetContent(snapshot: entry.snapshot, family: family)
            .containerBackground(for: .widget) {
                QuotaWidgetBackground()
            }
    }
}
