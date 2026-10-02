import SwiftUI

struct NotchHomeView: View {
    let layout: NotchLayout
    let date: Date
    let battery: BatteryStatus?
    let openApp: (HomeApp) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum FocusTarget: Hashable {
        case home
        case app(HomeApp)
    }

    @FocusState private var focus: FocusTarget?
    @State private var hoveredApp: HomeApp?
    @State private var lightLevel = 0.0

    private var activeApp: HomeApp? {
        if let hoveredApp { return hoveredApp }
        if case .app(let app) = focus { return app }
        return nil
    }

    private var lightColor: Color { HomeGlow.color(for: activeApp) }

    var body: some View {
        GlassEffectContainer(spacing: 0) {
            VStack(spacing: 8) {
                header

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
                spotify: activeApp == .spotify ? 1 : 0,
                codex: activeApp == .codex ? 1 : 0,
                darkHeight: layout.headerSize.height + 16
            )
            .opacity(lightLevel)
        }
        .animation(reduceMotion ? .linear(duration: 0.12) : .easeInOut(duration: 0.7), value: activeApp)
        .focusable()
        .focused($focus, equals: .home)
        .focusEffectDisabled()
        .onAppear { focus = .home }
        .task {
            withAnimation(reduceMotion ? .linear(duration: 0.12) : .easeOut(duration: 0.95).delay(0.08)) {
                lightLevel = 1
            }
        }
        .onMoveCommand { direction in
            switch direction {
            case .left:
                hoveredApp = nil
                focus = .app(.spotify)
            case .right:
                hoveredApp = nil
                focus = .app(.codex)
            default: break
            }
        }
    }

    private var header: some View {
        NotchHeader(layout: layout) {
            Button {
                hoveredApp = nil
                focus = .home
            } label: {
                Image(systemName: "house.fill")
                    .font(.system(size: 10))
                    .modifier(GlassInk(tint: lightColor, illumination: lightLevel))
                    .frame(width: 24, height: 16)
                    .glassEffect(.clear.interactive(), in: .capsule)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("0", modifiers: .command)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel("Hem")
            .accessibilityAddTraits(.isSelected)
        } center: {
            EmptyView()
        } trailing: {
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
            .help(battery?.description ?? "Nätansluten")
        }
        .padding(.horizontal, 4)
    }

    private var clock: some View {
        VStack(spacing: 0) {
            Text(date, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
                .font(.system(size: 58, weight: .medium))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .modifier(GlassInk(tint: lightColor, illumination: lightLevel))
                .frame(height: 64)

            Text(date.formatted(.dateTime.day().month(.wide).year().locale(Locale(identifier: "sv_SE"))))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(height: 14)
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .modifier(HomeCardGlass(shape: HomeCardShape(), tint: lightColor, illumination: lightLevel))
        .accessibilityElement(children: .combine)
    }

    private func appButton(_ app: HomeApp) -> some View {
        let selected = activeApp == app
        let shape = HomeCardShape(app: app)

        return Button {
            openApp(app)
        } label: {
            Image(app.rawValue)
                .renderingMode(.template)
                .frame(width: app == .spotify ? 32 : 24, height: app == .spotify ? 32 : 24)
                .modifier(GlassInk(tint: lightColor, illumination: lightLevel, isSelected: selected))
                .frame(width: 64)
                .frame(maxHeight: .infinity)
                .modifier(HomeCardGlass(shape: shape, tint: lightColor, illumination: lightLevel, isSelected: selected))
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .focusable()
        .focused($focus, equals: .app(app))
        .focusEffectDisabled()
        .onHover { hovering in
            if hovering { hoveredApp = app }
            else if hoveredApp == app { hoveredApp = nil }
        }
        .onKeyPress(keys: [.return, .space]) { _ in
            openApp(app)
            return .handled
        }
        .keyboardShortcut(app == .spotify ? "1" : "2", modifiers: .command)
        .accessibilityLabel("Öppna \(app.rawValue)")
        .help("Öppna \(app.rawValue) · ⌘\(app == .spotify ? "1" : "2")")
    }


}

#if DEBUG
#Preview("Hem") {
    let layout = NotchLayout(screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982))
    NotchHomeView(layout: layout, date: .now, battery: BatteryStatus(percentage: 75, isCharging: false)) { _ in }
        .frame(width: layout.expandedSize.width, height: layout.expandedSize.height)
        .background(.black)
        .clipShape(NotchShape(shoulderRadius: 0, bottomRadius: NotchLayout.bottomRadius))
        .preferredColorScheme(.dark)
}
#endif
