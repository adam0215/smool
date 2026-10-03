import SwiftUI

@MainActor
private final class RenderApplet: Applet {
    let id: AppletID
    let title: String
    let icon: AppletIcon
    let tint = Color.teal
    let contentHeight: CGFloat = 120

    init(_ index: Int) {
        id = AppletID(rawValue: "render-\(index)")
        title = "Applet \(index)"
        icon = .symbol(["folder", "note.text", "waveform"][index % 3])
    }

    func makeView(context: AppletContext, artwork: NSImage?) -> AnyView { AnyView(Text(title)) }
}

@main
struct HostRenderingChecks {
    @MainActor static func main() throws {
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let date = ISO8601DateFormatter().date(from: "2026-10-03T20:46:00+02:00")!
        let suite = "smool.host-rendering.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let applets: [any Applet] = [HomeApplet()] + (1...10).map(RenderApplet.init)
        let ids = applets.map(\.id)

        for width in [400.0, 1512.0] {
            for count in 0...3 {
                let settings = AppSettings(defaults: defaults)
                for id in settings.frontIDs(in: ids) { settings.setFront(false, for: id, in: ids) }
                for id in ids.dropFirst().prefix(count) { settings.setFront(true, for: id, in: ids) }
                let presentation = NotchPresentation(registry: AppletRegistry(applets), settings: settings)
                let layout = NotchLayout(screenFrame: CGRect(x: 0, y: 0, width: width, height: 982),
                                         notch: .physical(ScreenNotch.referenceSize))
                presentation.layout = layout
                do {
                    let view = VStack(spacing: 8) {
                        NotchTabBar(presentation: presentation, select: { _ in })
                        NotchHomeView(layout: layout, date: date, applets: presentation.frontApplets)
                    }
                    .frame(width: layout.expandedSize.width, height: layout.expandedSize.height)
                    .background(.black)
                    .clipShape(NotchShape(shoulderRadius: 0, bottomRadius: 64))
                    .environment(\.colorScheme, .dark)
                    let renderer = ImageRenderer(content: view)
                    renderer.scale = 2
                    guard let image = renderer.cgImage else { fatalError("Could not render home") }
                    let bitmap = NSBitmapImageRep(cgImage: image)
                    precondition(bitmap.pixelsWide == Int(layout.expandedSize.width * 2))
                    let center = layout.headerRegions(in: layout.expandedSize.width).center
                    for x in Int(center.minX * 2)..<Int(center.maxX * 2) {
                        for y in 0..<Int(center.height * 2) {
                            let pixel = bitmap.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
                            precondition(max(pixel.redComponent, pixel.greenComponent, pixel.blueComponent) < 0.03)
                        }
                    }
                    try bitmap.representation(using: .png, properties: [:])!
                        .write(to: output.appendingPathComponent("host-\(Int(width))-\(count).png"))
                }
            }
        }
        print("Passed: 0–3 front applets, 11-app header, compact/full width and camera exclusion.")
    }
}
