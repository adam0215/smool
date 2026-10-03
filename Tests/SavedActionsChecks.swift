import Foundation

@main
struct SavedActionsChecks {
    @MainActor static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        for invalid in ["javascript:alert(1)", "file:///tmp", "https://", "https://user:password@example.com", "example.com", "https://exa mple.com"] {
            rejects { _ = try ActionDestination.web(invalid) }
        }
        let website = try ActionDestination.web(" https://example.com/path?q=å ")
        let threadID = UUID()
        let thread = try ActionDestination.thread(threadID.uuidString)
        let threadURL = try ActionDestination.thread("codex://threads/\(threadID.uuidString.lowercased())")
        precondition(thread == threadURL)
        for invalid in ["codex://settings", "codex://threads/not-an-id", "codex://threads/\(threadID)?execute=1", "codex://threads/\(threadID)/other", "codex://user@threads/\(threadID)", "codex://threads/%2F\(threadID)"] {
            rejects { _ = try ActionDestination.thread(invalid) }
        }
        let folder = try ActionDestination.local(root, kind: .folder)
        rejects { _ = try ActionDestination.local(root, kind: .application) }
        rejects { _ = try ActionDestination.local(URL(string: "https://example.com")!, kind: .folder) }
        let shortcutID = UUID()
        let shortcuts = try ShortcutCatalog.parse("One (\(shortcutID))\n")
        precondition(shortcuts == [AvailableShortcut(id: shortcutID, name: "One")])
        let emptyShortcuts = try ShortcutCatalog.parse("")
        precondition(emptyShortcuts.isEmpty)
        rejects { _ = try ShortcutCatalog.parse("unexpected output") }

        var opened: [URL] = []
        var ran: [UUID] = []
        let launcher = ActionLauncher(openURL: { url in
            if url.host == "fails.example.com" { throw ActionFailure(message: "Stub failure") }
            opened.append(url)
        }, runShortcut: { ran.append($0) })
        let webAction = SavedAction(name: "Example", destination: website)
        let folderAction = SavedAction(name: "Folder", destination: folder)
        let threadAction = SavedAction(name: "Thread", destination: thread)
        let shortcutAction = SavedAction(name: "Shortcut", destination: .shortcut(id: shortcutID, name: "A ; $(touch nope)"))
        let failure = SavedAction(name: "Broken", destination: try .web("https://fails.example.com"))
        let actionURL = root.appendingPathComponent("actions.json")
        let actions = QuickActionStore(url: actionURL, launcher: launcher)
        precondition(actions.save(webAction))
        precondition(actions.save(folderAction))
        precondition(actions.save(shortcutAction))
        actions.move(shortcutAction.id, offset: -1)
        precondition(actions.actions.map(\.id) == [webAction.id, shortcutAction.id, folderAction.id])
        var renamed = webAction
        renamed.name = "Renamed"
        precondition(actions.save(renamed))
        let reloadedActions = QuickActionStore(url: actionURL, launcher: launcher)
        precondition(reloadedActions.actions == actions.actions)
        await actions.run(shortcutAction)
        precondition(ran == [shortcutID] && opened.isEmpty)
        await actions.run(folderAction)
        precondition(opened.count == 1 && opened[0].standardizedFileURL == root.standardizedFileURL)
        await actions.run(failure)
        precondition(actions.error?.contains("Stub failure") == true && actions.runningID == nil)
        actions.delete(folderAction.id)
        precondition(QuickActionStore(url: actionURL, launcher: launcher).actions.count == 2)

        let workspaceURL = root.appendingPathComponent("workspaces.json")
        let store = WorkspaceStore(url: workspaceURL, launcher: launcher)
        var workspace = SavedWorkspace(name: " Project ", resources: [webAction, threadAction, failure], selectedResourceIDs: [webAction.id, failure.id])
        precondition(store.save(workspace))
        precondition(store.workspaces[0].name == "Project")
        precondition(WorkspaceStore(url: workspaceURL, launcher: launcher).workspaces == store.workspaces)
        opened.removeAll()
        await store.open(workspace.resources.filter { workspace.selectedResourceIDs.contains($0.id) })
        precondition(opened.count == 1 && ran.count == 1)
        precondition(store.error?.contains("Broken") == true && store.result == "Öppnade 1 av 2 resurser.")
        precondition(!store.isOpening)
        workspace.resources = [webAction]
        precondition(store.save(workspace))
        precondition(store.workspaces[0].selectedResourceIDs == [webAction.id])
        precondition(store.delete(workspace.id))
        precondition(WorkspaceStore(url: workspaceURL, launcher: launcher).workspaces.isEmpty)
        rejects { try validateActions([shortcutAction], allowShortcuts: false) }
        rejects { try validateActions([webAction, webAction], allowShortcuts: true) }

        var pending: CheckedContinuation<Void, Never>?
        var launchCount = 0
        let gatedLauncher = ActionLauncher(openURL: { _ in
            launchCount += 1
            await withCheckedContinuation { pending = $0 }
        }, runShortcut: { _ in })
        let gated = QuickActionStore(url: root.appendingPathComponent("gated.json"), launcher: gatedLauncher)
        let running = Task { await gated.run(webAction) }
        while gated.runningID == nil { await Task.yield() }
        await gated.run(webAction)
        precondition(launchCount == 1, "Repeated Return must not launch twice while running")
        pending?.resume()
        await running.value
        precondition(gated.runningID == nil)

        let corrupt = Data("not json".utf8)
        try corrupt.write(to: actionURL)
        let broken = QuickActionStore(url: actionURL, launcher: launcher)
        precondition(!broken.canSave && !broken.save(webAction))
        let preservedActions = try Data(contentsOf: actionURL)
        precondition(preservedActions == corrupt)
        try corrupt.write(to: workspaceURL)
        let brokenWorkspaces = WorkspaceStore(url: workspaceURL, launcher: launcher)
        precondition(!brokenWorkspaces.canSave && !brokenWorkspaces.save(workspace))
        let preservedWorkspaces = try Data(contentsOf: workspaceURL)
        precondition(preservedWorkspaces == corrupt)

        let blockedURL = root.appendingPathComponent("blocked")
        try Data().write(to: blockedURL)
        let blocked = QuickActionStore(url: blockedURL.appendingPathComponent("actions.json"), launcher: launcher)
        precondition(!blocked.save(webAction) && blocked.actions.isEmpty)
        print("Passed: URL validation, local bookmarks, shortcut parsing, persistence, ordering, edits, deletion, corrupt-file preservation, failed writes and injected launches.")
    }

    static func rejects(_ body: () throws -> Void) {
        do { try body(); preconditionFailure("Expected validation failure") } catch {}
    }
}
