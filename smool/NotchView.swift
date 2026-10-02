import SwiftUI

@MainActor
@Observable
final class NotchPresentation {
    var isExpanded = false
    var layout = NotchLayout(screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900))
}

struct NotchView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let presentation: NotchPresentation

    private var size: CGSize {
        presentation.isExpanded ? presentation.layout.expandedSize : presentation.layout.collapsedSize
    }

    private var shape: NotchShape {
        NotchShape(
            shoulderRadius: presentation.isExpanded ? 14 : 4,
            bottomRadius: presentation.isExpanded ? 64 : 8
        )
    }

    private var horizontalAnimation: Animation? {
        guard !reduceMotion else { return nil }
        return presentation.isExpanded
            ? .spring(duration: 0.28, bounce: 0.20)
            : .spring(duration: 0.32, bounce: 0.16).delay(0.03)
    }

    private var verticalAnimation: Animation? {
        guard !reduceMotion else { return nil }
        return presentation.isExpanded
            ? .spring(duration: 0.40, bounce: 0.32).delay(0.025)
            : .spring(duration: 0.26, bounce: 0.12)
    }

    var body: some View {
        shape
            .fill(.black)
            .animation(horizontalAnimation) { content in
                content.frame(width: size.width)
            }
            .animation(verticalAnimation) { content in
                content.frame(height: size.height, alignment: .top)
            }
            .overlay(alignment: .top) {
                NotchHeader(layout: presentation.layout) {
                    EmptyView()
                } center: {
                    Text("smool")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.65))
                } trailing: {
                    EmptyView()
                }
                .frame(width: presentation.layout.expandedSize.width)
                .opacity(presentation.isExpanded ? 1 : 0)
                .accessibilityHidden(!presentation.isExpanded)
                .allowsHitTesting(presentation.isExpanded)
            }
            .clipShape(shape)
            .shadow(color: .black.opacity(presentation.isExpanded ? 0.22 : 0), radius: 14, y: 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .ignoresSafeArea()
            .preferredColorScheme(.dark)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("smool")
    }
}

// Concave shoulders join the screen edge; the lower corners curve inward.
struct NotchShape: Shape {
    var shoulderRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(shoulderRadius, bottomRadius) }
        set {
            shoulderRadius = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let shoulder = min(shoulderRadius, rect.height / 3)
        let corner = min(bottomRadius, rect.height / 2)
        let left = rect.minX + shoulder
        let right = rect.maxX - shoulder
        let top = rect.minY

        var path = UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: corner,
            bottomTrailingRadius: corner,
            topTrailingRadius: 0,
            style: .continuous
        ).path(in: CGRect(x: left, y: top, width: right - left, height: rect.height))

        path.move(to: CGPoint(x: rect.minX, y: top))
        path.addLine(to: CGPoint(x: left, y: top))
        path.addLine(to: CGPoint(x: left, y: top + shoulder))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: top), control: CGPoint(x: left, y: top))
        path.closeSubpath()

        path.move(to: CGPoint(x: right, y: top))
        path.addLine(to: CGPoint(x: rect.maxX, y: top))
        path.addQuadCurve(to: CGPoint(x: right, y: top + shoulder), control: CGPoint(x: right, y: top))
        path.closeSubpath()

        return path
    }
}
