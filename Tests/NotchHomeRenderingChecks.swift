import SwiftUI

@main
struct NotchHomeRenderingChecks {
    @MainActor
    static func main() throws {
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let date = ISO8601DateFormatter().date(from: "2026-10-02T20:46:00+02:00")!

        for (name, expectedSize) in [("Spotify", 32.0), ("Codex", 24.0)] {
            guard let image = NSImage(named: name) else { fatalError("Missing bundled logo: \(name)") }
            precondition(image.size == CGSize(width: expectedSize, height: expectedSize))
        }

        for (name, width, notch) in [
            ("home", 1512.0, ScreenNotch.none),
            ("physical", 1512.0, .physical(ScreenNotch.referenceSize)),
            ("wide-notch", 1512.0, .physical(CGSize(width: 432, height: 38))),
            ("compact", 400.0, .none)
        ] {
            let layout = NotchLayout(screenFrame: CGRect(x: 0, y: 0, width: width, height: 982), notch: notch)
            let view = GlassEffectContainer(spacing: 0) {
                VStack(spacing: 8) {
                    NotchTabBar(layout: layout, selection: .home, select: { _ in })
                    NotchHomeView(layout: layout, date: date, openTab: { _ in })
                }
            }
            .frame(width: layout.expandedSize.width, height: layout.expandedSize.height)
            .background(.black)
            .clipShape(NotchShape(shoulderRadius: 0, bottomRadius: 64))
            .environment(\.colorScheme, .dark)

            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            guard let image = renderer.cgImage else { fatalError("Could not render \(name)") }
            let bitmap = NSBitmapImageRep(cgImage: image)
            precondition(bitmap.pixelsWide == Int(layout.expandedSize.width * 2))
            precondition(bitmap.pixelsHigh == Int(layout.expandedSize.height * 2))

            let sideWidth = layout.headerRegions(in: layout.expandedSize.width - 8).leading.width
            let tabInset = min(12, max(0, (sideWidth - 80) / 2))
            precondition(sideWidth - tabInset * 2 >= 80, "All three header tabs must fit beside the camera.")

            // Header content and decorative light must leave the camera area black.
            let center = layout.headerRegions(in: layout.expandedSize.width).center
            for x in Int(center.minX * 2)..<Int(center.maxX * 2) {
                for y in 0..<Int(center.height * 2) {
                    let pixel = bitmap.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
                    precondition(max(pixel.redComponent, pixel.greenComponent, pixel.blueComponent) < 0.03)
                }
            }

            try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("\(name).png"))

            var appletLayout = layout
            appletLayout.contentHeight = 300
            let stack = VStack(spacing: 8) {
                NotchTabBar(layout: appletLayout, selection: .spotify, select: { _ in })
                PageStack(pages: ["Spelare", "Spellistor", "Kö"], selection: .constant("Spellistor"), title: { $0 }) { _ in
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Release Radar").font(.headline)
                        Text("Ny musik för dig").foregroundStyle(.secondary)
                        Button("Spela") {}
                    }
                }
            }
            .frame(width: appletLayout.expandedSize.width, height: appletLayout.expandedSize.height)
            .background(.black)
            .clipShape(NotchShape(shoulderRadius: 0, bottomRadius: 64))
            .environment(\.colorScheme, .dark)
            let stackRenderer = ImageRenderer(content: stack)
            stackRenderer.scale = 2
            guard let stackImage = stackRenderer.cgImage else { fatalError("Could not render the page stack") }
            let stackBitmap = NSBitmapImageRep(cgImage: stackImage)
            precondition(stackBitmap.pixelsWide == Int(appletLayout.expandedSize.width * 2))
            precondition(stackBitmap.pixelsHigh == Int(appletLayout.expandedSize.height * 2))
            for x in Int(center.minX * 2)..<Int(center.maxX * 2) {
                for y in 0..<Int(center.height * 2) {
                    let pixel = stackBitmap.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
                    precondition(max(pixel.redComponent, pixel.greenComponent, pixel.blueComponent) < 0.03)
                }
            }
            try stackBitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("stack-\(name).png"))
        }

        print("Passed: bundled logo dimensions, home rendering, compact displays, and camera exclusion.")
    }
}
