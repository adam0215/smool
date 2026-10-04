@testable import SmoolChecksSupport
import Foundation

private actor WriteGate {
    private(set) var started = false
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false

    func wait() async {
        guard !released else { return }
        started = true
        await withCheckedContinuation { continuation = $0 }
    }

    func release() {
        released = true
        continuation?.resume()
        continuation = nil
    }
}

@main
struct TerminationChecks {
    @MainActor static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "smool-exit-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suite = "smool.exit.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let parent = directory.appending(path: "notes")
        let url = parent.appending(path: "notes.json")
        let store = NotesStore(fileURL: url)
        let notes = NotesApplet(store: store)
        let settings = AppSettings(defaults: defaults)
        let presentation = NotchPresentation(registry: AppletRegistry([HomeApplet(), notes]), settings: settings)
        settings.setEnabled(false, for: notes.id)

        let id = store.createNote(text: "Must survive a failed save")!
        try Data().write(to: parent)
        let canQuit = await presentation.finishPendingChanges()
        precondition(!canQuit, "Unsaved notes must prevent exit even when their applet is disabled")
        precondition(store.hasUnsavedChanges && store.selectedNote?.id == id)
        precondition(store.selectedNote?.text == "Must survive a failed save")

        try FileManager.default.removeItem(at: parent)
        let canRetry = await presentation.finishPendingChanges()
        precondition(canRetry && !store.hasUnsavedChanges)
        precondition(NotesStore(fileURL: url).selectedNote?.text == "Must survive a failed save")
        let changingActionsURL = directory.appending(path: "changing-actions.json")
        let changingGate = WriteGate()
        let changingFile = ActionFile<[SavedAction]>(url: changingActionsURL)
        let changingActions = QuickActionsApplet(store: QuickActionStore(url: changingActionsURL, write: { items in
            await changingGate.wait()
            try await changingFile.save(items)
        }))
        let changingHost = NotchPresentation(registry: AppletRegistry([HomeApplet(), notes, changingActions]), settings: settings)
        let changingAction = SavedAction(name: "During quit", destination: .website(URL(string: "https://example.com")!))
        let changingSave = Task { await changingActions.store.save(changingAction) }
        while await !changingGate.started { await Task.yield() }
        let changingQuit = Task { await changingHost.finishPendingChanges() }
        try await Task.sleep(for: .milliseconds(20))
        store.update(id, text: "Edited while another store was still saving")
        await changingGate.release()
        let changingActionSaved = await changingSave.value
        let changingCanQuit = await changingQuit.value
        precondition(changingActionSaved && changingCanQuit)
        precondition(!store.hasUnsavedChanges, "Quit must recheck Notes after waiting for another store.")
        precondition(NotesStore(fileURL: url).selectedNote?.text == "Edited while another store was still saving",
                     "A successful quit must include edits made during its other writes.")

        let actionsParent = directory.appending(path: "actions")
        let actionsURL = actionsParent.appending(path: "actions.json")
        let actionGate = WriteGate()
        let actionFile = ActionFile<[SavedAction]>(url: actionsURL)
        let actions = QuickActionsApplet(store: QuickActionStore(url: actionsURL, write: { items in
            await actionGate.wait()
            try await actionFile.save(items)
        }))
        let workspaceParent = directory.appending(path: "workspaces")
        let workspaceURL = workspaceParent.appending(path: "workspaces.json")
        let workspaceGate = WriteGate()
        let workspaceFile = ActionFile<[SavedWorkspace]>(url: workspaceURL)
        let workspaces = WorkspacesApplet(store: WorkspaceStore(url: workspaceURL, write: { items in
            await workspaceGate.wait()
            try await workspaceFile.save(items)
        }))
        let tools = NotchPresentation(registry: AppletRegistry([HomeApplet(), actions, workspaces]), settings: settings)
        let action = SavedAction(name: "Example", destination: .website(URL(string: "https://example.com")!))
        let workspace = SavedWorkspace(name: "Daily work", resources: [action], selectedResourceIDs: [action.id])
        actions.edit()
        actions.editor!.input = "example.com"
        let draft = actions.editor!
        workspaces.edit()
        workspaces.editor!.workspace = workspace
        let workspaceDraft = workspaces.editor!
        try Data().write(to: actionsParent)
        try Data().write(to: workspaceParent)
        let savingAction = Task { await actions.save(action) }
        while await !actionGate.started { await Task.yield() }
        let actionQuit = Task { await tools.finishPendingChanges() }
        // The writer stays suspended while the host begins draining all stores.
        try await Task.sleep(for: .milliseconds(20))
        await actionGate.release()
        let failedAction = await savingAction.value
        let actionCanQuit = await actionQuit.value
        precondition(!failedAction && !actionCanQuit)
        precondition(tools.failedSaveAppletID == actions.id && tools.terminationError?.contains("Actions") == true)
        precondition(actions.editor === draft && draft.input == "example.com", "A failed quit must leave the editor and its draft visible.")
        precondition(!tools.canRetryPendingChanges, "Actions retry belongs to the editor.")

        let savingWorkspace = Task { await workspaces.saveEditor() }
        while await !workspaceGate.started { await Task.yield() }
        let workspaceQuit = Task { await tools.finishPendingChanges() }
        try await Task.sleep(for: .milliseconds(20))
        await workspaceGate.release()
        let failedWorkspace = await savingWorkspace.value
        let workspaceCanQuit = await workspaceQuit.value
        precondition(!failedWorkspace && !workspaceCanQuit)
        precondition(tools.failedSaveAppletID == workspaces.id && tools.terminationError?.contains("Workspaces") == true)
        precondition(workspaces.editor === workspaceDraft && workspaceDraft.workspace == workspace)
        try FileManager.default.removeItem(at: actionsParent)
        try FileManager.default.removeItem(at: workspaceParent)
        let laterQuit = await tools.finishPendingChanges()
        precondition(laterQuit && tools.terminationError == nil, "An already handled transaction failure must not block a later quit or replay itself.")
        precondition(QuickActionStore(url: actionsURL).actions.isEmpty)
        precondition(WorkspaceStore(url: workspaceURL).workspaces.isEmpty)
        actions.edit()
        let actionRetry = await actions.save(action)
        let workspaceRetry = await workspaces.saveEditor()
        precondition(actionRetry && workspaceRetry)
        precondition(QuickActionStore(url: actionsURL).actions == [action])
        precondition(WorkspaceStore(url: workspaceURL).workspaces == [workspace])
        let lateActionsParent = directory.appending(path: "late-actions")
        let lateActions = QuickActionsApplet(store: QuickActionStore(url: lateActionsParent.appending(path: "actions.json")))
        try Data().write(to: lateActionsParent)
        let lateWorkspaceGate = WriteGate()
        let lateWorkspaceFile = ActionFile<[SavedWorkspace]>(url: directory.appending(path: "late-workspaces.json"))
        let lateWorkspaces = WorkspacesApplet(store: WorkspaceStore(url: lateWorkspaceFile.url, write: { items in
            await lateWorkspaceGate.wait()
            try await lateWorkspaceFile.save(items)
        }))
        let lateHost = NotchPresentation(registry: AppletRegistry([HomeApplet(), lateActions, lateWorkspaces]), settings: settings)
        let lateWorkspaceSave = Task { await lateWorkspaces.store.save(workspace) }
        while await !lateWorkspaceGate.started { await Task.yield() }
        let lateQuit = Task { await lateHost.finishPendingChanges() }
        try await Task.sleep(for: .milliseconds(20))
        let previousFailure = lateActions.store.failedWriteGeneration
        let lateActionSaved = await lateActions.store.save(action)
        precondition(!lateActionSaved)
        precondition(!lateActions.store.hasPendingChanges && lateActions.store.failedWriteGeneration != previousFailure,
                     "The failed action write must have left pending before the workspace finishes.")
        await lateWorkspaceGate.release()
        let lateWorkspaceSaved = await lateWorkspaceSave.value
        let lateCanQuit = await lateQuit.value
        precondition(lateWorkspaceSaved && !lateCanQuit,
                     "A write that starts and fails while another store is draining must still prevent this quit.")
        let afterLateFailure = await lateHost.finishPendingChanges()
        precondition(afterLateFailure, "The already handled failure must not prevent a later explicit quit.")

        print("Passed: quit drains concurrent edits, catches active and late write failures, retains drafts and never replays failed transactions.")
    }
}
