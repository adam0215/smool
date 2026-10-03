import SwiftUI

struct NotchContentView: View {
    let presentation: NotchPresentation
    let selectTab: (NotchTab) -> Void
    var restoreFocus: () -> Void = {}

    var body: some View {
        GlassEffectContainer(spacing: 0) {
            VStack(spacing: 8) {
                NotchTabBar(layout: presentation.layout, selection: presentation.tab, select: selectTab)

                switch presentation.tab {
                case .home:
                    TimelineView(.everyMinute) { context in
                        NotchHomeView(layout: presentation.layout, date: context.date, openTab: selectTab)
                    }
                case .spotify:
                    SpotifyAppletView(service: presentation.spotify, state: presentation.spotifyState)
                case .codex:
                    CodexAppletView(state: presentation.codexState, restoreFocus: restoreFocus)
                }
            }
        }
        .background {
            if presentation.tab != .home {
                HomeGlow(
                    spotify: presentation.tab == .spotify ? 1 : 0,
                    codex: presentation.tab == .codex ? 1 : 0,
                    darkHeight: max(presentation.layout.headerSize.height + 16, presentation.layout.expandedSize.height - 128)
                )
            }
        }
    }
}

struct NotchTabBar: View {
    let layout: NotchLayout
    let selection: NotchTab
    let select: (NotchTab) -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var sideInset: CGFloat {
        let sideWidth = layout.headerRegions(in: layout.expandedSize.width - 8).leading.width
        return min(12, max(0, (sideWidth - 80) / 2))
    }

    var body: some View {
        NotchHeader(layout: layout, sideInset: sideInset) {
            HStack(spacing: 4) {
                ForEach(NotchTab.allCases, id: \.self) { tab in
                    Button { select(tab) } label: {
                        Group {
                            if tab == .home {
                                Image(systemName: "house.fill")
                                    .font(.system(size: 10))
                            } else {
                                Image(tab.title)
                                    .resizable()
                                    .renderingMode(.template)
                                    .scaledToFit()
                                    .frame(width: 10, height: 10)
                            }
                        }
                        .modifier(GlassInk(illumination: 1, isSelected: selection == tab))
                        .frame(width: 24, height: 16)
                        .background {
                            if reduceTransparency {
                                Capsule().fill(Color(white: selection == tab ? 0.25 : 0.1))
                            }
                        }
                        .glassEffect(.clear.tint(tab.tint.opacity(selection == tab ? 0.08 : 0.008)).interactive(), in: .capsule)
                        .overlay {
                            Capsule().strokeBorder(.white.opacity(selection == tab ? 0.18 : 0), lineWidth: 0.5)
                        }
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .accessibilityLabel(tab.title)
                    .accessibilityAddTraits(selection == tab ? .isSelected : [])
                    .help("\(tab.title) · ⌘\(tab.rawValue)")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } center: {
            EmptyView()
        } trailing: {
            TimelineView(.everyMinute) { _ in
                let battery = BatteryStatus.current()
                HStack(spacing: 2) {
                    if let battery {
                        Text("\(battery.percentage)%")
                            .font(.system(size: 8))
                            .monospacedDigit()
                    }
                    Image(systemName: battery?.symbolName ?? "powerplug.fill")
                        .font(.system(size: 10))
                }
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(battery?.description ?? "Nätansluten")
            }
        }
        .padding(.horizontal, 4)
    }
}
