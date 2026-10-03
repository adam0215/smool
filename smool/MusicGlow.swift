import SwiftUI

struct MusicGlow: View {
    let colors: NSImage?
    let fallback: Color
    let darkHeight: CGFloat
    let audio: AudioEnvelope

    var body: some View {
        GeometryReader { geometry in
            let height = max(0, geometry.size.height - darkHeight)
            let lift = audio.lift

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
                        .opacity(audio.colorMix)
                } else {
                    LinearGradient(
                        colors: [fallback, fallback.mix(with: .white, by: 0.2 + audio.colorMix * 0.4)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                }
            }
            .frame(width: geometry.size.width, height: height)
            .scaleEffect(1.2)
            .offset(x: sin(audio.phase) * audio.level * 24)
            .saturation(1.1 + audio.pulse * 0.2)
            .blur(radius: 32)
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: max(0, 0.85 - lift * 0.85)),
                        .init(color: .white.opacity(0.45), location: 1 - lift * 0.4),
                        .init(color: .white, location: 1)
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            }
            .opacity(audio.opacity)
            .clipped()
            .offset(y: darkHeight)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
