import SwiftUI

@MainActor
@Observable
final class NotchPresentation {
    var isExpanded = false
    var layout = NotchLayout(screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900))
}

struct NotchView: View {
    let presentation: NotchPresentation

    private var size: CGSize {
        presentation.isExpanded ? presentation.layout.expandedSize : presentation.layout.collapsedSize
    }

    private var shape: NotchShape {
        NotchShape(
            shoulderRadius: presentation.isExpanded ? 14 : 4,
            bottomRadius: presentation.isExpanded ? 30 : 8
        )
    }

    var body: some View {
        shape
            .fill(.black)
            .frame(width: size.width, height: size.height)
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
    var shoulderRadius: CGFloat = 14
    var bottomRadius: CGFloat = 30

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
