import SwiftUI
import WidgetKit

struct BeaverMeterEntry: TimelineEntry {
    let date: Date
    let snapshot: UsageSnapshot
}

struct BeaverMeterProvider: TimelineProvider {
    func placeholder(in context: Context) -> BeaverMeterEntry {
        BeaverMeterEntry(date: UsageSnapshot.previewDate, snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (BeaverMeterEntry) -> Void) {
        completion(BeaverMeterEntry(date: context.isPreview ? UsageSnapshot.previewDate : .now,
                                   snapshot: context.isPreview ? .preview : .load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BeaverMeterEntry>) -> Void) {
        let entry = BeaverMeterEntry(date: .now, snapshot: .load())
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(5 * 60))))
    }
}

@main
struct BeaverMeterWidget: Widget {
    let kind = "BeaverMeterWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BeaverMeterProvider()) { entry in
            BeaverMeterWidgetView(entry: entry)
        }
        .configurationDisplayName("BeaverMeter")
        .description("Codex, Cursor and DeepSeek usage at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
        .contentMarginsDisabled()
    }
}
