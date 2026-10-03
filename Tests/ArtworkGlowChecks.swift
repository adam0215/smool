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
        print("Passed: cover-derived colors, bounded color-map size, invalid artwork, and black header band.")
    }
}
