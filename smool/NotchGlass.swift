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
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        if !reduceTransparency {
            GeometryReader { geometry in
                // Color dodge amplifies the content's own channels instead of painting white.
                // Clipping the outer half leaves one physical pixel inside the panel.
                shape.stroke(Color(white: 0.65), lineWidth: 2 / displayScale)
                    .mask(alignment: .bottom) {
                        LinearGradient(colors: [.clear, .white.opacity(0.5), .white],
                                       startPoint: .top, endPoint: .bottom)
                            .frame(height: max(0, min(NotchLayout.bottomRadius, geometry.size.height - darkHeight)))
                    }
            }
            .blendMode(.colorDodge)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}
