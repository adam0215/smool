import Foundation
import Observation

@MainActor @Observable
final class QuickActionStore {
    private(set) var actions: [SavedAction] = []
    private(set) var canSave = true
    private(set) var runningID: UUID?
    var error: String?
    var result: String?
    private let file: ActionFile<[SavedAction]>
    private let launcher: ActionLauncher

    init(url: URL = ActionFile<[SavedAction]>.location("quick-actions.json"), launcher: ActionLauncher = .live) {
        file = ActionFile(url: url)
        self.launcher = launcher
        reload()
    }

    func reload() {
        do {
            let loaded = try file.load(default: [])
            try validateActions(loaded, allowShortcuts: true)
            actions = loaded
            canSave = true
            error = nil
        } catch {
            canSave = false
            self.error = "Quick actions could not be loaded. The saved file has been preserved. \(error.localizedDescription)"
        }
    }

    @discardableResult func save(_ action: SavedAction) -> Bool {
        var updated = actions
        if let index = updated.firstIndex(where: { $0.id == action.id }) { updated[index] = action }
        else { updated.append(action) }
        return persist(updated)
    }

    func delete(_ id: UUID) { _ = persist(actions.filter { $0.id != id }) }

    func move(_ id: UUID, offset: Int) {
        guard let index = actions.firstIndex(where: { $0.id == id }), actions.indices.contains(index + offset) else { return }
        var updated = actions
        updated.swapAt(index, index + offset)
        _ = persist(updated)
    }

    func run(_ action: SavedAction) async {
        guard runningID == nil else { return }
        runningID = action.id
        error = nil
        result = nil
        defer { runningID = nil }
        do {
            try await launcher.perform(action)
            result = "\(action.name) completed."
        } catch { self.error = "\(action.name): \(error.localizedDescription)" }
    }

    private func persist(_ items: [SavedAction]) -> Bool {
        guard canSave else { return false }
        do {
            try validateActions(items, allowShortcuts: true)
            try file.save(items)
            actions = items
            error = nil
            return true
        } catch {
            self.error = "Could not save the quick action. \(error.localizedDescription)"
            return false
        }
    }
}
