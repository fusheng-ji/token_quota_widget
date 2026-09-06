import SwiftUI
import WidgetKit

struct BeaverMeterWidgetView: View {
    let entry: BeaverMeterEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        QuotaWidgetContent(snapshot: entry.snapshot, family: family)
            .containerBackground(for: .widget) {
                QuotaWidgetBackground()
            }
    }
}
