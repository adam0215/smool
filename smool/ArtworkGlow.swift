import SwiftUI

struct ArtworkGlow: View {
    let colors: NSImage
    let darkHeight: CGFloat

    var body: some View {
        GeometryReader { geometry in
            let height = max(0, geometry.size.height - darkHeight)

            Image(nsImage: colors)
                .resizable()
                .interpolation(.high)
                .scaledToFill()
                .frame(width: geometry.size.width, height: height)
                .blur(radius: 32)
                .mask {
                    LinearGradient(
                        stops: [.init(color: .clear, location: 0),
                                .init(color: .white.opacity(0.35), location: 0.4),
                                .init(color: .white, location: 1)],
                        startPoint: .top, endPoint: .bottom
                    )
                }
                .clipped()
                .offset(y: darkHeight)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
