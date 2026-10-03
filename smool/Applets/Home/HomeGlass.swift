import SwiftUI

/// Keeps the outside bottom arc concentric with the panel, including narrow cards.
struct HomeCardShape: InsettableShape {
    enum Edge { case none, leading, trailing, both }

    var edge: Edge = .none
    private var inset: CGFloat = 0

    init(edge: Edge = .none) { self.edge = edge }

    func inset(by amount: CGFloat) -> HomeCardShape {
        var shape = self
        shape.inset += amount
        return shape
    }

    func path(in bounds: CGRect) -> Path {
        let rect = bounds.insetBy(dx: inset, dy: inset)
        let outer = min(NotchLayout.bottomRadius - NotchLayout.contentInset, bounds.width / (edge == .both ? 2 : 1))
        let inner = min(16, max(0, bounds.width - outer))
        let left = max(0, (edge == .leading || edge == .both ? outer : edge == .trailing ? inner : 16) - inset)
        let right = max(0, (edge == .trailing || edge == .both ? outer : edge == .leading ? inner : 16) - inset)
        let top = max(0, min(16, bounds.width / 2) - inset)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + top, y: rect.minY))
        path.addArc(center: CGPoint(x: rect.maxX - top, y: rect.minY + top), radius: top,
                    startAngle: .degrees(-90), endAngle: .zero, clockwise: false)
        path.addArc(center: CGPoint(x: rect.maxX - right, y: rect.maxY - right), radius: right,
                    startAngle: .zero, endAngle: .degrees(90), clockwise: false)
        path.addArc(center: CGPoint(x: rect.minX + left, y: rect.maxY - left), radius: left,
                    startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        path.addArc(center: CGPoint(x: rect.minX + top, y: rect.minY + top), radius: top,
                    startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        path.closeSubpath()
        return path
    }
}

/// The material is masked to the original glyph, so the glass belongs to the ink,
/// rather than adding a rectangular badge behind the text or logo.
struct GlassInk: ViewModifier {
    let illumination: Double
    var isSelected = false

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if reduceTransparency {
            content.foregroundStyle(.white.opacity(isSelected ? 0.95 : 0.8))
        } else {
            content.foregroundStyle(.clear)
                .overlay {
                    GlassEffectContainer(spacing: 0) {
                        Color.clear
                            .glassEffect(.clear.tint(.white.opacity(0.1)), in: .rect(cornerRadius: 0))
                    }
                    .overlay {
                        LinearGradient(stops: [
                            .init(color: .white.opacity(0.12 + illumination * 0.56), location: 0),
                            .init(color: .white.opacity(0.08 + illumination * 0.22), location: 0.38),
                            .init(color: .white.opacity(0.04 + illumination * 0.1), location: 0.52),
                            .init(color: .white.opacity(0.12 + illumination * (isSelected ? 0.75 : 0.4)), location: 0.82),
                            .init(color: .white.opacity(0.2 + illumination * 0.65), location: 1)
                        ], startPoint: .topLeading, endPoint: .bottomTrailing)
                    }
                    .overlay(.white.opacity(0.03 + illumination * 0.07))
                    .mask { content.foregroundStyle(.white) }
                    .opacity(0.2 + illumination * 0.8)
                }
                .overlay {
                    content.foregroundStyle(.black.shadow(.inner(
                        color: .white.opacity(0.08 + illumination * 0.5), radius: 0.6, x: 0.5, y: 0.8
                    )))
                    .blendMode(.screen)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
                .overlay {
                    content.foregroundStyle(.black.shadow(.inner(
                        color: .white.opacity(illumination * 0.65), radius: 0.5, x: -0.4, y: -0.6
                    )))
                    .blendMode(.screen)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
        }
    }
}

struct HomeCardGlass: ViewModifier {
    let shape: HomeCardShape
    let illumination: Double
    var isSelected = false

    func body(content: Content) -> some View {
        content.modifier(CardGlass(shape: shape, illumination: illumination, isSelected: isSelected))
    }
}

struct CardGlass<S: InsettableShape>: ViewModifier {
    let shape: S
    var illumination = 1.0
    var isSelected = false

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background {
                shape.fill(Color(white: isSelected ? 0.18 : 0.08))
                    .overlay { shape.strokeBorder(.white.opacity(isSelected ? 0.3 : 0.1), lineWidth: 1) }
            }
        } else {
            content
                .glassEffect(
                    .clear.tint(.white.opacity((isSelected ? 0.065 : 0.015) * illumination)).interactive(),
                    in: shape
                )
                .overlay {
                    shape.strokeBorder(.white.opacity(isSelected ? 0.2 : 0), lineWidth: 1)
                        .blur(radius: 0.5)
                        .allowsHitTesting(false)
                }
        }
    }
}
