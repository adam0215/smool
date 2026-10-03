import SwiftUI

struct MusicGlow: View {
    let colors: NSImage?
    let fallback: Color
    let darkHeight: CGFloat
    let audio: AudioSpectrum

    var body: some View {
        GeometryReader { geometry in
            let height = max(0, geometry.size.height - darkHeight)
            let colorMix = (audio.bass.colorMix + audio.middle.colorMix + audio.treble.colorMix) / 3
            let phase = (audio.bass.phase + audio.middle.phase + audio.treble.phase) / 3

            ZStack {
                if let colors {
                    Image(nsImage: colors)
                        .resizable()
                        .scaledToFill()
                    // Blend another part of the same cover into the light as the music rises.
                    Image(nsImage: colors)
                        .resizable()
                        .scaledToFill()
                        .scaleEffect(x: -1, y: -1)
                        .opacity(colorMix)
                } else {
                    LinearGradient(
                        colors: [fallback, fallback.mix(with: .white, by: 0.2 + colorMix * 0.4)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                }
            }
            .frame(width: geometry.size.width, height: height)
            .scaleEffect(1.3)
            .offset(x: sin(phase) * 36)
            .saturation(1.2)
            .blur(radius: 32)
            .mask { clouds }
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .clear, location: 0.08),
                        .init(color: .white.opacity(0.65), location: 0.5),
                        .init(color: .white, location: 1)
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            }
            // Clip after every blur and transform. Nothing can paint above the black notch band.
            .clipped()
            .offset(y: darkHeight)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var clouds: some View {
        Canvas { context, size in
            context.blendMode = .plusLighter
            for (index, band) in [audio.bass, audio.middle, audio.treble].enumerated() {
                guard band.opacity > 0 else { continue }
                let phase = band.phase + Double(index) * 2.1
                let center = size.width * (0.12 + Double(index) * 0.38)

                for layer in 0..<3 {
                    let drift = phase + Double(layer) * 1.8
                    let x = center + sin(drift) * size.width * 0.055 * band.lift
                    let y = size.height * (1.12 - band.lift * 0.5 + cos(drift * 0.7) * band.lift * 0.13)
                    let width = size.width * (0.24 + Double(layer) * 0.025 + band.lift * 0.06)
                    let height = size.height * (0.22 + band.lift * 0.7 + Double(layer) * 0.06)
                    var cloud = context
                    cloud.translateBy(x: x, y: y)
                    cloud.scaleBy(x: width, y: height)
                    cloud.fill(Path(ellipseIn: CGRect(x: -1, y: -1, width: 2, height: 2)), with: .radialGradient(
                        Gradient(stops: [
                            .init(color: .white.opacity(band.opacity * 0.65), location: 0),
                            .init(color: .white.opacity(band.opacity * 0.3), location: 0.45),
                            .init(color: .clear, location: 1)
                        ]),
                        center: .zero, startRadius: 0, endRadius: 1
                    ))
                }
            }
        }
    }
}
