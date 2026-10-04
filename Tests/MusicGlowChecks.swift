@testable import SmoolChecksSupport
import SwiftUI

@main
struct MusicGlowChecks {
    @MainActor
    static func main() throws {
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let cover = ImageRenderer(content: HStack(spacing: 0) {
            Color.red
            Color.blue
        }.frame(width: 128, height: 128)).nsImage!

        var quiet = AudioSpectrum()
        var loud = AudioSpectrum()
        var beat = AudioSpectrum()
        for _ in 0..<90 {
            quiet.update(AudioBands(bass: 0.02, middle: 0.02, treble: 0.02), elapsed: 1.0 / 30)
            loud.update(AudioBands(bass: 0.5, middle: 0.5, treble: 0.5), elapsed: 1.0 / 30)
            beat.update(AudioBands(bass: 0.12, middle: 0.12, treble: 0.12), elapsed: 1.0 / 30)
        }
        for _ in 0..<12 { beat.update(AudioBands(bass: 1, middle: 1, treble: 1), elapsed: 1.0 / 30) }
        var peak = AudioSpectrum()
        for _ in 0..<30 { peak.update(AudioBands(bass: 1, middle: 1, treble: 1), elapsed: 1.0 / 30) }
        var faded = beat
        for _ in 0..<210 { faded.update(AudioBands(), elapsed: 1.0 / 30) }

        for colors in [cover, nil] {
            var upperLight: [String: Double] = [:]
            for (name, audio) in [("silence", AudioSpectrum()), ("quiet", quiet), ("loud", loud),
                                  ("beat", beat), ("peak", peak), ("faded", faded)] {
                let renderer = ImageRenderer(content: MusicGlow(colors: colors, fallback: .green, darkHeight: 80, audio: audio)
                    .frame(width: 480, height: 224).background(.black))
                let pixels = NSBitmapImageRep(cgImage: renderer.cgImage!)
                var light = 0.0
                for y in 0..<224 {
                    for x in 0..<480 {
                        let pixel = pixels.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
                        let brightness = max(pixel.redComponent, pixel.greenComponent, pixel.blueComponent)
                        if y < 80 || name == "silence" || name == "faded" {
                            precondition(brightness < 0.005, "The notch band and silence must remain black in \(name).")
                        }
                        if (80..<160).contains(y) { light += brightness }
                    }
                }
                upperLight[name] = light
                let filename = "music-glow-\(colors == nil ? "fallback" : "cover")-\(name).png"
                try pixels.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(filename))
            }
            precondition(upperLight["loud"]! > upperLight["quiet"]! + 100,
                         "Louder music must raise the light into the upper part of the allowed band.")
            precondition(upperLight["beat"]! > upperLight["quiet"]! + 100)
        }
        for (name, bands) in [("bass", AudioBands(bass: 0.5)), ("treble", AudioBands(treble: 0.5))] {
            var spectrum = AudioSpectrum()
            for _ in 0..<90 { spectrum.update(bands, elapsed: 1.0 / 30) }
            let renderer = ImageRenderer(content: MusicGlow(colors: nil, fallback: .green, darkHeight: 80, audio: spectrum)
                .frame(width: 480, height: 224).background(.black))
            let pixels = NSBitmapImageRep(cgImage: renderer.cgImage!)
            var left = 0.0
            var right = 0.0
            for y in 0..<224 {
                for x in 0..<480 {
                    let pixel = pixels.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
                    let brightness = max(pixel.redComponent, pixel.greenComponent, pixel.blueComponent)
                    if y < 80 { precondition(brightness < 0.005) }
                    if x < 160 { left += brightness }
                    if x >= 320 { right += brightness }
                }
            }
            precondition(name == "bass" ? left > right * 1.4 : right > left * 1.4,
                         "Active bands must still dominate their side despite the shared flowing light.")
            precondition(min(left, right) > 10, "Light must remain present across quiet bands while music plays.")
            try pixels.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("music-glow-\(name).png"))

            for _ in 0..<60 { spectrum.update(bands, elapsed: 1.0 / 30) }
            let later = ImageRenderer(content: MusicGlow(colors: nil, fallback: .green, darkHeight: 80, audio: spectrum)
                .frame(width: 480, height: 224).background(.black))
            let moved = NSBitmapImageRep(cgImage: later.cgImage!)
            var leftMovement = 0.0
            var rightMovement = 0.0
            for y in 80..<224 {
                for x in 0..<480 {
                    let before = pixels.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!.greenComponent
                    let after = moved.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!.greenComponent
                    if x < 160 { leftMovement += abs(after - before) }
                    if x >= 320 { rightMovement += abs(after - before) }
                }
            }
            precondition(min(leftMovement, rightMovement) > 50,
                         "Visible drift must reach both sides even with a single sustained frequency band.")
            try moved.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("music-glow-\(name)-drift.png"))
        }
        print("Passed: black notch band at peak volume, dark silence, rising light, and artwork/fallback rendering.")
    }
}
