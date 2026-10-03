import SwiftUI

struct NotchTabBar: View {
    let presentation: NotchPresentation
    let select: (AppletID) -> Void
    var restoreFocus: () -> Void = {}

    private var visibleApplets: [any Applet] { presentation.registry.tabPage(containing: presentation.selection) }
    private var overflowCount: Int { presentation.registry.applets.count - visibleApplets.count }

    var body: some View {
        NotchHeader(layout: presentation.layout, sideInset: 16) {
            if presentation.showsSettings {
                Button {
                    presentation.showsSettings = false
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.left").font(.system(size: 10, weight: .semibold))
                        Text("Settings").font(.system(size: 11, weight: .medium))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Back · esc")
            } else {
                HStack(spacing: 3) {
                    tabs
                    if overflowCount > 0 {
                        Menu {
                            ForEach(presentation.registry.applets, id: \.id) { applet in
                                Button { select(applet.id) } label: {
                                    Label(applet.title + (presentation.registry.shortcutNumber(for: applet.id).map { "  ⌘\($0)" } ?? ""),
                                          systemImage: presentation.selection == applet.id ? "checkmark" : "circle")
                                }
                            }
                        } label: {
                            Text("+\(overflowCount)").font(.system(size: 11, weight: .medium))
                                .frame(minWidth: 28, minHeight: 28)
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()
                        .help("All applets · ⌃Tab switches applet")
                        .accessibilityLabel("All applets")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        } center: {
            EmptyView()
        } trailing: {
            HStack(spacing: 8) {
                if !presentation.showsSettings, presentation.hostTool == nil, !presentation.displayedApplet.pages.isEmpty { pageIndicators }
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
                Button {
                    restoreFocus()
                    presentation.showTool(.workspaces)
                } label: {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain).focusable(false)
                .foregroundStyle(presentation.hostTool == .workspaces ? .primary : .secondary)
                .accessibilityLabel("Workspaces")
                .help("Workspaces · ⌘⇧W")
                NotchActionsMenu(presentation: presentation, restoreFocus: restoreFocus)
            }
            .fixedSize()
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var tabs: some View {
        GlassEffectContainer(spacing: 4) {
            HStack(spacing: 4) {
                ForEach(visibleApplets, id: \.id) { applet in
                    Button { select(applet.id) } label: {
                        applet.icon.view
                            .foregroundStyle(.white.opacity(presentation.selection == applet.id ? 1 : 0.65))
                            .frame(width: 28, height: 28)
                            .modifier(CardGlass(shape: Circle(), isSelected: presentation.selection == applet.id))
                    }
                    .id(applet.id)
                    .buttonStyle(.plain).focusable(false)
                    .accessibilityLabel(applet.title)
                    .accessibilityAddTraits(presentation.selection == applet.id ? .isSelected : [])
                    .help(applet.title + (presentation.registry.shortcutNumber(for: applet.id).map { " · ⌘\($0)" } ?? ""))
                }
            }
        }
        .frame(height: presentation.layout.navigationHeight)
    }

    private var pageIndicators: some View {
        HStack(spacing: 0) {
            ForEach(presentation.displayedApplet.pages) { page in
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
        .accessibilityLabel("Pages")
    }

}
