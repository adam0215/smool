import SwiftUI

struct NotchGlass: View {
    let shape: NotchShape
    let darkHeight: CGFloat

    var body: some View {
        shape.fill(.black)
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
