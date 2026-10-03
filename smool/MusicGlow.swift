import SwiftUI

struct MusicGlow: View {
    let colors: NSImage?
    let fallback: Color
    let darkHeight: CGFloat
    let audio: AudioSpectrum

    var body: some View {
        GeometryReader { geometry in
            let height = max(0, geometry.size.height - darkHeight)
            let colorMix = 0.35 + sin(audio.phase * 0.6) * 0.25

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
            .scaleEffect(1.6)
            .offset(x: sin(audio.phase * 0.7) * 64, y: cos(audio.phase * 0.53) * 20)
            .saturation(1.2)
            .blur(radius: 64)
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
            .opacity(audio.visibility)
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
                let phase = audio.phase + Double(index) * 1.1
                let lift = band.lift * 0.75 + audio.lift * 0.25
                let center = size.width * (0.08 + Double(index) * 0.42)
                // Incommensurate waves give a continuous drift, including in quiet frequency bands.
                let x = center + size.width * (sin(phase) * 0.1 + sin(phase * 0.53 + 2) * 0.04)
                let y = size.height * (1.25 - lift * 0.8 + sin(phase * 0.83) * 0.18 + sin(phase * 0.37) * 0.06)
                let width = size.width * (0.5 + lift * 0.1)
                let height = size.height * (0.55 + lift * 0.6)
                var cloud = context
                cloud.translateBy(x: x, y: y)
                cloud.scaleBy(x: width, y: height)
                cloud.fill(Path(ellipseIn: CGRect(x: -1, y: -1, width: 2, height: 2)), with: .radialGradient(
                    Gradient(stops: [
                        .init(color: .white, location: 0),
                        .init(color: .white.opacity(0.6), location: 0.5),
                        .init(color: .clear, location: 1)
                    ]),
                    center: .zero, startRadius: 0, endRadius: 1
                ))
            }
        }
    }
}
