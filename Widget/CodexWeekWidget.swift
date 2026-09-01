import SwiftUI
import WidgetKit

struct CodexWeekEntry: TimelineEntry {
    let date: Date
    let snapshot: UsageSnapshot
}

struct CodexWeekProvider: TimelineProvider {
    func placeholder(in context: Context) -> CodexWeekEntry {
        CodexWeekEntry(date: .now, snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (CodexWeekEntry) -> Void) {
        completion(CodexWeekEntry(date: .now, snapshot: context.isPreview ? .preview : .load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CodexWeekEntry>) -> Void) {
        let entry = CodexWeekEntry(date: .now, snapshot: .load())
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(5 * 60))))
    }
}

@main
struct CodexWeekWidget: Widget {
    let kind = "CodexWeekWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CodexWeekProvider()) { entry in
            CodexWeekWidgetView(entry: entry)
        }
        .configurationDisplayName("AI Token Quota")
        .description("Codex, Cursor and DeepSeek usage at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
        .contentMarginsDisabled()
    }
}
