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
    @ObservationIgnored private let write: @Sendable ([SavedAction]) async throws -> Void
    @ObservationIgnored private var pending: [(id: UUID, task: Task<Bool, Never>)] = []
    @ObservationIgnored private(set) var failedWriteGeneration = 0

    var hasPendingChanges: Bool { !pending.isEmpty }

    init(url: URL = ActionFile<[SavedAction]>.location("quick-actions.json"), launcher: ActionLauncher = .live,
         write: (@Sendable ([SavedAction]) async throws -> Void)? = nil) {
        let file = ActionFile<[SavedAction]>(url: url)
        self.file = file
        self.launcher = launcher
        self.write = write ?? { try await file.save($0) }
        reload()
    }

    func reload() {
        guard pending.isEmpty else { return }
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

    @discardableResult func save(_ action: SavedAction) async -> Bool {
        await persist { items in
            var updated = items
            if let index = updated.firstIndex(where: { $0.id == action.id }) { updated[index] = action }
            else { updated.append(action) }
            return updated
        }
    }

    @discardableResult func delete(_ id: UUID) async -> Bool {
        await persist { $0.filter { $0.id != id } }
    }

    @discardableResult func move(_ id: UUID, offset: Int) async -> Bool {
        await persist { items in
            guard let index = items.firstIndex(where: { $0.id == id }), items.indices.contains(index + offset) else { return nil }
            var updated = items
            updated.swapAt(index, index + offset)
            return updated
        }
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

    func run(_ action: SavedAction) async {
        guard runningID == nil else { return }
        runningID = action.id
        error = nil
        result = nil
        defer { runningID = nil }
        do {
            let destination = try await launcher.perform(action)
            if destination != action.destination {
                _ = await persist { items in
                    guard let index = items.firstIndex(where: { $0.id == action.id }),
                          items[index].destination == action.destination else { return nil }
                    var updated = items
                    updated[index].destination = destination
                    return updated
                }
            }
            result = "\(action.name) completed."
        } catch { self.error = "\(action.name): \(error.localizedDescription)" }
    }

    private func persist(_ update: @escaping ([SavedAction]) -> [SavedAction]?) async -> Bool {
        let previous = pending.last?.task
        let id = UUID()
        let operation = Task {
            _ = await previous?.value
            defer { pending.removeAll { $0.id == id } }
            guard canSave else {
                failedWriteGeneration += 1
                return false
            }
            guard let items = update(actions) else { return true }
            do {
                try validateActions(items, allowShortcuts: true)
                try await write(items)
                actions = items
                error = nil
                return true
            } catch {
                failedWriteGeneration += 1
                self.error = "Could not save the quick action. \(error.localizedDescription)"
                return false
            }
        }
        pending.append((id, operation))
        return await operation.value
    }
}
