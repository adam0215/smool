import SwiftUI

@main
struct NotchHeaderRenderingChecks {
    @MainActor
    static func main() throws {
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)

        for (name, notch, hasSideContent) in [
            ("no-notch", ScreenNotch.none, false),
            ("no-notch-with-sides", .none, true),
            ("physical", .physical(ScreenNotch.referenceSize), true),
            ("simulated", .simulated(ScreenNotch.referenceSize), true)
        ] {
            let layout = NotchLayout(screenFrame: screen, notch: notch)
            let view = NotchHeader(layout: layout) {
                // Deliberately oversized content must not cover the reserved center.
                if hasSideContent {
                    Color.red.frame(width: 600, height: 32)
                }
            } center: {
                Text("smool").font(.system(size: 13, weight: .medium, design: .rounded))
            } trailing: {
                if hasSideContent {
                    Color.blue.frame(width: 16, height: 16)
                }
            }
            .frame(width: 440)
            .foregroundStyle(.white)
            .background(.black)

            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            guard let image = renderer.cgImage else { fatalError("Could not render \(name)") }
            let bitmap = NSBitmapImageRep(cgImage: image)
            let center = layout.headerRegions(in: 440).center
            var textPixels = 0
            var firstTextX = bitmap.pixelsWide
            var lastTextX = 0

            for x in Int(center.minX * 2 + 1)..<Int(center.maxX * 2 - 1) {
                for y in 0..<bitmap.pixelsHigh {
                    guard let pixel = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else {
                        fatalError("Could not read a rendered pixel")
                    }
                    precondition(abs(pixel.redComponent - pixel.blueComponent) < 0.02, "Side content leaked into the notch region.")
                    if pixel.redComponent > 0.1 {
                        textPixels += 1
                        firstTextX = min(firstTextX, x)
                        lastTextX = max(lastTextX, x)
                    }
                }
            }

            if notch.obscuresCenter {
                precondition(textPixels == 0, "Center content must be absent behind a notch.")
            } else {
                precondition(textPixels > 0, "The notch-free header must show smool.")
                precondition(abs(CGFloat(firstTextX + lastTextX) / 2 - 440) < 4, "Unequal side content moved the center label.")
            }

            try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("header-\(name).png"))
        }

        print("Passed: rendered center label, notch exclusion, and oversized side-content clipping.")
    }
}
