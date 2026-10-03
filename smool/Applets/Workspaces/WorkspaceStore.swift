import Foundation
import Observation

struct SavedWorkspace: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var resources: [SavedAction] = []
    var selectedResourceIDs: Set<UUID> = []
}

@MainActor @Observable
final class WorkspaceStore {
    private(set) var workspaces: [SavedWorkspace] = []
    private(set) var canSave = true
    var error: String?
    private(set) var isOpening = false
    var result: String?
    private let file: ActionFile<[SavedWorkspace]>
    private let launcher: ActionLauncher

    init(url: URL = ActionFile<[SavedWorkspace]>.location("workspaces.json"), launcher: ActionLauncher = .live) {
        file = ActionFile(url: url)
        self.launcher = launcher
        reload()
    }

    func reload() {
        do {
            let loaded = try file.load(default: [])
            try validate(loaded)
            workspaces = loaded
            canSave = true
            error = nil
        } catch {
            canSave = false
            self.error = "Kunde inte läsa arbetsytorna. Filen har bevarats. \(error.localizedDescription)"
        }
    }

    @discardableResult func save(_ workspace: SavedWorkspace) -> Bool {
        var updated = workspaces
        var workspace = workspace
        workspace.name = workspace.name.trimmingCharacters(in: .whitespacesAndNewlines)
        workspace.selectedResourceIDs.formIntersection(workspace.resources.map(\.id))
        if let index = updated.firstIndex(where: { $0.id == workspace.id }) { updated[index] = workspace }
        else { updated.append(workspace) }
        return persist(updated)
    }

    @discardableResult func delete(_ id: UUID) -> Bool {
        persist(workspaces.filter { $0.id != id })
    }

    func open(_ resources: [SavedAction]) async {
        guard !isOpening, !resources.isEmpty else { return }
        isOpening = true
        error = nil
        result = nil
        defer { isOpening = false }
        var failures: [String] = []
        var opened = 0
        for resource in resources {
            do { try await launcher.perform(resource); opened += 1 }
            catch { failures.append("\(resource.name): \(error.localizedDescription)") }
        }
        result = "Öppnade \(opened) av \(resources.count) resurser."
        if !failures.isEmpty { error = failures.joined(separator: "\n") }
    }

    private func validate(_ items: [SavedWorkspace]) throws {
        guard Set(items.map(\.id)).count == items.count else { throw ActionFailure(message: "Dubbla arbetsyte-ID:n.") }
        for item in items {
            guard !item.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ActionFailure(message: "Ge arbetsytan ett namn.")
            }
            try validateActions(item.resources, allowShortcuts: false)
        }
    }

    private func persist(_ items: [SavedWorkspace]) -> Bool {
        guard canSave else { return false }
        do {
            try validate(items)
            try file.save(items)
            workspaces = items
            error = nil
            return true
        } catch {
            self.error = "Kunde inte spara arbetsytan. \(error.localizedDescription)"
            return false
        }
    }
}
