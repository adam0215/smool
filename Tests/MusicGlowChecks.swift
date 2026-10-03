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

        var quiet = AudioEnvelope()
        var loud = AudioEnvelope()
        var beat = AudioEnvelope()
        for _ in 0..<90 {
            quiet.update(rms: 0.02, elapsed: 1.0 / 30)
            loud.update(rms: 0.5, elapsed: 1.0 / 30)
            beat.update(rms: 0.12, elapsed: 1.0 / 30)
        }
        for _ in 0..<4 { beat.update(rms: 1, elapsed: 1.0 / 30) }
        var peak = AudioEnvelope()
        for _ in 0..<10 { peak.update(rms: 1, elapsed: 1.0 / 30) }
        precondition(peak.lift == 1, "Exercise the highest possible glow against the notch boundary.")
        var faded = beat
        for _ in 0..<60 { faded.update(rms: 0, elapsed: 1.0 / 30) }

        for colors in [cover, nil] {
            var upperLight: [String: Double] = [:]
            for (name, audio) in [("silence", AudioEnvelope()), ("quiet", quiet), ("loud", loud),
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
        print("Passed: black notch band at peak volume, dark silence, rising light, and artwork/fallback rendering.")
    }
}
