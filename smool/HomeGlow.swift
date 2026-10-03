import SwiftUI

nonisolated struct HomeGlow: View, Animatable {
    var spotify: Double
    var codex: Double
    let darkHeight: CGFloat
    var level = 0.0
    var phase = 0.0

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(spotify, codex) }
        set {
            spotify = newValue.first
            codex = newValue.second
        }
    }

    static func color(for app: HomeApp?) -> Color {
        switch app {
        case .spotify: Color(nsColor: .systemGreen)
        case .codex: Color(nsColor: .systemPurple).mix(with: .black, by: 0.46)
        case nil: Color(nsColor: .systemBlue)
        }
    }

    var body: some View {
        Canvas { context, size in
            let color = Self.color(for: nil)
                .mix(with: Self.color(for: .spotify), by: spotify)
                .mix(with: Self.color(for: .codex), by: codex)
            let centerX = size.width * (0.5 + 0.25 * (codex - spotify)) + sin(phase) * level * 36
            let height = max(0, size.height - darkHeight)

            // No gradient can contribute a pixel above this band, even mid-animation.
            context.clip(to: Path(CGRect(x: 0, y: darkHeight, width: size.width, height: height)))
            for (tint, opacity, radius) in [
                (color, 0.66, CGSize(width: size.width * (0.66 + level * 0.1), height: height)),
                (color.mix(with: .white, by: 0.4), 0.2 + level * 0.12,
                 CGSize(width: size.width * 0.3, height: height * (0.48 + level * 0.14)))
            ] {
                var glow = context
                glow.translateBy(x: centerX, y: size.height)
                glow.scaleBy(x: radius.width, y: max(1, radius.height))
                let area = CGRect(x: -centerX / radius.width, y: -height / max(1, radius.height),
                                  width: size.width / radius.width, height: height / max(1, radius.height))
                glow.fill(Path(area), with: .radialGradient(
                    Gradient(colors: [tint.opacity(opacity), .clear]),
                    center: .zero, startRadius: 0, endRadius: 1
                ))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
