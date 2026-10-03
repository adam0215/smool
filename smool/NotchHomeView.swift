import SwiftUI

struct NotchHomeView: View {
    let layout: NotchLayout
    let date: Date
    let openTab: (NotchTab) -> Void
    var openCalendar: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Card: Hashable {
        case spotify, clock, codex

        var previous: Card { self == .codex ? .clock : .spotify }
        var next: Card { self == .spotify ? .clock : .codex }
    }

    @FocusState private var focusedCard: Card?
    @State private var hoveredCard: Card?
    @State private var lightLevel = 0.0

    private var activeCard: Card { hoveredCard ?? focusedCard ?? .clock }

    var body: some View {
        GlassEffectContainer(spacing: 0) {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    appButton(.spotify)
                    clock
                    appButton(.codex)
                }
                .padding(.horizontal, NotchLayout.contentInset)
                .padding(.bottom, NotchLayout.contentInset)
            }
        }
        .background {
            HomeGlow(
                spotify: activeCard == .spotify ? 1 : 0,
                codex: activeCard == .codex ? 1 : 0,
                darkHeight: 16
            )
            .opacity(lightLevel)
        }
        .animation(reduceMotion ? .linear(duration: 0.12) : .easeInOut(duration: 0.7), value: activeCard)
        .onAppear { focusedCard = .clock }
        .task {
            withAnimation(reduceMotion ? .linear(duration: 0.12) : .timingCurve(0.5, 0, 0.2, 1, duration: 1).delay(0.1)) {
                lightLevel = 1
            }
        }
        .onMoveCommand { direction in
            switch direction {
            case .left:
                let previous = activeCard.previous
                hoveredCard = nil
                focusedCard = previous
            case .right:
                let next = activeCard.next
                hoveredCard = nil
                focusedCard = next
            default: break
            }
        }
    }

    private var clock: some View {
        VStack(spacing: 0) {
            Text(date, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
                .font(.system(size: 58, weight: .medium))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .modifier(GlassInk(illumination: lightLevel, isSelected: activeCard == .clock))
                .frame(height: 64)

            Text(date.formatted(.dateTime.day().month(.wide).year().locale(Locale(identifier: "sv_SE"))))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(height: 14)
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .modifier(HomeCardGlass(shape: HomeCardShape(), illumination: lightLevel, isSelected: activeCard == .clock))
        .contentShape(HomeCardShape())
        .focusable(interactions: .edit)
        .focused($focusedCard, equals: .clock)
        .focusEffectDisabled()
        .onTapGesture {
            hoveredCard = nil
            focusedCard = .clock
            openCalendar()
        }
        .onKeyPress(.return) {
            openCalendar()
            return .handled
        }
        .onHover { updateHover($0, card: .clock) }
        .accessibilityAction(named: "Öppna kalender", openCalendar)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(activeCard == .clock ? .isSelected : [])
    }

    private func appButton(_ app: HomeApp) -> some View {
        let card: Card = app == .spotify ? .spotify : .codex
        let selected = activeCard == card
        let shape = HomeCardShape(app: app)

        return Button {
            openTab(app == .spotify ? .spotify : .codex)
        } label: {
            Image(app.rawValue)
                .renderingMode(.template)
                .frame(width: app == .spotify ? 32 : 24, height: app == .spotify ? 32 : 24)
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
        .onKeyPress(keys: [.return, .space], phases: .down) { _ in
            openTab(app == .spotify ? .spotify : .codex)
            return .handled
        }
        .accessibilityLabel("Öppna \(app.rawValue)")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .help("Öppna \(app.rawValue) · ⌘\(app == .spotify ? "2" : "3")")
    }

    private func updateHover(_ hovering: Bool, card: Card) {
        if hovering { hoveredCard = card }
        else if hoveredCard == card { hoveredCard = nil }
    }
}

#if DEBUG
#Preview("Hem") {
    let layout = NotchLayout(screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982))
    NotchHomeView(layout: layout, date: .now) { _ in }
        .frame(width: layout.expandedSize.width, height: layout.expandedSize.height)
        .background(.black)
        .clipShape(NotchShape(shoulderRadius: 0, bottomRadius: NotchLayout.bottomRadius))
        .preferredColorScheme(.dark)
}
#endif
