import SwiftUI

/// Keeps the lower outside arc concentric with the panel, without SwiftUI scaling
/// both bottom radii down to fit the narrow card.
struct HomeCardShape: InsettableShape {
    var app: HomeApp?
    private var inset: CGFloat = 0

    init(app: HomeApp? = nil) {
        self.app = app
    }

    func inset(by amount: CGFloat) -> HomeCardShape {
        var shape = self
        shape.inset += amount
        return shape
    }

    func path(in bounds: CGRect) -> Path {
        let rect = bounds.insetBy(dx: inset, dy: inset)
        guard let app else {
            return RoundedRectangle(cornerRadius: max(0, 16 - inset), style: .circular).path(in: rect)
        }

        let outer = max(0, NotchLayout.bottomRadius - NotchLayout.contentInset - inset)
        let inner = max(0, bounds.width - (NotchLayout.bottomRadius - NotchLayout.contentInset) - inset)
        let top = max(0, 16 - inset)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + top, y: rect.minY))
        path.addArc(center: CGPoint(x: rect.maxX - top, y: rect.minY + top), radius: top,
                    startAngle: .degrees(-90), endAngle: .zero, clockwise: false)
        path.addArc(center: CGPoint(x: rect.maxX - inner, y: rect.maxY - inner), radius: inner,
                    startAngle: .zero, endAngle: .degrees(90), clockwise: false)
        path.addArc(center: CGPoint(x: rect.minX + outer, y: rect.maxY - outer), radius: outer,
                    startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        path.addArc(center: CGPoint(x: rect.minX + top, y: rect.minY + top), radius: top,
                    startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        path.closeSubpath()

        if app == .codex {
            return path.applying(CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: bounds.midX * 2, ty: 0))
        }
        return path
    }
}

/// The material is masked to the original glyph, so the glass belongs to the ink,
/// rather than adding a rectangular badge behind the text or logo.
struct GlassInk: ViewModifier {
    let tint: Color
    let illumination: Double
    var isSelected = false

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if reduceTransparency {
            content.foregroundStyle(isSelected ? tint : .white.opacity(0.8))
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
                            .init(color: tint.opacity(0.08 + illumination * 0.22), location: 0.38),
                            .init(color: .white.opacity(0.04 + illumination * 0.1), location: 0.52),
                            .init(color: tint.opacity(0.12 + illumination * (isSelected ? 0.75 : 0.4)), location: 0.82),
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
                        color: tint.opacity(illumination * 0.65), radius: 0.5, x: -0.4, y: -0.6
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
    let tint: Color
    let illumination: Double
    var isSelected = false

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background {
                shape.fill(Color(white: isSelected ? 0.18 : 0.08))
                    .overlay { shape.strokeBorder(tint.opacity(isSelected ? 0.7 : 0.15), lineWidth: 1) }
            }
        } else {
            content
                .glassEffect(
                    .clear.tint(tint.opacity((isSelected ? 0.2 : 0.025) * illumination)).interactive(shape.app != nil),
                    in: shape
                )
                .overlay {
                    shape.strokeBorder(tint.opacity(isSelected ? 0.45 : 0), lineWidth: 1)
                        .blur(radius: 0.5)
                        .allowsHitTesting(false)
                }
        }
    }
}
