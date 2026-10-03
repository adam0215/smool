import SwiftUI

@main
struct ArtworkGlowChecks {
    @MainActor
    static func main() async throws {
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let source = ImageRenderer(content: HStack(spacing: 0) {
            Color.red
            Color.blue
        }.frame(width: 128, height: 128))
        let data = NSBitmapImageRep(cgImage: source.cgImage!).representation(using: .png, properties: [:])!
        let artwork = AlbumArtwork.decode(data)!
        precondition(artwork.colors.size.width <= 8 && artwork.colors.size.height <= 8)
        precondition(AlbumArtwork.decode(Data("invalid image".utf8)) == nil)

        var loads = 0
        let cache = AlbumArtworkCache(capacity: 2) { _ in
            loads += 1
            try? await Task.sleep(for: .milliseconds(20))
            return artwork
        }
        let first = AlbumArtwork.Source.spotify(URL(string: "https://i.scdn.co/image/first")!)
        let second = AlbumArtwork.Source.spotify(URL(string: "https://i.scdn.co/image/second")!)
        let third = AlbumArtwork.Source.embedded(data)
        precondition(cache.cached(first) == nil)
        let player = Task { await cache.load(first) }
        let glow = Task { await cache.load(first) }
        let playerArtwork = await player.value
        let glowArtwork = await glow.value
        precondition(loads == 1, "The player and glow must share one artwork request.")
        precondition(playerArtwork?.image === glowArtwork?.image)
        precondition(cache.cached(first)?.colors === artwork.colors, "Recreated views need decoded colors synchronously.")
        _ = await cache.load(first)
        precondition(loads == 1, "Reopening must not redownload the same cover.")
        _ = await cache.load(second)
        _ = cache.cached(first)
        _ = await cache.load(third)
        precondition(cache.cached(first) != nil && cache.cached(third) != nil)
        precondition(cache.cached(second) == nil, "Evict the least recently used cover at capacity.")

        let closingView = Task { await cache.load(second) }
        await Task.yield()
        closingView.cancel()
        _ = await closingView.value
        precondition(cache.cached(second) != nil, "A requested cover should finish caching after its view closes.")

        var attempts = 0
        let retryCache = AlbumArtworkCache { _ in
            attempts += 1
            return attempts == 1 ? nil : artwork
        }
        _ = await retryCache.load(first)
        precondition(retryCache.cached(first) == nil)
        _ = await retryCache.load(first)
        precondition(attempts == 2 && retryCache.cached(first) != nil, "Failed artwork loads must remain retryable.")

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
        print("Passed: synchronous artwork reuse, shared loads, eviction, cancellation, retry, cover colors, and black header band.")
    }
}
