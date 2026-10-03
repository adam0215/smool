import SwiftUI

struct NotchTabBar: View {
    let presentation: NotchPresentation
    let select: (AppletID) -> Void

    var body: some View {
        NotchHeader(layout: presentation.layout, sideInset: 20) {
            HStack(spacing: 3) {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal) { tabs }
                        .scrollIndicators(.hidden)
                        .onChange(of: presentation.selection, initial: true) { _, selection in
                            proxy.scrollTo(selection, anchor: .center)
                        }
                        .onChange(of: presentation.registry.applets.map(\.id)) { _, _ in
                            proxy.scrollTo(presentation.selection, anchor: .center)
                        }
                }
                Menu {
                    ForEach(presentation.registry.applets, id: \.id) { applet in
                        Button { select(applet.id) } label: {
                            Label(applet.title + (presentation.registry.shortcutNumber(for: applet.id).map { "  ⌘\($0)" } ?? ""),
                                  systemImage: presentation.selection == applet.id ? "checkmark" : "circle")
                        }
                    }
                } label: {
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Alla applets · ⌃Tab byter applet")
                .accessibilityLabel("Alla applets")
            }
            .frame(maxHeight: .infinity)
        } center: {
            EmptyView()
        } trailing: {
            HStack(spacing: 10) {
                if !presentation.activeApplet.pages.isEmpty { pageIndicators }
                TimelineView(.everyMinute) { _ in
                    if presentation.settings.showBattery, let battery = BatteryStatus.current() {
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
            .fixedSize()
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var tabs: some View {
        GlassEffectContainer(spacing: 4) {
            HStack(spacing: 4) {
                ForEach(presentation.registry.applets, id: \.id) { applet in
                    Button { select(applet.id) } label: {
                        applet.icon.view
                            .foregroundStyle(.white.opacity(presentation.selection == applet.id ? 1 : 0.65))
                            .frame(width: 26, height: 26)
                            .modifier(CardGlass(shape: Circle(), isSelected: presentation.selection == applet.id))
                    }
                    .id(applet.id)
                    .buttonStyle(.plain).focusable(false)
                    .accessibilityLabel(applet.title)
                    .accessibilityAddTraits(presentation.selection == applet.id ? .isSelected : [])
                    .help(applet.title)
                }
            }
        }
        .frame(height: presentation.layout.navigationHeight)
    }

    private var pageIndicators: some View {
        HStack(spacing: 0) {
            ForEach(presentation.activeApplet.pages) { page in
                Button(action: page.select) {
                    Capsule().fill(.white.opacity(page.isSelected ? 0.85 : 0.25))
                        .frame(width: page.isSelected ? 10 : 4, height: 4)
                        .frame(width: 14, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain).focusable(false)
                .accessibilityLabel(page.id)
                .accessibilityAddTraits(page.isSelected ? .isSelected : [])
                .help(page.id)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sidor")
    }

}
