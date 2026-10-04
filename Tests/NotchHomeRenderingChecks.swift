@testable import SmoolChecksSupport
import SwiftUI
import ScreenCaptureKit

@main
struct NotchHomeRenderingChecks {
    @MainActor
    static func main() async throws {
        _ = NSApplication.shared
        NSApp.appearance = NSAppearance(named: .darkAqua)
        let suite = "smool.home-rendering.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
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
            let presentation = NotchPresentation(settings: settings)
            presentation.layout = layout
            let view = VStack(spacing: 8) {
                NotchTabBar(presentation: presentation, select: { _ in })
                NotchHomeView(layout: layout, date: date, applets: presentation.frontApplets)
            }
            .frame(width: layout.expandedSize.width, height: layout.expandedSize.height)
            .background(.black)
            .clipShape(NotchShape(shoulderRadius: 0, bottomRadius: 64))
            .environment(\.colorScheme, .dark)

            let bitmap = try await capture(view, size: layout.expandedSize)
            let scale = CGFloat(bitmap.pixelsWide) / layout.expandedSize.width

            // Header content and decorative light must leave the camera area black.
            let center = layout.headerRegions(in: layout.expandedSize.width).center
            for x in Int(center.minX * scale)..<Int(center.maxX * scale) {
                for y in 0..<Int((notch.obscuresCenter ? center.height : 0) * scale) {
                    let pixel = bitmap.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
                    precondition(max(pixel.redComponent, pixel.greenComponent, pixel.blueComponent) < 0.03)
                }
            }

            try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("\(name).png"))

            var appletLayout = layout
            appletLayout.contentHeight = 300
            let appletPresentation = NotchPresentation(settings: settings)
            appletPresentation.layout = appletLayout
            appletPresentation.select(AppletID(rawValue: "spotify"))
            let pages = VStack(spacing: 8) {
                NotchTabBar(presentation: appletPresentation, select: { _ in })
                AppletPages(pages: ["Player", "Playlists", "Queue"], selection: .constant("Playlists"), title: { $0 }) { _ in
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Release Radar").font(.headline)
                        Text("New music for you").foregroundStyle(.secondary)
                        Button("Play") {}
                    }
                }
            }
            .frame(width: appletLayout.expandedSize.width, height: appletLayout.expandedSize.height)
            .background(.black)
            .clipShape(NotchShape(shoulderRadius: 0, bottomRadius: 64))
            .environment(\.colorScheme, .dark)
            let pagesBitmap = try await capture(pages, size: appletLayout.expandedSize)
            let pagesScale = CGFloat(pagesBitmap.pixelsWide) / appletLayout.expandedSize.width
            for x in Int(center.minX * pagesScale)..<Int(center.maxX * pagesScale) {
                for y in 0..<Int((notch.obscuresCenter ? center.height : 0) * pagesScale) {
                    let pixel = pagesBitmap.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
                    precondition(max(pixel.redComponent, pixel.greenComponent, pixel.blueComponent) < 0.03)
                }
            }
            try pagesBitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("pages-\(name).png"))
        }

        print("Passed: bundled logo dimensions, home rendering, compact displays, and camera exclusion.")
    }

    @MainActor private static func capture(_ content: some View, size: CGSize) async throws -> NSBitmapImageRep {
        let host = NSHostingView(rootView: content)
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFrontRegardless()
        defer { window.close() }
        // Home enters with a one-second glow animation after a 0.1-second delay.
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(1_300))
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        // View caching omits GPU-composited glass content. Capture only this
        // process's window; currentProcess does not request screen-recording access.
        let shareable = try await SCShareableContent.currentProcess
        guard let capturedWindow = shareable.windows.first(where: { $0.windowID == CGWindowID(window.windowNumber) }) else {
            fatalError("The render window is unavailable for capture")
        }
        let filter = SCContentFilter(desktopIndependentWindow: capturedWindow)
        let configuration = SCStreamConfiguration()
        let scale = CGFloat(filter.pointPixelScale)
        configuration.width = Int((size.width * scale).rounded())
        configuration.height = Int((size.height * scale).rounded())
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = true
        configuration.colorSpaceName = CGColorSpace.sRGB
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        let bitmap = NSBitmapImageRep(cgImage: image)
        precondition(bitmap.pixelsWide == configuration.width)
        precondition(bitmap.pixelsHigh == configuration.height)
        return bitmap
    }
}
