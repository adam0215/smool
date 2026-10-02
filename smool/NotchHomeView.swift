import SwiftUI

struct NotchHomeView: View {
    let layout: NotchLayout
    let date: Date
    let battery: BatteryStatus?
    let openApp: (HomeApp) -> Void

    private enum FocusTarget: Hashable {
        case home
        case app(HomeApp)
    }

    @FocusState private var focus: FocusTarget?

    var body: some View {
        VStack(spacing: 8) {
            NotchHeader(layout: layout) {
                Image(systemName: "house.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 16)
                    .background {
                        Capsule().fill(.white.opacity(0.05)
                            .shadow(.inner(color: .white.opacity(0.1), radius: 4, y: -3))
                            .shadow(.inner(color: .black.opacity(0.25), radius: 3, y: 5)))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("Hem")
                    .accessibilityAddTraits(.isSelected)
            } center: {
                EmptyView()
            } trailing: {
                Image(systemName: battery?.symbolName ?? "powerplug.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .accessibilityLabel(battery?.description ?? "Nätansluten")
                    .help(battery?.description ?? "Nätansluten")
            }
            .padding(.horizontal, 4)

            HStack(spacing: 8) {
                appButton(.spotify)

                VStack(spacing: 0) {
                    Text(date, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
                        .font(.system(size: 58, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.25))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .frame(height: 64)

                    Text(date.formatted(.dateTime.day().month(.wide).year().locale(Locale(identifier: "sv_SE"))))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(height: 14)
                }
                .padding(8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background { HomeCardSurface() }
                .accessibilityElement(children: .combine)

                appButton(.codex)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
        .background { HomeGlow() }
        .focusable()
        .focused($focus, equals: .home)
        .focusEffectDisabled()
        .onAppear { focus = .home }
        .onMoveCommand { direction in
            switch direction {
            case .left: focus = .app(.spotify)
            case .right: focus = .app(.codex)
            default: break
            }
        }
    }

    private func appButton(_ app: HomeApp) -> some View {
        Button {
            openApp(app)
        } label: {
            Image(app.rawValue)
                .frame(width: app == .spotify ? 32 : 24, height: app == .spotify ? 32 : 24)
                .frame(width: 64)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(HomeAppButtonStyle(app: app, isFocused: focus == .app(app)))
        .focusable()
        .focused($focus, equals: .app(app))
        .focusEffectDisabled()
        .onKeyPress(keys: [.return, .space]) { _ in
            openApp(app)
            return .handled
        }
        .keyboardShortcut(app == .spotify ? "1" : "2", modifiers: .command)
        .accessibilityLabel("Öppna \(app.rawValue)")
        .help("Öppna \(app.rawValue) · ⌘\(app == .spotify ? "1" : "2")")
    }
}

private struct HomeAppButtonStyle: ButtonStyle {
    let app: HomeApp
    let isFocused: Bool
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                HomeCardSurface(
                    bottomLeadingRadius: app == .spotify ? 56 : 16,
                    bottomTrailingRadius: app == .codex ? 56 : 16,
                    isHighlighted: isHovered || isFocused || configuration.isPressed
                )
            }
            .opacity(configuration.isPressed ? 0.7 : 1)
            .onHover { isHovered = $0 }
    }
}

private struct HomeCardSurface: View {
    var bottomLeadingRadius: CGFloat = 16
    var bottomTrailingRadius: CGFloat = 16
    var isHighlighted = false

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 16,
            bottomLeadingRadius: bottomLeadingRadius,
            bottomTrailingRadius: bottomTrailingRadius,
            topTrailingRadius: 16,
            style: .circular
        )
    }

    var body: some View {
        shape.fill(.white.opacity(isHighlighted ? 0.1 : 0.05))
            .overlay {
                shape.fill(.white.shadow(.inner(color: .black.opacity(0.24), radius: 6, y: 8)))
                    .blendMode(.multiply)
            }
            .overlay {
                shape.fill(.black.shadow(.inner(color: .white.opacity(0.08), radius: 6, y: -8)))
                    .blendMode(.screen)
            }
            .overlay {
                shape.strokeBorder(.white.opacity(isHighlighted ? 0.25 : 0.06), lineWidth: 1)
            }
    }
}

private struct HomeGlow: View {
    private let blue = Color(red: 0, green: 145 / 255, blue: 1)

    var body: some View {
        Canvas { context, size in
            let bounds = CGRect(origin: .zero, size: size)
            context.fill(Path(bounds), with: .linearGradient(
                Gradient(stops: [
                    .init(color: .black.opacity(0.2), location: 0.80263),
                    .init(color: blue.opacity(0.2), location: 1)
                ]),
                startPoint: .zero,
                endPoint: CGPoint(x: 0, y: size.height)
            ))

            // Ellipse radii and layer opacity from the two Figma glow fills.
            for (color, opacity, radius) in [
                (blue, 0.4, CGSize(width: 314.17, height: 108.5)),
                (Color.white, 0.2, CGSize(width: 159.26, height: 55))
            ] {
                var glow = context
                glow.translateBy(x: size.width / 2, y: size.height)
                glow.scaleBy(x: radius.width, y: radius.height)
                let area = CGRect(x: -size.width / 2 / radius.width, y: -size.height / radius.height,
                                  width: size.width / radius.width, height: size.height / radius.height)
                glow.fill(Path(area), with: .radialGradient(
                    Gradient(colors: [color.opacity(opacity), .black.opacity(opacity)]),
                    center: .zero, startRadius: 0, endRadius: 1
                ))
            }
        }
        .allowsHitTesting(false)
    }
}

#if DEBUG
#Preview("Hem") {
    let layout = NotchLayout(screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982))
    NotchHomeView(layout: layout, date: .now, battery: BatteryStatus(percentage: 75, isCharging: false)) { _ in }
        .frame(width: layout.expandedSize.width, height: layout.expandedSize.height)
        .background(.black)
        .clipShape(NotchShape(shoulderRadius: 0, bottomRadius: 64))
        .preferredColorScheme(.dark)
}
#endif
