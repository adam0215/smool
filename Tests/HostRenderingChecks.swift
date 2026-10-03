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
                if width > 600 {
                    let side = layout.headerRegions(in: layout.expandedSize.width).leading.width
                    let fourTabsAndOverflow: CGFloat = 4 * 28 + 3 * 4 + 3 + 28
                    precondition(side - 2 * 16 >= fourTabsAndOverflow,
                                 "All four tab hit targets and overflow must fit beside the camera.")
                }
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
        let homeApplets = [
            AppletDestination(id: AppletID(rawValue: "spotify"), title: "Spotify", icon: .symbol("music.note"), tint: .green),
            AppletDestination(id: AppletID(rawValue: "codex"), title: "Codex", icon: .symbol("terminal"), tint: .purple)
        ]
        let cards = HomeCard.arrangement(for: homeApplets.map(\.id))
        for (index, card) in cards.enumerated() {
            let glow = card.glow(applets: homeApplets)
            let reference = HomeGlow.color(for: index == 0 ? .spotify : index == 2 ? .codex : nil)
            precondition(glow.color.resolve(in: EnvironmentValues()) == reference.resolve(in: EnvironmentValues()),
                         "Configurable Home must preserve its original palette.")
            precondition(glow.horizontalPosition == [0.25, 0.5, 0.75][index])
            let renderer = ImageRenderer(content: glow.frame(width: 600, height: 120).background(.black))
            guard let image = renderer.cgImage else { fatalError("Could not render configured Home glow") }
            try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
                .write(to: output.appendingPathComponent("configured-home-glow-\(index).png"))
        }

        let settingsPresentation = NotchPresentation(registry: AppletRegistry(applets), settings: AppSettings(defaults: defaults))
        settingsPresentation.showsSettings = true
        for section in SettingsSection.allCases {
            settingsPresentation.changeSettingsSection(section)
            var layout = NotchLayout(screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                                     notch: .physical(ScreenNotch.referenceSize))
            layout.contentHeight = settingsPresentation.contentHeight
            settingsPresentation.layout = layout
            let view = VStack(spacing: 8) {
                NotchTabBar(presentation: settingsPresentation, select: { _ in })
                SettingsView(presentation: settingsPresentation)
            }
            .frame(width: layout.expandedSize.width, height: layout.expandedSize.height)
            .background(.black)
            .clipShape(NotchShape(shoulderRadius: 0, bottomRadius: 64))
            .environment(\.colorScheme, .dark)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            guard let image = renderer.cgImage else { fatalError("Could not render settings") }
            try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
                .write(to: output.appendingPathComponent("settings-\(section.rawValue.lowercased()).png"))
        }

        print("Passed: 0–3 front applets, 11-app header, compact/full width and camera exclusion.")
    }
}
