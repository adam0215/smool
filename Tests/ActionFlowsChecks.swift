@testable import SmoolChecksSupport
import SwiftUI
import Observation

@main
struct ActionFlowsChecks {
    @MainActor static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let launcher = ActionLauncher(openURL: { _ in preconditionFailure("Editing must not launch resources") }, runShortcut: { _ in preconditionFailure("Editing must not run shortcuts") })
        let quick = QuickActionsApplet(store: QuickActionStore(url: root.appendingPathComponent("actions.json"), launcher: launcher))
        let spaces = WorkspacesApplet(store: WorkspaceStore(url: root.appendingPathComponent("spaces.json"), launcher: launcher))
        let layout = NotchLayout(screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900))
        var invoked = 0
        quick.commandContext = AppletCommandContext(hostActions: {
            [AppletAction(id: "context", title: "Context command", symbol: "star", shortcut: AppletShortcut(key: "n"), selected: true) { invoked += 1 },
             AppletAction(id: "context-return", title: "Context return", symbol: "arrow.up", shortcut: AppletShortcut(key: .return, modifiers: [])) {}]
        })
        // Commands are available before rendering and retain selected state.
        precondition(quick.entries.first?.selected == true)
        precondition(quick.entries.first?.id == "context:context")
        _ = quick.makeView(context: AppletContext(layout: layout), artwork: nil)
        precondition(quick.entries.first?.title == "Context command")
        precondition(quick.handleArrow(.down, command: false))
        quick.activateSelected()
        precondition(invoked == 1)
        let contextEntry = quick.entries.first!
        let newEntry = quick.entries.first { $0.id == "new" }!
        precondition(contextEntry.shortcut?.paletteShortcut?.key == "n" && contextEntry.shortcut?.paletteShortcut?.modifiers == .command)
        precondition(newEntry.shortcut?.paletteShortcut?.key == "n" && newEntry.shortcut?.paletteShortcut?.modifiers == [.command, .shift])
        precondition(quick.entries.first { $0.title == "Context return" }?.shortcut?.paletteShortcut == nil)

        quick.edit()
        let new = quick.editor!
        new.input = "example.com/path"
        precondition(!quick.handleArrow(.down, command: false))
        quick.dismissOverlay()
        precondition(!quick.hasPresentedOverlay)
        quick.edit()
        precondition(quick.editor === new && quick.editor?.input == "example.com/path")
        let saved = try new.savedAction()
        precondition(saved.name == "example.com")
        let savedAction = await quick.save(saved)
        precondition(savedAction)
        quick.dismissOverlay()
        quick.edit(saved)
        quick.editor?.name = "Changed draft"
        quick.deactivate()
        quick.edit(saved)
        precondition(quick.editor?.name == "Changed draft")
        precondition(quick.store.actions.first?.name == "example.com", "Leaving a draft must not change saved data")
        quick.dismissOverlay()
        quick.edit()
        precondition(quick.editor?.input.isEmpty == true, "Saving clears only the completed new draft")

        spaces.edit()
        let workspaceDraft = spaces.editor!
        workspaceDraft.workspace.name = "Writing"
        workspaceDraft.editResource()
        let resourceDraft = workspaceDraft.resourceEditor!
        resourceDraft.input = "developer.apple.com"
        spaces.dismissOverlay()
        precondition(spaces.editor === workspaceDraft && workspaceDraft.resourceEditor == nil)
        workspaceDraft.editResource()
        precondition(workspaceDraft.resourceEditor === resourceDraft)
        let resource = try resourceDraft.savedAction()
        precondition(workspaceDraft.saveResource(resource))
        workspaceDraft.resourceEditor = nil
        precondition(workspaceDraft.workspace.selectedResourceIDs == [resource.id])
        workspaceDraft.toggleSelected()
        precondition(workspaceDraft.workspace.selectedResourceIDs.isEmpty)
        workspaceDraft.toggleSelected()
        precondition(workspaceDraft.moveSelection(1))
        spaces.dismissOverlay()
        spaces.edit()
        precondition(spaces.editor === workspaceDraft)
        spaces.deactivate()
        precondition(spaces.editor === workspaceDraft, "Opening Actions must preserve workspace editor commands")
        precondition(spaces.actions.contains { $0.id == "add-resource" })
        workspaceDraft.editResource()
        let unfinished = workspaceDraft.resourceEditor!
        unfinished.input = "unfinished.example"
        spaces.dismissOverlay()
        let savedWorkspace = await spaces.saveEditor()
        precondition(savedWorkspace)
        precondition(spaces.editor == nil && spaces.store.workspaces.count == 1)
        precondition(spaces.store.workspaces[0].resources == [resource])
        spaces.edit(spaces.store.workspaces[0])
        precondition(spaces.editor === workspaceDraft)
        workspaceDraft.editResource()
        precondition(workspaceDraft.resourceEditor === unfinished && workspaceDraft.resourceEditor?.input == "unfinished.example")
        spaces.dismissOverlay()
        let second = SavedAction(name: "Second", destination: try .web("second.example"))
        precondition(workspaceDraft.saveResource(second))
        precondition(workspaceDraft.moveSelection(1) && workspaceDraft.selectedResourceID == resource.id)
        precondition(workspaceDraft.moveSelection(-1) && workspaceDraft.selectedResourceID == second.id)
        spaces.editor?.removeSelected()
        precondition(workspaceDraft.selectedResourceID == resource.id)
        spaces.editor?.removeSelected()
        precondition(spaces.editor?.workspace.resources.isEmpty == true)
        precondition(spaces.store.workspaces[0].resources == [resource], "Removing a draft resource is only persisted on Save")

        let shortcut = SavedAction(name: "Morning", destination: .shortcut(id: UUID(), name: "Morning"))
        let shortcutDraft = ActionEditorRequest(action: shortcut)
        let unchangedShortcut = try shortcutDraft.savedAction()
        precondition(unchangedShortcut == shortcut)
        shortcutDraft.usesShortcut = false
        shortcutDraft.input = "example.org"
        let changedShortcut = try shortcutDraft.savedAction()
        precondition(changedShortcut.destination.kind == .website)
        try await checkReplacedEditors(root: root, launcher: launcher)
        try await checkFailedWrites(root: root, launcher: launcher)
        print("Passed: combined palette, keyboard selection, inferred editor names, independent drafts, nested Escape, workspace inclusion and save boundaries.")
    }

    @MainActor private static func checkReplacedEditors(root: URL, launcher: ActionLauncher) async throws {
        let quick = QuickActionsApplet(store: QuickActionStore(url: root.appendingPathComponent("replacement-actions.json"), launcher: launcher))
        quick.edit()
        quick.editor!.input = "example.com"
        let saved = try quick.editor!.savedAction()
        let replacement = SavedAction(name: "Another action", destination: try .web("example.org"))
        withObservationTracking {
            _ = quick.isPersisting
        } onChange: {
            MainActor.assumeIsolated {
                quick.dismissOverlay()
                quick.edit(replacement)
            }
        }
        let mayCloseActionEditor = await quick.save(saved)
        precondition(!mayCloseActionEditor && quick.editor?.action == replacement)
        precondition(quick.store.actions == [saved], "A completed write must not close a replacement editor")

        let spaces = WorkspacesApplet(store: WorkspaceStore(url: root.appendingPathComponent("replacement-workspaces.json"), launcher: launcher))
        spaces.edit()
        let savedWorkspace = spaces.editor!.workspace
        let replacementWorkspace = SavedWorkspace(name: "Another workspace")
        withObservationTracking {
            _ = spaces.isPersisting
        } onChange: {
            MainActor.assumeIsolated {
                spaces.dismissOverlay()
                spaces.edit(replacementWorkspace)
            }
        }
        let mayCloseWorkspaceEditor = await spaces.saveEditor()
        precondition(!mayCloseWorkspaceEditor && spaces.editor?.workspace == replacementWorkspace)
        precondition(spaces.store.workspaces.first?.id == savedWorkspace.id)

        quick.editor!.input = "changed.example"
        let actionDraft = quick.editor!
        let beforeChange = try actionDraft.savedAction()
        withObservationTracking {
            _ = quick.isPersisting
        } onChange: {
            MainActor.assumeIsolated { actionDraft.name = "Newer unsaved name" }
        }
        let mayCloseChangedAction = await quick.save(beforeChange)
        precondition(!mayCloseChangedAction && quick.editor === actionDraft && actionDraft.name == "Newer unsaved name")
        precondition(quick.store.actions.first { $0.id == beforeChange.id } == beforeChange)

        let workspaceDraft = spaces.editor!
        let beforeWorkspaceChange = workspaceDraft.workspace
        withObservationTracking {
            _ = spaces.isPersisting
        } onChange: {
            MainActor.assumeIsolated { workspaceDraft.workspace.name = "Newer workspace name" }
        }
        let mayCloseChangedWorkspace = await spaces.saveEditor()
        precondition(!mayCloseChangedWorkspace && spaces.editor === workspaceDraft)
        precondition(workspaceDraft.workspace.name == "Newer workspace name")
        precondition(spaces.store.workspaces.first { $0.id == beforeWorkspaceChange.id } == beforeWorkspaceChange)
    }

    @MainActor private static func checkFailedWrites(root: URL, launcher: ActionLauncher) async throws {
        let actionFolder = root.appendingPathComponent("action-failure")
        let quick = QuickActionsApplet(store: QuickActionStore(url: actionFolder.appendingPathComponent("actions.json"), launcher: launcher))
        let action = SavedAction(name: "Keep action", destination: try .web("example.com"))
        let initialActionSaved = await quick.store.save(action)
        precondition(initialActionSaved)
        quick.selectedID = action.id
        quick.edit(action)
        let actionDraft = quick.editor!
        actionDraft.name = "Keep this edited draft"
        let editedAction = try actionDraft.savedAction()
        try FileManager.default.removeItem(at: actionFolder)
        try Data("Blocks the parent directory".utf8).write(to: actionFolder)
        let failedSave = await quick.save(editedAction)
        precondition(!failedSave && quick.editor === actionDraft && quick.selectedID == action.id)
        precondition(quick.store.actions == [action] && actionDraft.name == "Keep this edited draft")
        quick.dismissOverlay()
        quick.deletingAction = action
        let failedDelete = await quick.confirmDeletion()
        precondition(!failedDelete && quick.deletingAction == action && quick.selectedID == action.id)

        let workspaceFolder = root.appendingPathComponent("workspace-failure")
        let spaces = WorkspacesApplet(store: WorkspaceStore(url: workspaceFolder.appendingPathComponent("workspaces.json"), launcher: launcher))
        let workspace = SavedWorkspace(name: "Keep workspace", resources: [action])
        let initialWorkspaceSaved = await spaces.store.save(workspace)
        precondition(initialWorkspaceSaved)
        spaces.selectedID = workspace.id
        spaces.edit(workspace)
        let workspaceDraft = spaces.editor!
        workspaceDraft.workspace.name = "Keep this workspace draft"
        try FileManager.default.removeItem(at: workspaceFolder)
        try Data("Blocks the parent directory".utf8).write(to: workspaceFolder)
        let failedWorkspaceSave = await spaces.saveEditor()
        precondition(!failedWorkspaceSave && spaces.editor === workspaceDraft && spaces.selectedID == workspace.id)
        precondition(spaces.store.workspaces == [workspace] && workspaceDraft.workspace.name == "Keep this workspace draft")
        spaces.dismissOverlay()
        spaces.deletingWorkspace = workspace
        let failedWorkspaceDelete = await spaces.confirmDeletion()
        precondition(!failedWorkspaceDelete && spaces.deletingWorkspace == workspace && spaces.selectedID == workspace.id)
    }

}
