import Foundation
import Observation

@MainActor
@Observable
final class AppSettings {
    var demoNotchEnabled: Bool { didSet { saveIfChanged(from: oldValue, to: demoNotchEnabled) } }
    var showBattery: Bool { didSet { saveIfChanged(from: oldValue, to: showBattery) } }
    var showTimerStatus: Bool { didSet { saveIfChanged(from: oldValue, to: showTimerStatus) } }
    var showCodexStatus: Bool { didSet { saveIfChanged(from: oldValue, to: showCodexStatus) } }

    private(set) var disabledAppletIDs: Set<AppletID>
    private(set) var appletOrder: [AppletID]
    private(set) var frontAppletIDs: [AppletID]

    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private let defaults: UserDefaults
    private var frontIsConfigured: Bool

    private let home = AppletID(rawValue: "home")

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        demoNotchEnabled = defaults.object(forKey: "demoNotchEnabled") as? Bool ?? true
        showBattery = defaults.object(forKey: "showBattery") as? Bool ?? true
        showTimerStatus = defaults.object(forKey: "showTimerStatus") as? Bool ?? true
        showCodexStatus = defaults.object(forKey: "showCodexStatus") as? Bool ?? true
        let disabled = Set(Self.readIDs("disabledAppletIDs", from: defaults).filter { $0.rawValue != "home" })
        disabledAppletIDs = disabled
        appletOrder = Self.readIDs("appletOrder", from: defaults)
        frontIsConfigured = defaults.object(forKey: "frontAppletIDs") != nil
        frontAppletIDs = Array(Self.readIDs("frontAppletIDs", from: defaults)
            .filter { $0.rawValue != "home" && !$0.isHostTool && !disabled.contains($0) }.prefix(3))
    }

    func isEnabled(_ id: AppletID) -> Bool {
        id == home || !disabledAppletIDs.contains(id)
    }

    /// Includes disabled applets so settings can show and re-enable them.
    func orderedIDs(in registered: [AppletID]) -> [AppletID] {
        let available = Set(registered)
        var seen = Set<AppletID>()
        return ([home] + appletOrder + registered).filter {
            available.contains($0) && !$0.isHostTool && seen.insert($0).inserted
        }
    }

    /// An absent saved preference defaults to two applets; an explicitly empty one stays empty.
    func frontIDs(in registered: [AppletID]) -> [AppletID] {
        let selected = Set(frontAppletIDs)
        let candidates = orderedIDs(in: registered).filter { !frontIsConfigured || selected.contains($0) }
        let limit = frontIsConfigured ? 3 : 2
        return Array(candidates.filter { $0 != home && isEnabled($0) }.prefix(limit))
    }

    func setEnabled(_ enabled: Bool, for id: AppletID) {
        guard id != home, !id.isHostTool, isEnabled(id) != enabled else { return }
        if enabled {
            disabledAppletIDs.remove(id)
        } else {
            disabledAppletIDs.insert(id)
            frontAppletIDs.removeAll { $0 == id }
        }
        save()
    }

    func move(_ id: AppletID, offset: Int, in registered: [AppletID] = []) {
        var ordered = orderedIDs(in: registered.isEmpty ? appletOrder : registered)
        guard id != home, let index = ordered.firstIndex(of: id) else { return }
        let destination = index + offset
        guard ordered.indices.contains(destination), ordered[destination] != home, destination != index else { return }
        ordered.remove(at: index)
        ordered.insert(id, at: destination)
        let available = Set(ordered)
        appletOrder = ordered + appletOrder.filter { !available.contains($0) }
        save()
    }

    func setFront(_ selected: Bool, for id: AppletID, in registered: [AppletID] = []) {
        guard id != home, !id.isHostTool, !selected || isEnabled(id) else { return }
        var selection = frontIsConfigured ? frontAppletIDs : frontIDs(in: registered)
        if selected {
            guard !selection.contains(id), selection.count < 3 else { return }
            selection.append(id)
        } else {
            selection.removeAll { $0 == id }
        }
        guard !frontIsConfigured || selection != frontAppletIDs else { return }
        frontIsConfigured = true
        frontAppletIDs = selection
        save()
    }

    private func saveIfChanged(from oldValue: Bool, to newValue: Bool) {
        if oldValue != newValue { save() }
    }

    private func save() {
        defaults.set(demoNotchEnabled, forKey: "demoNotchEnabled")
        defaults.set(showBattery, forKey: "showBattery")
        defaults.set(showTimerStatus, forKey: "showTimerStatus")
        defaults.set(showCodexStatus, forKey: "showCodexStatus")
        defaults.set(disabledAppletIDs.map(\.rawValue).sorted(), forKey: "disabledAppletIDs")
        defaults.set(appletOrder.map(\.rawValue), forKey: "appletOrder")
        if frontIsConfigured {
            defaults.set(frontAppletIDs.map(\.rawValue), forKey: "frontAppletIDs")
        }
        onChange?()
    }

    static func displayLocale(for locale: Locale = .current) -> Locale {
        var components = Locale.Components(languageCode: .english, languageRegion: locale.region)
        components.hourCycle = locale.hourCycle
        components.firstDayOfWeek = locale.firstDayOfWeek
        components.calendar = locale.calendar.identifier
        components.numberingSystem = locale.numberingSystem
        return Locale(components: components)
    }

    private static func readIDs(_ key: String, from defaults: UserDefaults) -> [AppletID] {
        var seen = Set<String>()
        return (defaults.stringArray(forKey: key) ?? [])
            .filter { !$0.isEmpty && seen.insert($0).inserted }
            .map(AppletID.init(rawValue:))
    }
}
