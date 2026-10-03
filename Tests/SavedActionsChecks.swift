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
        precondition(store.error?.contains("Broken") == true && store.result == "Opened 1 of 2 resources.")
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
        print("Passed: resource inference, website normalization, suggested names, URL validation, local bookmarks, shortcut parsing, persistence, ordering, edits, deletion, corrupt-file preservation, failed writes and injected launches.")
    }

    static func rejects(_ body: () throws -> Void) {
        do { try body(); preconditionFailure("Expected validation failure") } catch {}
    }
}
