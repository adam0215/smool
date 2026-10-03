import SwiftUI

@MainActor
@Observable
final class NotchPresentation {
    var isExpanded = false
    var tab: NotchTab = .home
    var showCalendar = false
    let calendar = CalendarService()
    let music = MusicService()
    let spotify = SpotifyService()
    let spotifyState = SpotifyAppletState()
    let codexState = CodexAppletState()
    var layout = NotchLayout(screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900))

    var contentHeight: CGFloat { contentHeight(for: tab, calendar: showCalendar) }

    func contentHeight(for tab: NotchTab, calendar: Bool) -> CGFloat {
        if tab == .home, calendar { return 168 }
        if tab == .spotify, spotifyState.editingPlaylistLink { return 196 }
        if tab == .codex {
            if case .composer = codexState.scope { return 224 }
            if codexState.page == .usage { return 176 }
        }
        return tab.contentHeight
    }
}

struct NotchView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let presentation: NotchPresentation
    let selectTab: (NotchTab) -> Void
    var close: () -> Void = {}
    var restoreFocus: () -> Void = {}
    var openCalendar: () -> Void = {}
    var closeCalendar: () -> Void = {}
    var resizeContent: () -> Void = {}

    private var size: CGSize {
        presentation.isExpanded ? presentation.layout.expandedSize : presentation.layout.collapsedSize
    }

    private var shape: NotchShape {
        NotchShape(
            shoulderRadius: presentation.isExpanded ? 0 : 4,
            bottomRadius: presentation.isExpanded ? NotchLayout.bottomRadius : 8
        )
    }

    private var horizontalAnimation: Animation? {
        guard !reduceMotion else { return nil }
        return presentation.isExpanded
            ? .spring(response: 0.48, dampingFraction: 0.78)
            : .spring(response: 0.42, dampingFraction: 0.86).delay(0.03)
    }

    private var verticalAnimation: Animation? {
        guard !reduceMotion else { return nil }
        return presentation.isExpanded
            ? .spring(response: 0.54, dampingFraction: 0.76).delay(0.025)
            : .spring(response: 0.4, dampingFraction: 0.86)
    }

    var body: some View {
        shape
            .fill(.black)
            .frame(width: size.width)
            .animation(horizontalAnimation, value: presentation.isExpanded)
            .frame(height: size.height, alignment: .top)
            .animation(verticalAnimation, value: presentation.isExpanded)
            .overlay(alignment: .top) {
                if presentation.isExpanded {
                    NotchContentView(presentation: presentation, selectTab: selectTab, restoreFocus: restoreFocus, openCalendar: openCalendar, closeCalendar: closeCalendar)
                        .frame(width: presentation.layout.expandedSize.width, height: presentation.layout.expandedSize.height)
                        .transition(.asymmetric(insertion: .identity, removal: .opacity.animation(.easeOut(duration: 0.16))))
                }
            }
            .clipShape(shape)
            .shadow(color: .black.opacity(presentation.isExpanded ? 0.22 : 0), radius: 14, y: 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .ignoresSafeArea()
            .preferredColorScheme(.dark)
            .environment(\.locale, Locale(identifier: "sv_SE"))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("smool")
            .onChange(of: presentation.contentHeight) { _, _ in resizeContent() }
            .onExitCommand(perform: close)
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
            style: .circular
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
