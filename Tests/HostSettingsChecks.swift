import SwiftUI

@MainActor
private final class FixtureApplet: Applet {
    let id: AppletID
    let title: String
    let icon = AppletIcon.symbol("square")
    let tint = Color.blue
    let contentHeight: CGFloat = 120
    var deactivations = 0

    init(_ name: String) {
        id = AppletID(rawValue: name)
        title = name
    }

    func makeView(context: AppletContext, artwork: NSImage?) -> AnyView { AnyView(Text(title)) }
    func deactivate() { deactivations += 1 }
}

@main
struct HostSettingsChecks {
    @MainActor static func main() {
        _ = NSApplication.shared
        let suite = "smool.host-checks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let applets = (["home"] + (1...10).map { "fixture-\($0)" }).map(FixtureApplet.init)
        let ids = applets.map(\.id)
        let settings = AppSettings(defaults: defaults)
        let presentation = NotchPresentation(registry: AppletRegistry(applets), settings: settings)
        var changes = 0
        settings.onChange = {
            changes += 1
            presentation.reconcileSettings()
        }

        precondition(settings.frontIDs(in: ids) == Array(ids[1...2]))
        precondition(settings.orderedIDs(in: ids) == ids)
        precondition(presentation.frontApplets.map(\.id) == Array(ids[1...2]))
        settings.setEnabled(false, for: .home)
        precondition(settings.isEnabled(.home) && changes == 0)

        presentation.select(ids[1])
        settings.setEnabled(false, for: ids[1])
        precondition(presentation.selection == .home && applets[1].deactivations == 1)
        precondition(presentation.registry.applet(number: 2)?.id == ids[2])
        precondition(!presentation.frontApplets.contains { $0.id == ids[1] })
        settings.setEnabled(true, for: ids[1])
        settings.move(ids[10], offset: -9, in: ids)
        precondition(presentation.registry.applet(number: 2)?.id == ids[10])
        precondition(presentation.registry.applet(number: 10) == nil)
        precondition(presentation.registry.neighbor(of: .home, offset: -1) == ids[9])
        var visited = Set<AppletID>()
        var current = AppletID.home
        for _ in 0..<ids.count {
            visited.insert(current)
            current = presentation.registry.neighbor(of: current, offset: 1)
        }
        precondition(visited == Set(ids) && current == .home)

        for id in settings.frontIDs(in: ids) { settings.setFront(false, for: id, in: ids) }
        precondition(settings.frontIDs(in: ids).isEmpty)
        precondition(AppSettings(defaults: defaults).frontIDs(in: ids).isEmpty)
        for id in ids[1...4] { settings.setFront(true, for: id, in: ids) }
        precondition(settings.frontIDs(in: ids) == Array(ids[1...3]))
        settings.move(ids[3], offset: -1, in: ids)
        precondition(settings.frontIDs(in: ids) == [ids[1], ids[3], ids[2]])
        settings.demoNotchEnabled = false
        settings.showBattery = false
        settings.showTimerStatus = false
        settings.showCodexStatus = false
        let reloaded = AppSettings(defaults: defaults)
        precondition(!reloaded.demoNotchEnabled && !reloaded.showBattery)
        precondition(!reloaded.showTimerStatus && !reloaded.showCodexStatus)
        precondition(reloaded.frontIDs(in: ids) == settings.frontIDs(in: ids))
        precondition(reloaded.orderedIDs(in: ids) == settings.orderedIDs(in: ids))
        precondition(reloaded.frontIDs(in: Array(ids.prefix(2))) == [ids[1]])
        precondition(reloaded.frontIDs(in: ids).count == 3, "Unavailable applets retain their saved selection")
        settings.setEnabled(false, for: ids[3])
        precondition(!settings.frontIDs(in: ids).contains(ids[3]))

        precondition(HomeCard.arrangement(for: []) == [.clock])
        precondition(HomeCard.arrangement(for: [ids[1]]) == [.clock, .applet(ids[1])])
        precondition(HomeCard.arrangement(for: Array(ids[1...2])) == [.applet(ids[1]), .clock, .applet(ids[2])])
        precondition(HomeCard.arrangement(for: Array(ids[1...4])) == [.clock, .applet(ids[1]), .applet(ids[2]), .applet(ids[3])])

        defaults.set(["home", "fixture-1", "fixture-1", "", "fixture-2", "fixture-3", "fixture-4"], forKey: "frontAppletIDs")
        defaults.set(["home", "fixture-1"], forKey: "disabledAppletIDs")
        let repaired = AppSettings(defaults: defaults)
        precondition(repaired.isEnabled(.home))
        precondition(repaired.frontAppletIDs == Array(ids[2...4]))
        let swedish = Locale(identifier: "sv_SE")
        let english = AppSettings.displayLocale(for: swedish)
        precondition(english.language.languageCode == .english)
        precondition(english.region == swedish.region && english.hourCycle == swedish.hourCycle)
        var clockFormat = Date.FormatStyle.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(english)
        clockFormat.timeZone = TimeZone(secondsFromGMT: 0)!
        let evening = Date(timeIntervalSince1970: 22 * 3600 + 38 * 60)
        precondition(evening.formatted(clockFormat) == "22:38", "English labels must preserve the user's 24-hour clock.")

        let panel = NotchPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        precondition(!panel.canBecomeKey)
        panel.allowsKeyboardFocus = true
        precondition(panel.canBecomeKey)
        panel.allowsKeyboardFocus = false
        precondition(!panel.canBecomeKey)
        let controller = NotchPanelController()
        controller.restoreFocus()
        precondition(!controller.isOpen, "A late popover dismissal cannot reopen the panel.")
        controller.stop()

        presentation.showsSettings = true
        presentation.changeSettingsSection(.general)
        precondition(presentation.contentHeight == 360)
        precondition(presentation.handleSettingsKey(49, modifiers: [], characters: " "))
        precondition(settings.demoNotchEnabled)
        precondition(presentation.handleSettingsKey(48, modifiers: .shift, characters: nil))
        precondition(presentation.settingsRow == 3)
        precondition(presentation.handleSettingsKey(48, modifiers: [], characters: nil))
        precondition(presentation.settingsRow == 0)
        precondition(presentation.handleSettingsKey(124, modifiers: [], characters: nil))
        precondition(presentation.settingsSection == .applets)
        presentation.settingsRow = 1
        let selected = presentation.settingsAppletIDs[1]
        let wasEnabled = settings.isEnabled(selected)
        precondition(presentation.handleSettingsKey(36, modifiers: [], characters: nil))
        precondition(settings.isEnabled(selected) != wasEnabled)
        settings.setEnabled(true, for: selected)
        precondition(presentation.handleSettingsKey(125, modifiers: .command, characters: nil))
        precondition(presentation.settingsAppletIDs[presentation.settingsRow] == selected)
        precondition(!presentation.handleSettingsKey(1, modifiers: .command, characters: "s"))
        presentation.select(presentation.selection)
        precondition(!presentation.showsSettings, "Selecting the current applet returns from settings.")

        defaults.set(["missing-1", "missing-2", "missing-3"], forKey: "frontAppletIDs")
        let missing = NotchPresentation(registry: AppletRegistry(applets), settings: AppSettings(defaults: defaults))
        missing.changeSettingsSection(.applets)
        missing.settingsRow = missing.settingsRowCount - 1
        missing.activateSettingsRow()
        precondition(missing.settings.frontAppletIDs.count == 2)
        precondition(missing.settingsRow < missing.settingsRowCount)
        missing.settingsRow = missing.settingsAppletIDs.firstIndex(of: ids[2])!
        missing.toggleSettingsFront()
        precondition(missing.settings.frontIDs(in: ids).contains(ids[2]))

        print("Passed: persistence, normalization, 0–3 front applets, generic ordering, disabling, and 11-app keyboard navigation.")
    }
}
