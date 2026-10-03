import SwiftUI

@main
struct ActionFlowsChecks {
    @MainActor static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let launcher = ActionLauncher(openURL: { _ in preconditionFailure("Editing must not launch resources") }, runShortcut: { _ in preconditionFailure("Editing must not run shortcuts") })
        let quick = QuickActionsApplet(store: QuickActionStore(url: root.appendingPathComponent("actions.json"), launcher: launcher))
        let spaces = WorkspacesApplet(store: WorkspaceStore(url: root.appendingPathComponent("spaces.json"), launcher: launcher))
        let layout = NotchLayout(screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900))
        var invoked = 0
        _ = quick.makeView(context: AppletContext(layout: layout, hostActions: [AppletAction(id: "Context command", symbol: "star", shortcut: "⌘N") { invoked += 1 }, AppletAction(id: "Context return", symbol: "arrow.up", shortcut: "↵") {}]), artwork: nil)
        precondition(quick.entries.first?.title == "Context command")
        precondition(quick.handleArrow(.down, command: false))
        quick.activateSelected()
        precondition(invoked == 1)
        let contextEntry = quick.entries.first!
        let newEntry = quick.entries.first { $0.id == "new" }!
        precondition(contextEntry.keyboardShortcut?.key == "n" && contextEntry.keyboardShortcut?.modifiers == .command)
        precondition(newEntry.keyboardShortcut?.key == "n" && newEntry.keyboardShortcut?.modifiers == [.command, .shift])
        precondition(quick.entries.first { $0.title == "Context return" }?.keyboardShortcut == nil)

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
        precondition(quick.save(saved))
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
        precondition(spaces.actions.contains { $0.id == "Add resource" })
        workspaceDraft.editResource()
        let unfinished = workspaceDraft.resourceEditor!
        unfinished.input = "unfinished.example"
        spaces.dismissOverlay()
        spaces.saveEditor()
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
        print("Passed: combined palette, keyboard selection, inferred editor names, independent drafts, nested Escape, workspace inclusion and save boundaries.")
    }
}
