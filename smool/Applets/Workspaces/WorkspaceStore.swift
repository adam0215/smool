import Foundation
import Observation

struct SavedWorkspace: Codable, Equatable, Identifiable, Sendable {
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
    @ObservationIgnored private let write: @Sendable ([SavedWorkspace]) async throws -> Void
    @ObservationIgnored private var pending: [(id: UUID, task: Task<Bool, Never>)] = []
    @ObservationIgnored private(set) var failedWriteGeneration = 0

    var hasPendingChanges: Bool { !pending.isEmpty }

    init(url: URL = ActionFile<[SavedWorkspace]>.location("workspaces.json"), launcher: ActionLauncher = .live,
         write: (@Sendable ([SavedWorkspace]) async throws -> Void)? = nil) {
        let file = ActionFile<[SavedWorkspace]>(url: url)
        self.file = file
        self.launcher = launcher
        self.write = write ?? { try await file.save($0) }
        reload()
    }

    func reload() {
        guard pending.isEmpty else { return }
        do {
            let loaded = try file.load(default: [])
            try validate(loaded)
            workspaces = loaded
            canSave = true
            error = nil
        } catch {
            canSave = false
            self.error = "Workspaces could not be loaded. The saved file has been preserved. \(error.localizedDescription)"
        }
    }

    @discardableResult func save(_ workspace: SavedWorkspace) async -> Bool {
        await persist { items in
            var updated = items
            var workspace = workspace
            workspace.name = workspace.name.trimmingCharacters(in: .whitespacesAndNewlines)
            workspace.selectedResourceIDs.formIntersection(workspace.resources.map(\.id))
            if let index = updated.firstIndex(where: { $0.id == workspace.id }) { updated[index] = workspace }
            else { updated.append(workspace) }
            return updated
        }
    }

    @discardableResult func delete(_ id: UUID) async -> Bool {
        await persist { $0.filter { $0.id != id } }
    }

    // Failed mutations stay with their editor or confirmation; draining never retries them.
    func finishPendingChanges() async -> Bool {
        var saved = true
        while !pending.isEmpty {
            let operations = pending.map(\.task)
            for operation in operations {
                if await !operation.value { saved = false }
            }
        }
        return saved
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
            do {
                let destination = try await launcher.perform(resource)
                opened += 1
                if destination != resource.destination {
                    let saved = await persist { items in
                        var updated = items
                        var changed = false
                        for workspace in updated.indices {
                            for index in updated[workspace].resources.indices {
                                let current = updated[workspace].resources[index]
                                guard current.id == resource.id, current.destination == resource.destination else { continue }
                                updated[workspace].resources[index].destination = destination
                                changed = true
                            }
                        }
                        return changed ? updated : nil
                    }
                    if !saved { failures.append("\(resource.name): The updated file reference could not be saved.") }
                }
            } catch { failures.append("\(resource.name): \(error.localizedDescription)") }
        }
        result = "Opened \(opened) of \(resources.count) resources."
        if !failures.isEmpty { error = failures.joined(separator: "\n") }
    }

    private func validate(_ items: [SavedWorkspace]) throws {
        guard Set(items.map(\.id)).count == items.count else { throw ActionFailure(message: "Duplicate workspace IDs.") }
        for item in items {
            guard !item.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ActionFailure(message: "Give the workspace a name.")
            }
            try validateActions(item.resources, allowShortcuts: false)
        }
    }

    private func persist(_ update: @escaping ([SavedWorkspace]) -> [SavedWorkspace]?) async -> Bool {
        let previous = pending.last?.task
        let id = UUID()
        let operation = Task {
            _ = await previous?.value
            defer { pending.removeAll { $0.id == id } }
            guard canSave else {
                failedWriteGeneration += 1
                return false
            }
            guard let items = update(workspaces) else { return true }
            do {
                try validate(items)
                try await write(items)
                workspaces = items
                error = nil
                return true
            } catch {
                failedWriteGeneration += 1
                self.error = "Could not save the workspace. \(error.localizedDescription)"
                return false
            }
        }
        pending.append((id, operation))
        return await operation.value
    }
}
