import SwiftUI

struct NotchHomeView: View {
    let layout: NotchLayout
    let date: Date
    var applets: [AppletDestination] = []
    var openApplet: (AppletID) -> Void = { _ in }
    var openCalendar: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focusedCard: HomeCard?
    @State private var hoveredCard: HomeCard?
    @State private var lightLevel = 0.0

    private var cards: [HomeCard] { HomeCard.arrangement(for: Array(applets.prefix(3)).map(\.id)) }
    private var activeCard: HomeCard { hoveredCard ?? focusedCard ?? .clock }

    var body: some View {
        GlassEffectContainer(spacing: 0) {
            HStack(spacing: 8) {
                ForEach(cards, id: \.self) { card in
                    let shape = HomeCardShape(edge: edge(for: card))
                    switch card {
                    case .clock:
                        clock(shape: shape)
                    case .applet(let id):
                        if let applet = applets.first(where: { $0.id == id }) {
                            appButton(applet, shape: shape)
                        }
                    }
                }
            }
            .padding(.horizontal, NotchLayout.contentInset)
            .padding(.bottom, NotchLayout.contentInset)
        }
        .background {
            activeCard.glow(applets: applets)
                .opacity(lightLevel)
        }
        .animation(reduceMotion ? .linear(duration: 0.12) : .easeInOut(duration: 0.7), value: activeCard)
        .onAppear { focusedCard = .clock }
        .onAppletFocusRestore { focusedCard = .clock }
        .onChange(of: cards) { _, _ in
            if let focusedCard, !cards.contains(focusedCard) { self.focusedCard = .clock }
            if let hoveredCard, !cards.contains(hoveredCard) { self.hoveredCard = nil }
        }
        .task {
            withAnimation(reduceMotion ? .linear(duration: 0.12) : .timingCurve(0.5, 0, 0.2, 1, duration: 1).delay(0.1)) {
                lightLevel = 1
            }
        }
        .onMoveCommand { direction in
            guard direction == .left || direction == .right else { return }
            let next = adjacentPage(in: cards, to: activeCard, offset: direction == .left ? -1 : 1)
            hoveredCard = nil
            focusedCard = next
        }
    }

    private func edge(for card: HomeCard) -> HomeCardShape.Edge {
        if cards.count == 1 { return .both }
        if card == cards.first { return .leading }
        if card == cards.last { return .trailing }
        return .none
    }

    private func clock(shape: HomeCardShape) -> some View {
        Button(action: openCalendar) {
            VStack(spacing: 0) {
                Text(date, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
                    .font(.system(size: 58, weight: .medium))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.45)
                    .modifier(GlassInk(illumination: lightLevel, isSelected: activeCard == .clock))
                    .frame(height: 64)

                Text(date.formatted(.dateTime.day().month(.wide).year().locale(AppSettings.displayLocale())))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(height: 14)
            }
            .padding(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .modifier(HomeCardGlass(shape: shape, illumination: lightLevel, isSelected: activeCard == .clock))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .focusable()
        .focused($focusedCard, equals: .clock)
        .focusEffectDisabled()
        .onKeyPress(.return) { openCalendar(); return .handled }
        .onHover { updateHover($0, card: .clock) }
        .accessibilityLabel("Open calendar")
        .accessibilityValue(date.formatted(date: .complete, time: .shortened))
        .accessibilityAddTraits(activeCard == .clock ? .isSelected : [])
        .help("Open calendar")
    }

    private func appButton(_ applet: AppletDestination, shape: HomeCardShape) -> some View {
        let card = HomeCard.applet(applet.id)
        let selected = activeCard == card

        return Button { openApplet(applet.id) } label: {
            applet.icon.image(size: 26)
                .modifier(GlassInk(illumination: lightLevel, isSelected: selected))
                .frame(width: 64)
                .frame(maxHeight: .infinity)
                .modifier(HomeCardGlass(shape: shape, illumination: lightLevel, isSelected: selected))
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .focusable()
        .focused($focusedCard, equals: card)
        .focusEffectDisabled()
        .onHover { updateHover($0, card: card) }
        .onKeyPress(.return) { openApplet(applet.id); return .handled }
        .accessibilityLabel("Open \(applet.title)")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .help("Open \(applet.title)" + (applet.shortcutNumber.map { " · ⌘\($0)" } ?? ""))
    }

    private func updateHover(_ hovering: Bool, card: HomeCard) {
        if hovering { hoveredCard = card }
        else if hoveredCard == card { hoveredCard = nil }
    }
}

/// The clock has a stable identity as applets are added, removed, or reordered.
enum HomeCard: Hashable {
    case clock
    case applet(AppletID)

    func glow(applets: [AppletDestination]) -> BottomGlow {
        let cards = Self.arrangement(for: applets.map(\.id))
        let index = cards.firstIndex(of: self) ?? 0
        let position = cards.count > 1 ? 0.25 + 0.5 * Double(index) / Double(cards.count - 1) : 0.5
        let color: Color
        switch self {
        case .clock: color = HomePalette.clock
        case .applet(let id):
            switch id.rawValue {
            case "spotify": color = HomePalette.spotify
            case "codex": color = HomePalette.codex
            default: color = applets.first { $0.id == id }?.tint ?? HomePalette.clock
            }
        }
        return BottomGlow(color: color, horizontalPosition: position, darkHeight: 16)
    }

    static func arrangement(for ids: [AppletID]) -> [HomeCard] {
        let applets = Array(ids.prefix(3)).map(HomeCard.applet)
        if applets.count == 2 { return [applets[0], .clock, applets[1]] }
        return [.clock] + applets
    }
}

#if DEBUG
#Preview("Home") {
    let layout = NotchLayout(screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982))
    NotchHomeView(layout: layout, date: .now)
        .frame(width: layout.expandedSize.width, height: 112)
        .background(.black)
        .preferredColorScheme(.dark)
}
#endif
