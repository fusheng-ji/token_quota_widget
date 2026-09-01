import AppKit
import SwiftUI
import WidgetKit

@main
struct PreviewRenderer {
    @MainActor
    static func main() throws {
        let arguments = CommandLine.arguments
        let outputDirectory = URL(
            fileURLWithPath: arguments.count > 1 ? arguments[1] : "screenshots",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )

        let menu = UsageMenuView(
            store: UsageStore(snapshot: .preview),
            automaticRefresh: false,
            scrollsContent: false,
            updatedDescriptionOverride: "from demo data",
            viewHeight: 920
        )
        .background(Color(nsColor: .windowBackgroundColor))
        render(menu, size: CGSize(width: 410, height: 920), to: outputDirectory.appendingPathComponent("menu-popover.png"))

        renderWidget(.systemSmall, size: CGSize(width: 174, height: 174), outputDirectory: outputDirectory)
        renderWidget(.systemMedium, size: CGSize(width: 352, height: 174), outputDirectory: outputDirectory)
        renderWidget(.systemLarge, size: CGSize(width: 352, height: 352), outputDirectory: outputDirectory)
        renderWidget(.systemExtraLarge, size: CGSize(width: 710, height: 352), outputDirectory: outputDirectory)
    }

    @MainActor
    private static func renderWidget(
        _ family: WidgetFamily,
        size: CGSize,
        outputDirectory: URL
    ) {
        let fileName: String
        switch family {
        case .systemSmall: fileName = "widget-small.png"
        case .systemMedium: fileName = "widget-medium.png"
        case .systemLarge: fileName = "widget-large.png"
        default: fileName = "widget-extra-large.png"
        }

        let view = QuotaWidgetContent(snapshot: .preview, family: family)
            .background(QuotaWidgetBackground())
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        render(view, size: size, to: outputDirectory.appendingPathComponent(fileName))
    }

    @MainActor
    private static func render<Content: View>(_ content: Content, size: CGSize, to destination: URL) {
        let renderer = ImageRenderer(
            content: content
                .frame(width: size.width, height: size.height)
                .preferredColorScheme(.dark)
        )
        renderer.scale = 2
        renderer.proposedSize = ProposedViewSize(size)

        guard
            let image = renderer.cgImage,
            let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        else {
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
