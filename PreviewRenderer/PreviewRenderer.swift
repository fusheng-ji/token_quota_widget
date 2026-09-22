import AppKit
import SwiftUI
import WidgetKit

@main
struct PreviewRenderer {
    @MainActor
    static func main() throws {
        let arguments = CommandLine.arguments
        let outputDirectory = URL(fileURLWithPath: arguments.count > 1 ? arguments[1] : "screenshots", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        for scenario in UsagePreviewScenario.allCases {
            let suffix = scenario == .normal ? "" : "-\(scenario.rawValue)"
            let snapshot = scenario.snapshot
            let height: CGFloat = scenario == .longList ? 1_550 : scenario == .refreshError ? 960 : 820
            for scheme in [ColorScheme.dark, .light] {
                let menu = UsageMenuView(
                    store: UsageStore(snapshot: snapshot, observesSnapshotChanges: false),
                    automaticRefresh: false,
                    scrollsContent: false,
                    updatedDescriptionOverride: "from demo data",
                    viewHeight: height,
                    referenceDate: UsageSnapshot.previewDate,
                    refreshErrorOverride: scenario == .refreshError ? "Refresh failed; the previous data was preserved." : nil
                )
                .background(Color(nsColor: .windowBackgroundColor))
                let appearance = scheme == .dark ? "" : "-light"
                render(menu, size: CGSize(width: 410, height: height), colorScheme: scheme,
                       to: outputDirectory.appendingPathComponent("menu-popover\(suffix)\(appearance).png"))
            }
            for (family, size, name) in [
                (WidgetFamily.systemSmall, CGSize(width: 174, height: 174), "small"),
                (.systemMedium, CGSize(width: 352, height: 174), "medium"),
                (.systemLarge, CGSize(width: 352, height: 352), "large"),
                (.systemExtraLarge, CGSize(width: 710, height: 352), "extra-large")
            ] {
                let view = QuotaWidgetContent(snapshot: snapshot, family: family, referenceDate: UsageSnapshot.previewDate)
                    .background(QuotaWidgetBackground())
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                render(view, size: size, colorScheme: .dark,
                       to: outputDirectory.appendingPathComponent("widget-\(name)\(suffix).png"))
            }
        }
    }

    @MainActor
    private static func render<Content: View>(
        _ content: Content, size: CGSize, colorScheme: ColorScheme, to destination: URL
    ) {
        let priorAppearance = NSAppearance.current
        NSAppearance.current = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
        defer { NSAppearance.current = priorAppearance }
        let renderer = ImageRenderer(
            content: content
                .frame(width: size.width, height: size.height)
                .environment(\.colorScheme, colorScheme)
                .environment(\.locale, Locale(identifier: "en_US"))
                .environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)
        )
        renderer.scale = 2
        renderer.proposedSize = ProposedViewSize(size)
        guard let image = renderer.cgImage,
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            fatalError("Could not render \(destination.lastPathComponent)")
        }
        do {
            try png.write(to: destination, options: .atomic)
            print("Rendered \(destination.path)")
        } catch {
            fatalError("Could not write \(destination.path): \(error.localizedDescription)")
        }
    }
}
