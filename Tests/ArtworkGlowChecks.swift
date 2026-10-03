import SwiftUI

@main
struct ArtworkGlowChecks {
    @MainActor
    static func main() throws {
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let source = ImageRenderer(content: HStack(spacing: 0) {
            Color.red
            Color.blue
        }.frame(width: 128, height: 128))
        let data = NSBitmapImageRep(cgImage: source.cgImage!).representation(using: .png, properties: [:])!
        let artwork = AlbumArtwork.decode(data)!
        precondition(artwork.colors.size.width <= 8 && artwork.colors.size.height <= 8)
        precondition(AlbumArtwork.decode(Data("invalid image".utf8)) == nil)

        let renderer = ImageRenderer(content: ArtworkGlow(colors: artwork.colors, darkHeight: 80)
            .frame(width: 480, height: 224)
            .background(.black))
        let bitmap = NSBitmapImageRep(cgImage: renderer.cgImage!)
        for y in 0..<80 {
            for x in 0..<480 {
                let pixel = bitmap.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
                precondition(max(pixel.redComponent, pixel.greenComponent, pixel.blueComponent) < 0.005,
                             "Artwork light must not enter the black header band.")
            }
        }
        let left = bitmap.colorAt(x: 100, y: 200)!.usingColorSpace(.deviceRGB)!
        let right = bitmap.colorAt(x: 380, y: 200)!.usingColorSpace(.deviceRGB)!
        precondition(left.redComponent > left.blueComponent + 0.2)
        precondition(right.blueComponent > right.redComponent + 0.2)
        try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("glow-artwork.png"))
        for phase in [0.0, Double.pi / 2, Double.pi, Double.pi * 1.5] {
            let reactive = ImageRenderer(content: ArtworkGlow(colors: artwork.colors, darkHeight: 80, level: 1, phase: phase)
                .frame(width: 480, height: 224)
                .background(.black))
            let pixels = NSBitmapImageRep(cgImage: reactive.cgImage!)
            for y in 0..<80 {
                for x in 0..<480 {
                    let pixel = pixels.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
                    precondition(max(pixel.redComponent, pixel.greenComponent, pixel.blueComponent) < 0.005,
                                 "Audio motion must stay below the header.")
                }
            }
            let warm = pixels.colorAt(x: 100, y: 200)!.usingColorSpace(.deviceRGB)!
            let cool = pixels.colorAt(x: 380, y: 200)!.usingColorSpace(.deviceRGB)!
            precondition(warm.redComponent > warm.blueComponent + 0.2)
            precondition(cool.blueComponent > cool.redComponent + 0.2)
            if phase == 0 {
                try pixels.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("glow-artwork-audio.png"))
            }
        }
        print("Passed: cover-derived colors, bounded color-map size, invalid artwork, and black header band.")
    }
}
