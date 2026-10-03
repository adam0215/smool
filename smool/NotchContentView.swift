import SwiftUI

struct NotchContentView: View {
    let presentation: NotchPresentation
    let selectTab: (NotchTab) -> Void
    var restoreFocus: () -> Void = {}
    var openCalendar: () -> Void = {}
    var closeCalendar: () -> Void = {}

    var body: some View {
        VStack(spacing: 8) {
            NotchTabBar(layout: presentation.layout, selection: presentation.tab, select: selectTab)

            Group {
                switch presentation.tab {
                case .home:
                    if presentation.showCalendar {
                        CalendarAppletView(service: presentation.calendar, close: closeCalendar)
                    } else {
                        TimelineView(.everyMinute) { context in
                            NotchHomeView(layout: presentation.layout, date: context.date, openTab: selectTab, openCalendar: openCalendar)
                        }
                    }
                case .spotify:
                    SpotifyAppletView(service: presentation.spotify, state: presentation.spotifyState)
                case .codex:
                    CodexAppletView(state: presentation.codexState, restoreFocus: restoreFocus)
                case .music:
                    MusicAppletView(service: presentation.music)
                }
            }
            .id(presentation.tab)
            .transition(.opacity)
        }
        .background {
            if presentation.tab != .home {
                HomeGlow(
                    spotify: presentation.tab == .spotify ? 1 : 0,
                    codex: presentation.tab == .codex ? 1 : 0,
                    darkHeight: max(presentation.layout.headerSize.height + 16, presentation.layout.expandedSize.height - 128)
                )
                .opacity(0.65)
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
        return min(12, max(0, (sideWidth - 104) / 2))
    }

    private var tabWidth: CGFloat {
        let sideWidth = layout.headerRegions(in: layout.expandedSize.width - 8).leading.width
        return min(28, max(18, (sideWidth - 12) / 4))
    }

    private func greeting(at date: Date) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        let salutation: String
        switch hour {
        case 5..<10: salutation = "God morgon"
        case 10..<12: salutation = "God förmiddag"
        case 12..<18: salutation = "God eftermiddag"
        case 18..<23: salutation = "God kväll"
        default: salutation = "God natt"
        }
        let name = NSFullUserName().split(separator: " ").first.map(String.init) ?? NSUserName()
        return "\(salutation), \(name)"
    }

    var body: some View {
        NotchHeader(layout: layout, sideInset: sideInset, height: max(44, layout.headerSize.height)) {
            VStack(alignment: .leading, spacing: 3) {
                TimelineView(.everyMinute) { context in
                    Text(greeting(at: context.date))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                GlassEffectContainer(spacing: 4) {
                    HStack(spacing: 4) {
                        ForEach(NotchTab.allCases, id: \.self) { tab in
                            Button { select(tab) } label: {
                                HStack(spacing: 3) {
                                    if tab == .home || tab == .music {
                                        Image(systemName: tab == .home ? "house.fill" : "music.note")
                                            .font(.system(size: 10))
                                    } else {
                                        Image(tab.title)
                                            .resizable()
                                            .renderingMode(.template)
                                            .scaledToFit()
                                            .frame(width: 10, height: 10)
                                    }
                                }
                                .foregroundStyle(selection == tab ? .white : .white.opacity(0.55))
                                .frame(width: tabWidth, height: 18)
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
                            .help(tab.title)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        } center: {
            EmptyView()
        } trailing: {
            TimelineView(.everyMinute) { _ in
                let battery = BatteryStatus.current()
                HStack(spacing: 4) {
                    Spacer(minLength: 0)
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
