import SwiftUI

struct NotchGlass: View {
    let shape: NotchShape
    let darkHeight: CGFloat

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        GeometryReader { geometry in
            if reduceTransparency {
                shape.fill(.black)
            } else {
                Color.clear
                    .glassEffect(.clear.tint(.black.opacity(0.8)), in: shape)
                    .overlay {
                        // Keep the entire header opaque, then reveal the glass gradually.
                        LinearGradient(
                            stops: [
                                .init(color: .black, location: 0),
                                .init(color: .black, location: min(1, darkHeight / max(1, geometry.size.height))),
                                .init(color: .black.opacity(0.72), location: 1)
                            ],
                            startPoint: .top, endPoint: .bottom
                        )
                    }
                    .clipShape(shape)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct NotchGlassEdge: View {
    let shape: NotchShape
    let darkHeight: CGFloat

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if !reduceTransparency {
            GeometryReader { geometry in
                // This glass sits above the content so its rim can pick up the applet's light.
                Color.clear
                    .glassEffect(.clear, in: shape)
                    .overlay {
                        shape.stroke(.white.opacity(0.55), lineWidth: 6)
                            .blur(radius: 2.5)
                    }
                    .overlay {
                        shape.stroke(.white.opacity(0.95), lineWidth: 2)
                    }
                    .mask {
                        shape.stroke(.white, lineWidth: 14)
                    }
                    .mask(alignment: .bottom) {
                        LinearGradient(colors: [.clear, .white.opacity(0.5), .white],
                                       startPoint: .top, endPoint: .bottom)
                            .frame(height: max(0, min(NotchLayout.bottomRadius, geometry.size.height - darkHeight)))
                    }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}
