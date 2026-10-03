import Foundation

/// Registration order defines the tab order and Command-number shortcuts.
@MainActor
struct AppletRegistry {
    let applets: [any Applet]

    init(_ applets: [any Applet]) {
        precondition(!applets.isEmpty, "Register at least one applet")
        precondition(Set(applets.map(\.id)).count == applets.count, "Applet IDs must be unique")
        let shortcuts = applets.compactMap(\.homeShortcut)
        precondition(Set(shortcuts).count == shortcuts.count, "Home shortcuts must be unique")
        self.applets = applets
    }

    func applet(for id: AppletID) -> (any Applet)? {
        applets.first { $0.id == id }
    }

    func applet(for shortcut: HomeApp) -> (any Applet)? {
        applets.first { $0.homeShortcut == shortcut }
    }

    func applet(number: Int) -> (any Applet)? {
        guard (1...9).contains(number), applets.indices.contains(number - 1) else { return nil }
        return applets[number - 1]
    }

    func shortcutNumber(for shortcut: HomeApp) -> Int? {
        guard let index = applets.firstIndex(where: { $0.homeShortcut == shortcut }), index < 9 else { return nil }
        return index + 1
    }

    func neighbor(of id: AppletID, offset: Int) -> AppletID {
        cyclingPage(in: applets.map(\.id), to: id, offset: offset)
    }
}
