@testable import SmoolChecksSupport
import Foundation

@main
struct SavedActionsChecks {
    @MainActor static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        for invalid in ["", "javascript:alert(1)", "file:///tmp", "https://", "https://user:password@example.com",
                        "user@example.com", "https://exa mple.com", "https://example..com", "example.com:99999",
                        "mailto:hello@example.com", "https://example.com/%zz", "https://example.com\\other",
                        "https://[garbage]", "https://[1:2:3:4:5:6:7:8:9]"] {
            rejects { _ = try ActionDestination.web(invalid) }
        }
        let website = try ActionDestination.web(" https://example.com/path?q=å ")
        for (input, expected) in [
            (" example.com ", "https://example.com"),
            ("WWW.Example.com/path?q=1#next", "https://www.example.com/path?q=1#next"),
            ("example.com:8443/path", "https://example.com:8443/path"),
            ("localhost:3000", "https://localhost:3000"),
            ("127.0.0.1:8080", "https://127.0.0.1:8080"),
            ("[::1]:8080", "https://[::1]:8080"),
            ("HTTPS://EXAMPLE.COM", "https://example.com"),
            ("http://intranet", "http://intranet")
        ] {
            let destination = try ActionDestination.inferred(input)
            precondition(destination == .website(URL(string: expected)!))
        }
        let namedWebsite = try ActionDestination.inferred("www.example.com/path")
        precondition(namedWebsite.suggestedName == "example.com")
        for invalid in ["", "unknown app that does not exist", "javascript:alert(1)", "file://remote/tmp", "file:///tmp?query=1"] {
            rejects { _ = try ActionDestination.inferred(invalid) }
        }
        let threadID = UUID()
        let thread = try ActionDestination.thread(threadID.uuidString)
        let threadURL = try ActionDestination.thread("codex://threads/\(threadID.uuidString.lowercased())")
        precondition(thread == threadURL)
        let inferredThread = try ActionDestination.inferred(threadID.uuidString)
        let uppercaseThread = try ActionDestination.inferred("CODEX://THREADS/\(threadID.uuidString)")
        precondition(inferredThread == thread && uppercaseThread == thread)
        precondition(thread.suggestedName == "Thread \(threadID.uuidString.lowercased().prefix(8))")
        for invalid in ["codex://settings", "codex://threads/not-an-id", "codex://threads/\(threadID)?execute=1", "codex://threads/\(threadID)/other", "codex://user@threads/\(threadID)", "codex://threads/%2F\(threadID)"] {
            rejects { _ = try ActionDestination.thread(invalid) }
        }
        let folder = try ActionDestination.local(root, kind: .folder)
        let inferredFolder = try ActionDestination.inferred(root.path)
        let inferredFileURL = try ActionDestination.inferred(root.absoluteString)
        precondition(inferredFolder.kind == .folder && inferredFileURL.kind == .folder)
        precondition(inferredFolder.suggestedName == root.lastPathComponent)
        let homeFolder = try ActionDestination.inferred("~")
        precondition(homeFolder.kind == .folder)
        let regularFile = root.appendingPathComponent("document.txt")
        try Data("text".utf8).write(to: regularFile)
        rejects { _ = try ActionDestination.inferred(regularFile.path) }
        let app = root.appendingPathComponent("Example.app/Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        let info: [String: String] = ["CFBundlePackageType": "APPL", "CFBundleIdentifier": "test.example",
                                    "CFBundleDisplayName": "Example App", "CFBundleExecutable": "Example"]
        let plist = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try plist.write(to: app.appendingPathComponent("Info.plist"))
        let inferredApp = try ActionDestination.inferred(app.deletingLastPathComponent().path)
        precondition(inferredApp.kind == .application && inferredApp.suggestedName == "Example App")
        if FileManager.default.fileExists(atPath: "/System/Applications/TextEdit.app") {
            let installedApp = try ActionDestination.inferred("textedit")
            precondition(installedApp.kind == .application && installedApp.suggestedName == "TextEdit")
        }
        rejects { _ = try ActionDestination.local(root, kind: .application) }
        rejects { _ = try ActionDestination.local(URL(string: "https://example.com")!, kind: .folder) }
        let originalFolder = root.appendingPathComponent("original", isDirectory: true)
        let movedFolder = root.appendingPathComponent("moved", isDirectory: true)
        try FileManager.default.createDirectory(at: originalFolder, withIntermediateDirectories: true)
        let localAction = SavedAction(name: "Local", destination: try .local(originalFolder, kind: .folder))
        try FileManager.default.moveItem(at: originalFolder, to: movedFolder)
        let renameDraft = ActionEditorRequest(action: localAction)
        renameDraft.name = "Renamed folder"
        let renamedFolder = try renameDraft.savedAction()
        precondition(renamedFolder.id == localAction.id && renamedFolder.destination == localAction.destination)
        let resolvedFolder = try renamedFolder.destination.resolvedLocal()
        precondition(resolvedFolder.url.resolvingSymlinksInPath() == movedFolder.resolvingSymlinksInPath())
        precondition(resolvedFolder.destination != localAction.destination)
        let renewedFolder = try resolvedFolder.destination.resolvedLocal()
        precondition(renewedFolder.destination == resolvedFolder.destination)
        let invalidBookmark = ActionDestination.folder(movedFolder, bookmark: Data("broken bookmark".utf8))
        let repairDraft = ActionEditorRequest(action: SavedAction(name: "Repair", destination: invalidBookmark))
        repairDraft.input = movedFolder.path
        let repairedFolder = try repairDraft.savedAction()
        precondition(repairedFolder.destination != invalidBookmark)
        let repairedURL = try repairedFolder.destination.resolvedLocal().url
        precondition(repairedURL.resolvingSymlinksInPath() == movedFolder.resolvingSymlinksInPath())

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
        let launchedDestination = try await launcher.perform(localAction)
        precondition(opened.last?.resolvingSymlinksInPath() == movedFolder.resolvingSymlinksInPath())
        precondition(launchedDestination == resolvedFolder.destination)
        opened.removeAll()
        try FileManager.default.createDirectory(at: originalFolder, withIntermediateDirectories: true)
        let reselectedDraft = ActionEditorRequest(action: localAction)
        reselectedDraft.input = originalFolder.path
        let reselectedFolder = try reselectedDraft.savedAction().destination.resolvedLocal()
        precondition(reselectedFolder.url.resolvingSymlinksInPath() == originalFolder.resolvingSymlinksInPath())
        let webAction = SavedAction(name: "Example", destination: website)
        let folderAction = SavedAction(name: "Folder", destination: folder)
        let threadAction = SavedAction(name: "Thread", destination: thread)
        let shortcutAction = SavedAction(name: "Shortcut", destination: .shortcut(id: shortcutID, name: "A ; $(touch nope)"))
        let failure = SavedAction(name: "Broken", destination: try .web("https://fails.example.com"))
        let actionURL = root.appendingPathComponent("actions.json")
        let actions = QuickActionStore(url: actionURL, launcher: launcher)
        expect(await actions.save(webAction))
        expect(await actions.save(folderAction))
        expect(await actions.save(shortcutAction))
        await actions.move(shortcutAction.id, offset: -1)
        precondition(actions.actions.map(\.id) == [webAction.id, shortcutAction.id, folderAction.id])
        var renamed = webAction
        renamed.name = "Renamed"
        expect(await actions.save(renamed))
        let reloadedActions = QuickActionStore(url: actionURL, launcher: launcher)
        precondition(reloadedActions.actions == actions.actions)
        await actions.run(shortcutAction)
        precondition(ran == [shortcutID] && opened.isEmpty)
        await actions.run(folderAction)
        precondition(opened.count == 1 && opened[0].standardizedFileURL == root.standardizedFileURL)
        await actions.run(failure)
        precondition(actions.error?.contains("Stub failure") == true && actions.runningID == nil)
        await actions.delete(folderAction.id)
        precondition(QuickActionStore(url: actionURL, launcher: launcher).actions.count == 2)

        let workspaceURL = root.appendingPathComponent("workspaces.json")
        let store = WorkspaceStore(url: workspaceURL, launcher: launcher)
        var workspace = SavedWorkspace(name: " Project ", resources: [webAction, threadAction, failure], selectedResourceIDs: [webAction.id, failure.id])
        expect(await store.save(workspace))
        precondition(store.workspaces[0].name == "Project")
        precondition(WorkspaceStore(url: workspaceURL, launcher: launcher).workspaces == store.workspaces)
        opened.removeAll()
        await store.open(workspace.resources.filter { workspace.selectedResourceIDs.contains($0.id) })
        precondition(opened.count == 1 && ran.count == 1)
        precondition(store.error?.contains("Broken") == true && store.result == "Opened 1 of 2 resources.")
        precondition(!store.isOpening)
        workspace.resources = [webAction]
        expect(await store.save(workspace))
        precondition(store.workspaces[0].selectedResourceIDs == [webAction.id])
        expect(await store.delete(workspace.id))
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

        let actionWriteGate = WriteGate()
        let writingAction = QuickActionStore(url: root.appendingPathComponent("writing-action.json"), launcher: launcher,
                                            write: { _ in try await actionWriteGate.wait() })
        let failedActionSave = Task { await writingAction.save(webAction) }
        while await !actionWriteGate.started { await Task.yield() }
        var waitingForAction = false
        let actionQuit = Task {
            waitingForAction = true
            return await writingAction.finishPendingChanges()
        }
        while !waitingForAction { await Task.yield() }
        await actionWriteGate.fail()
        expect(await failedActionSave.value == false)
        expect(await actionQuit.value == false)
        expect(await writingAction.finishPendingChanges())
        precondition(writingAction.actions.isEmpty && writingAction.error != nil)

        let workspaceWriteGate = WriteGate()
        let writingWorkspace = WorkspaceStore(url: root.appendingPathComponent("writing-workspace.json"), launcher: launcher,
                                              write: { _ in try await workspaceWriteGate.wait() })
        let failedWorkspaceSave = Task { await writingWorkspace.save(workspace) }
        while await !workspaceWriteGate.started { await Task.yield() }
        var waitingForWorkspace = false
        let workspaceQuit = Task {
            waitingForWorkspace = true
            return await writingWorkspace.finishPendingChanges()
        }
        while !waitingForWorkspace { await Task.yield() }
        await workspaceWriteGate.fail()
        expect(await failedWorkspaceSave.value == false)
        expect(await workspaceQuit.value == false)
        expect(await writingWorkspace.finishPendingChanges())
        precondition(writingWorkspace.workspaces.isEmpty && writingWorkspace.error != nil)

        let concurrentURL = root.appendingPathComponent("concurrent.json")
        let concurrent = QuickActionStore(url: concurrentURL, launcher: launcher)
        let concurrentActions = (0..<30).map { SavedAction(name: "Action \($0)", destination: website) }
        let saves = concurrentActions.map { action in Task { await concurrent.save(action) } }
        for save in saves { expect(await save.value) }
        expect(await concurrent.finishPendingChanges())
        precondition(Set(concurrent.actions.map(\.id)) == Set(concurrentActions.map(\.id)))
        precondition(QuickActionStore(url: concurrentURL, launcher: launcher).actions == concurrent.actions)
        let deletes = concurrentActions.prefix(15).map { action in Task { await concurrent.delete(action.id) } }
        for deletion in deletes { expect(await deletion.value) }
        precondition(Set(concurrent.actions.map(\.id)) == Set(concurrentActions.suffix(15).map(\.id)))

        let concurrentSpacesURL = root.appendingPathComponent("concurrent-spaces.json")
        let concurrentSpaces = WorkspaceStore(url: concurrentSpacesURL, launcher: launcher)
        let workspaces = (0..<20).map { SavedWorkspace(name: "Workspace \($0)", resources: [webAction]) }
        let workspaceSaves = workspaces.map { workspace in Task { await concurrentSpaces.save(workspace) } }
        for save in workspaceSaves { expect(await save.value) }
        expect(await concurrentSpaces.finishPendingChanges())
        precondition(Set(concurrentSpaces.workspaces.map(\.id)) == Set(workspaces.map(\.id)))

        let repairOriginal = root.appendingPathComponent("repair-original", isDirectory: true)
        let repairMoved = root.appendingPathComponent("repair-moved", isDirectory: true)
        try FileManager.default.createDirectory(at: repairOriginal, withIntermediateDirectories: true)
        let repairAction = SavedAction(name: "Repair on launch", destination: try .local(repairOriginal, kind: .folder))
        try FileManager.default.moveItem(at: repairOriginal, to: repairMoved)
        let repairsURL = root.appendingPathComponent("repairs.json")
        let repairs = QuickActionStore(url: repairsURL, launcher: gatedLauncher)
        expect(await repairs.save(repairAction))
        pending = nil
        let repairing = Task { await repairs.run(repairAction) }
        while pending == nil { await Task.yield() }
        var replacement = repairAction
        replacement.destination = website
        replacement.name = "New destination"
        expect(await repairs.save(replacement))
        pending?.resume()
        await repairing.value
        precondition(repairs.actions == [replacement], "A stale launch must not overwrite a new destination")

        expect(await repairs.save(repairAction))
        pending = nil
        let renaming = Task { await repairs.run(repairAction) }
        while pending == nil { await Task.yield() }
        var renamedRepair = repairAction
        renamedRepair.name = "New name"
        expect(await repairs.save(renamedRepair))
        pending?.resume()
        await renaming.value
        precondition(repairs.actions[0].name == "New name")
        precondition(repairs.actions[0].destination != repairAction.destination)
        precondition(QuickActionStore(url: repairsURL, launcher: launcher).actions == repairs.actions)

        let spaceRepairsURL = root.appendingPathComponent("space-repairs.json")
        let spaceRepairs = WorkspaceStore(url: spaceRepairsURL, launcher: gatedLauncher)
        var repairWorkspace = SavedWorkspace(name: "Repair workspace", resources: [repairAction], selectedResourceIDs: [repairAction.id])
        expect(await spaceRepairs.save(repairWorkspace))
        pending = nil
        let repairingWorkspace = Task { await spaceRepairs.open([repairAction]) }
        while pending == nil { await Task.yield() }
        repairWorkspace.resources = [replacement]
        expect(await spaceRepairs.save(repairWorkspace))
        pending?.resume()
        await repairingWorkspace.value
        precondition(spaceRepairs.workspaces == [repairWorkspace])
        repairWorkspace.resources = [repairAction]
        expect(await spaceRepairs.save(repairWorkspace))
        pending = nil
        let deletedWorkspace = Task { await spaceRepairs.open([repairAction]) }
        while pending == nil { await Task.yield() }
        expect(await spaceRepairs.delete(repairWorkspace.id))
        pending?.resume()
        await deletedWorkspace.value
        precondition(spaceRepairs.workspaces.isEmpty, "Bookmark renewal must not resurrect a deleted workspace")
        expect(await spaceRepairs.save(repairWorkspace))
        pending = nil
        let renewedWorkspace = Task { await spaceRepairs.open([repairAction]) }
        while pending == nil { await Task.yield() }
        pending?.resume()
        await renewedWorkspace.value
        precondition(spaceRepairs.workspaces[0].resources[0].destination != repairAction.destination)
        precondition(spaceRepairs.workspaces[0].selectedResourceIDs == [repairAction.id])
        precondition(WorkspaceStore(url: spaceRepairsURL, launcher: launcher).workspaces == spaceRepairs.workspaces)

        let corrupt = Data("not json".utf8)
        try corrupt.write(to: actionURL)
        let broken = QuickActionStore(url: actionURL, launcher: launcher)
        precondition(!broken.canSave)
        expect(await broken.save(webAction) == false)
        let preservedActions = try Data(contentsOf: actionURL)
        precondition(preservedActions == corrupt)
        try corrupt.write(to: workspaceURL)
        let brokenWorkspaces = WorkspaceStore(url: workspaceURL, launcher: launcher)
        precondition(!brokenWorkspaces.canSave)
        expect(await brokenWorkspaces.save(workspace) == false)
        let preservedWorkspaces = try Data(contentsOf: workspaceURL)
        precondition(preservedWorkspaces == corrupt)

        let blockedURL = root.appendingPathComponent("blocked")
        try Data().write(to: blockedURL)
        let blocked = QuickActionStore(url: blockedURL.appendingPathComponent("actions.json"), launcher: launcher)
        expect(await blocked.save(webAction) == false)
        precondition(blocked.actions.isEmpty)
        expect(await blocked.finishPendingChanges())
        try FileManager.default.removeItem(at: blockedURL)
        expect(await blocked.finishPendingChanges())
        precondition(blocked.actions.isEmpty, "Draining must not retry a failed action after its editor was dismissed")
        expect(await blocked.save(webAction))
        precondition(blocked.actions == [webAction])
        precondition(QuickActionStore(url: blockedURL.appendingPathComponent("actions.json"), launcher: launcher).actions == [webAction])

        let retryURL = root.appendingPathComponent("retry.json")
        let retry = QuickActionStore(url: retryURL, launcher: launcher)
        expect(await retry.save(webAction))
        try FileManager.default.removeItem(at: retryURL)
        try FileManager.default.createDirectory(at: retryURL, withIntermediateDirectories: true)
        expect(await retry.delete(webAction.id) == false)
        precondition(retry.actions == [webAction] && retry.error != nil)
        expect(await retry.finishPendingChanges())
        var latestAction = webAction
        latestAction.name = "Latest name"
        latestAction.destination = thread
        expect(await retry.save(latestAction) == false)
        try FileManager.default.removeItem(at: retryURL)
        expect(await retry.finishPendingChanges())
        precondition(retry.actions == [webAction], "Neither failed delete nor failed save may be replayed by quit")
        expect(await retry.save(latestAction))
        precondition(retry.actions == [latestAction] && retry.error == nil)
        precondition(QuickActionStore(url: retryURL, launcher: launcher).actions == [latestAction])

        let retrySpaceURL = root.appendingPathComponent("retry-space.json")
        let retrySpace = WorkspaceStore(url: retrySpaceURL, launcher: launcher)
        expect(await retrySpace.save(repairWorkspace))
        try FileManager.default.removeItem(at: retrySpaceURL)
        try FileManager.default.createDirectory(at: retrySpaceURL, withIntermediateDirectories: true)
        expect(await retrySpace.delete(repairWorkspace.id) == false)
        precondition(retrySpace.workspaces == [repairWorkspace] && retrySpace.error != nil)
        expect(await retrySpace.finishPendingChanges())
        try FileManager.default.removeItem(at: retrySpaceURL)
        expect(await retrySpace.finishPendingChanges())
        precondition(retrySpace.workspaces == [repairWorkspace], "Keep workspace must remain effective when quitting")
        expect(await retrySpace.delete(repairWorkspace.id))
        precondition(retrySpace.workspaces.isEmpty && retrySpace.error == nil)
        precondition(WorkspaceStore(url: retrySpaceURL, launcher: launcher).workspaces.isEmpty)

        print("Passed: resource inference, validation, bookmark renewal and edit races, serialized persistence, concurrent mutations, deletion, corrupt-file preservation, failed writes, quit boundaries and explicit retries.")
    }

    static func expect(_ result: Bool) { precondition(result) }

    static func rejects(_ body: () throws -> Void) {
        do { try body(); preconditionFailure("Expected validation failure") } catch {}
    }
}

private actor WriteGate {
    private(set) var started = false
    private var continuation: CheckedContinuation<Void, Error>?

    func wait() async throws {
        started = true
        try await withCheckedThrowingContinuation { continuation = $0 }
    }

    func fail() {
        continuation?.resume(throwing: CocoaError(.fileWriteNoPermission))
        continuation = nil
    }
}
