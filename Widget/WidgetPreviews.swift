import SwiftUI
import WidgetKit

#Preview("Small", as: .systemSmall) {
    BeaverMeterWidget()
} timeline: {
    BeaverMeterEntry(date: UsageSnapshot.previewDate, snapshot: .preview)
}

#Preview("Medium", as: .systemMedium) {
    BeaverMeterWidget()
} timeline: {
    BeaverMeterEntry(date: UsageSnapshot.previewDate, snapshot: .preview)
}

#Preview("Large", as: .systemLarge) {
    BeaverMeterWidget()
} timeline: {
    BeaverMeterEntry(date: UsageSnapshot.previewDate, snapshot: .preview)
}

#Preview("Extra Large", as: .systemExtraLarge) {
    BeaverMeterWidget()
} timeline: {
    BeaverMeterEntry(date: UsageSnapshot.previewDate, snapshot: .preview)
}

#Preview("Stale", as: .systemLarge) {
    BeaverMeterWidget()
} timeline: {
    BeaverMeterEntry(date: UsageSnapshot.previewDate, snapshot: .widgetStalePreview)
}

#Preview("Unavailable", as: .systemLarge) {
    BeaverMeterWidget()
} timeline: {
    BeaverMeterEntry(date: UsageSnapshot.previewDate, snapshot: UsagePreviewScenario.unavailable.snapshot)
}

#Preview("No reset", as: .systemLarge) {
    BeaverMeterWidget()
} timeline: {
    BeaverMeterEntry(date: UsageSnapshot.previewDate, snapshot: .widgetNoResetPreview)
}

#Preview("DeepSeek signed out", as: .systemMedium) {
    BeaverMeterWidget()
} timeline: {
    BeaverMeterEntry(date: UsageSnapshot.previewDate, snapshot: .widgetDeepSeekSignedOutPreview)
}

#Preview("DeepSeek error", as: .systemLarge) {
    BeaverMeterWidget()
} timeline: {
    BeaverMeterEntry(date: UsageSnapshot.previewDate, snapshot: .widgetDeepSeekErrorPreview)
}

#Preview("DeepSeek long balance", as: .systemSmall) {
    BeaverMeterWidget()
} timeline: {
    BeaverMeterEntry(date: UsageSnapshot.previewDate, snapshot: .widgetDeepSeekLongValuePreview)
}
