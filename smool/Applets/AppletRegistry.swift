import Foundation

/// Registration order defines the tab order and Command-number shortcuts.
@MainActor
struct AppletRegistry {
    let applets: [any Applet]

    init(_ applets: [any Applet]) {
        precondition(!applets.isEmpty, "Register at least one applet")
        precondition(Set(applets.map(\.id)).count == applets.count, "Applet IDs must be unique")
        self.applets = applets
    }

    func applet(for id: AppletID) -> (any Applet)? {
        applets.first { $0.id == id }
    }

    func applet(number: Int) -> (any Applet)? {
        guard (1...9).contains(number), applets.indices.contains(number - 1) else { return nil }
        return applets[number - 1]
    }

    func shortcutNumber(for id: AppletID) -> Int? {
        guard let index = applets.firstIndex(where: { $0.id == id }), index < 9 else { return nil }
        return index + 1
    }

    func tabPage(containing id: AppletID) -> [any Applet] {
        let index = applets.firstIndex { $0.id == id } ?? 0
        let start = index / 4 * 4
        return Array(applets[start..<min(start + 4, applets.count)])
    }

    func neighbor(of id: AppletID, offset: Int) -> AppletID {
        cyclingPage(in: applets.map(\.id), to: id, offset: offset)
    }
}
