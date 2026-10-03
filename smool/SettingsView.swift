import SwiftUI

enum SettingsSection: String, CaseIterable {
    case general = "General"
    case applets = "Applets"
}

extension NotchPresentation {
    var settingsAppletIDs: [AppletID] {
        let available = registeredApplets.applets.map(\.id)
        return settings.orderedIDs(in: available) + settings.frontAppletIDs.filter { !available.contains($0) }
    }

    var settingsRowCount: Int { settingsSection == .general ? 4 : settingsAppletIDs.count }

    func changeSettingsSection(_ section: SettingsSection) {
        settingsSection = section
        settingsRow = 0
    }

    func activateSettingsRow() {
        if settingsSection == .general {
            switch settingsRow {
            case 0: settings.demoNotchEnabled.toggle()
            case 1: settings.showBattery.toggle()
            case 2: settings.showTimerStatus.toggle()
            case 3: settings.showCodexStatus.toggle()
            default: break
            }
        } else if settingsAppletIDs.indices.contains(settingsRow) {
            let id = settingsAppletIDs[settingsRow]
            if registeredApplets.applet(for: id) == nil {
                settings.setFront(false, for: id, in: registeredApplets.applets.map(\.id))
                settingsRow = min(settingsRow, settingsRowCount - 1)
            } else {
                settings.setEnabled(!settings.isEnabled(id), for: id)
            }
        }
    }

    func toggleSettingsFront() {
        guard settingsSection == .applets, settingsAppletIDs.indices.contains(settingsRow) else { return }
        let id = settingsAppletIDs[settingsRow]
        let ids = registeredApplets.applets.map(\.id)
        let selected = settings.frontAppletIDs.contains(id) || settings.frontIDs(in: ids).contains(id)
        settings.setFront(!selected, for: id, in: ids)
        settingsRow = min(settingsRow, settingsRowCount - 1)
    }

    func moveSettingsApplet(_ offset: Int) {
        guard settingsSection == .applets, settingsAppletIDs.indices.contains(settingsRow) else { return }
        let id = settingsAppletIDs[settingsRow]
        settings.move(id, offset: offset, in: registeredApplets.applets.map(\.id))
        settingsRow = settingsAppletIDs.firstIndex(of: id) ?? 0
    }

    func handleSettingsKey(_ key: UInt16, modifiers: NSEvent.ModifierFlags, characters: String?) -> Bool {
        guard showsSettings, capturedSelection == nil else { return false }
        let modifiers = modifiers.intersection([.command, .control, .option, .shift])
        if modifiers == .command, key == 125 || key == 126 {
            moveSettingsApplet(key == 126 ? -1 : 1)
            return true
        }
        if key == 48, modifiers.isEmpty || modifiers == .shift {
            settingsRow = (settingsRow + (modifiers == .shift ? -1 : 1) + settingsRowCount) % settingsRowCount
            return true
        }
        guard modifiers.isEmpty else { return false }
        switch key {
        case 123: changeSettingsSection(.general)
        case 124: changeSettingsSection(.applets)
        case 125: settingsRow = min(settingsRow + 1, settingsRowCount - 1)
        case 126: settingsRow = max(settingsRow - 1, 0)
        case 36, 49: activateSettingsRow()
        default:
            if characters?.lowercased() == "f", settingsSection == .applets { toggleSettingsFront() }
            else { return false }
        }
        return true
    }
}

struct SettingsView: View {
    let presentation: NotchPresentation

    private var settings: AppSettings { presentation.settings }
    private var ids: [AppletID] { presentation.settingsAppletIDs }
    private var frontIDs: [AppletID] { settings.frontIDs(in: presentation.registeredApplets.applets.map(\.id)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 20) {
                ForEach(SettingsSection.allCases, id: \.self) { section in
                    Button { presentation.changeSettingsSection(section) } label: {
                        Text(section.rawValue)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(presentation.settingsSection == section ? .white : .white.opacity(0.4))
                            .padding(.vertical, 8)
                            .overlay(alignment: .bottom) {
                                if presentation.settingsSection == section {
                                    Capsule().fill(.white).frame(height: 2)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(presentation.settingsSection == section ? .isSelected : [])
                }
                Spacer()
                Text("← →").font(.system(size: 11)).foregroundStyle(.tertiary)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    if presentation.settingsSection == .general { general }
                    else { applets }
                }
                .scrollIndicators(.hidden)
                .onChange(of: presentation.settingsRow) { _, row in proxy.scrollTo(row, anchor: .center) }
                .onChange(of: presentation.settingsSection) { _, _ in proxy.scrollTo(0, anchor: .top) }
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(presentation.settingsSection == .general
                     ? "↑ ↓ Select    Space Toggle    esc Back"
                     : "↑ ↓ Select    Space Enable    F Pin    ⌘↑ ↓ Reorder")
                Text(presentation.settingsSection == .general
                     ? "⌃⌥Space Open smool    ⌘1–9 Applets    ⌘, Settings"
                     : "Pin up to three applets to Home. The clock stays visible.")
                    .foregroundStyle(.tertiary)
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 32)
        .padding(.top, 4)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var general: some View {
        VStack(spacing: 2) {
            settingRow(0, title: "Demo notch", detail: "Show a notch on displays without one", value: settings.demoNotchEnabled)
            settingRow(1, title: "Battery", detail: "Show battery level in the header", value: settings.showBattery)
            settingRow(2, title: "Timer status", detail: "Show active timers while smool is closed", value: settings.showTimerStatus)
            settingRow(3, title: "Codex status", detail: "Show when Codex needs your attention", value: settings.showCodexStatus)
        }
    }

    private func settingRow(_ index: Int, title: String, detail: String, value: Bool) -> some View {
        Button {
            presentation.settingsRow = index
            presentation.activateSettingsRow()
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 12, weight: .medium))
                    Text(detail).font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: value ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(value ? .white : .white.opacity(0.25))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(.white.opacity(presentation.settingsRow == index ? 0.09 : 0), in: RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .id(index)
        .accessibilityLabel(title)
        .accessibilityValue(value ? "On" : "Off")
        .accessibilityHint(detail)
        .accessibilityAddTraits(presentation.settingsRow == index ? .isSelected : [])
    }

    private var applets: some View {
        VStack(spacing: 2) {
            ForEach(Array(ids.enumerated()), id: \.element) { index, id in
                if let applet = presentation.registeredApplets.applet(for: id) {
                    appletRow(applet, index: index)
                } else {
                    Button {
                        presentation.settingsRow = index
                        presentation.activateSettingsRow()
                    } label: {
                        HStack {
                            Text(id.rawValue).lineLimit(1)
                            Spacer()
                            Text("Unavailable · Remove pin").foregroundStyle(.secondary)
                        }
                        .font(.system(size: 11))
                        .padding(12)
                        .background(.white.opacity(presentation.settingsRow == index ? 0.09 : 0),
                                    in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .id(index)
                    .accessibilityLabel("Remove unavailable applet from Home: \(id.rawValue)")
                }
            }
        }
    }

    private func appletRow(_ applet: any Applet, index: Int) -> some View {
        let enabled = settings.isEnabled(applet.id)
        let pinned = frontIDs.contains(applet.id)
        let isHome = applet.id == .home

        return HStack(spacing: 10) {
            Button {
                presentation.settingsRow = index
                presentation.activateSettingsRow()
            } label: {
                HStack(spacing: 10) {
                    applet.icon.view.frame(width: 18)
                    Text(applet.title).font(.system(size: 12, weight: .medium))
                    Spacer()
                    Text(isHome ? "Always on" : enabled ? "On" : "Off")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .accessibilityLabel(applet.title)
            .accessibilityValue(enabled ? "Enabled" : "Disabled")
            .disabled(isHome)

            if !isHome {
                Button {
                    presentation.settingsRow = index
                    presentation.moveSettingsApplet(-1)
                } label: { Image(systemName: "chevron.up").frame(width: 20, height: 26) }
                .disabled(index <= (ids.first == .home ? 1 : 0))
                .accessibilityLabel("Move \(applet.title) up")

                Button {
                    presentation.settingsRow = index
                    presentation.moveSettingsApplet(1)
                } label: { Image(systemName: "chevron.down").frame(width: 20, height: 26) }
                .disabled(index == ids.count - 1)
                .accessibilityLabel("Move \(applet.title) down")

                Button {
                    presentation.settingsRow = index
                    presentation.toggleSettingsFront()
                } label: {
                    Image(systemName: pinned ? "pin.fill" : "pin")
                        .foregroundStyle(pinned ? .white : .white.opacity(0.35))
                        .frame(width: 24, height: 26)
                }
                .disabled(!enabled || (!pinned && frontIDs.count + unavailableFrontCount >= 3))
                .accessibilityLabel(pinned ? "Unpin \(applet.title) from Home" : "Pin \(applet.title) to Home")
            }
        }
        .buttonStyle(.plain)
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(enabled ? .white : .white.opacity(0.45))
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(.white.opacity(presentation.settingsRow == index ? 0.09 : 0), in: RoundedRectangle(cornerRadius: 12))
        .id(index)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(presentation.settingsRow == index ? .isSelected : [])
    }

    private var unavailableFrontCount: Int { settings.frontAppletIDs.filter { presentation.registeredApplets.applet(for: $0) == nil }.count }
}
