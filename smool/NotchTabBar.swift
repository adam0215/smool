import SwiftUI

struct NotchTabBar: View {
    let presentation: NotchPresentation
    let select: (NotchTab) -> Void

    var body: some View {
        HStack(spacing: 10) {
            TimelineView(.everyMinute) { context in
                Text(greeting(at: context.date))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            GlassEffectContainer(spacing: 4) {
                HStack(spacing: 4) {
                    ForEach(NotchTab.allCases, id: \.self) { tab in
                        Button { select(tab) } label: {
                            tabIcon(tab)
                                .foregroundStyle(.white.opacity(presentation.tab == tab ? 1 : 0.65))
                                .frame(width: 25, height: 22)
                                .glassEffect(.clear.tint(tab.tint.opacity(presentation.tab == tab ? 0.12 : 0.015)), in: .capsule)
                                .overlay { Capsule().strokeBorder(.white.opacity(presentation.tab == tab ? 0.18 : 0), lineWidth: 0.5) }
                        }
                        .buttonStyle(.plain).focusable(false)
                        .accessibilityLabel(tab.title)
                        .accessibilityAddTraits(presentation.tab == tab ? .isSelected : [])
                        .help(tab.title)
                    }
                }
            }

            pageIndicators
            TimelineView(.everyMinute) { _ in
                if let battery = BatteryStatus.current() {
                    HStack(spacing: 3) {
                        Text("\(battery.percentage)%").font(.system(size: 9)).monospacedDigit()
                        Image(systemName: battery.symbolName).font(.system(size: 10))
                    }
                    .foregroundStyle(.secondary)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(battery.description)
                }
            }
            NotchActionsMenu(presentation: presentation)
        }
        .padding(.horizontal, 20)
        .frame(height: 40)
        .padding(.top, presentation.layout.notch.obscuresCenter ? presentation.layout.headerSize.height : 0)
    }

    @ViewBuilder private func tabIcon(_ tab: NotchTab) -> some View {
        switch tab {
        case .home, .music:
            Image(systemName: tab == .home ? "house.fill" : "music.note")
                .font(.system(size: 11, weight: .medium))
        case .spotify, .codex:
            Image(tab.title).resizable().renderingMode(.template)
                .scaledToFit().frame(width: 11, height: 11)
        }
    }

    @ViewBuilder private var pageIndicators: some View {
        switch presentation.tab {
        case .spotify:
            indicators(SpotifyPage.allCases, selected: presentation.spotifyState.page, title: { $0.title }) {
                presentation.spotifyState.page = $0
            }
        case .codex:
            indicators(CodexPage.allCases, selected: presentation.codexState.page, title: { $0.rawValue }) {
                presentation.codexState.scope = .deck
                presentation.codexState.page = $0
            }
        default: EmptyView()
        }
    }

    private func indicators<Page: Hashable>(_ pages: [Page], selected: Page, title: @escaping (Page) -> String, select: @escaping (Page) -> Void) -> some View {
        HStack(spacing: 0) {
            ForEach(pages, id: \.self) { page in
                Button { select(page) } label: {
                    Capsule().fill(.white.opacity(page == selected ? 0.85 : 0.25))
                        .frame(width: page == selected ? 10 : 4, height: 4)
                        .frame(width: 14, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain).focusable(false)
                .accessibilityLabel(title(page))
                .accessibilityAddTraits(page == selected ? .isSelected : [])
                .help(title(page))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sidor")
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
}
