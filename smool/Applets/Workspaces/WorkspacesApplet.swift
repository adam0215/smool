import SwiftUI

@MainActor @Observable
final class WorkspacesApplet: Applet {
    let id = AppletID(rawValue: "workspaces")
    let title = "Workspaces"
    let icon = AppletIcon.symbol("square.grid.2x2")
    let tint = Color.teal
    let store: WorkspaceStore
    var selectedID: UUID?
    var editor: WorkspaceDraft? {
        didSet { editorGeneration += 1 }
    }
    private var editorGeneration = 0
    private(set) var isPersisting = false
    var deletingWorkspace: SavedWorkspace?
    private var drafts: [UUID: WorkspaceDraft] = [:]
    private var newDraft: WorkspaceDraft?

    init(store: WorkspaceStore = WorkspaceStore()) { self.store = store }

    var contentHeight: CGFloat {
        if editor?.resourceEditor != nil { return 250 }
        if deletingWorkspace != nil { return 180 }
        let feedbackHeight: CGFloat = store.error != nil ? 44 : (store.result != nil ? 24 : 0)
        if let editor {
            return min(320, max(230, 190 + CGFloat(editor.workspace.resources.count) * 36) + feedbackHeight)
        }
        return min(320, max(180, 120 + CGFloat(store.workspaces.count) * 60) + feedbackHeight)
    }

    var selected: SavedWorkspace? { store.workspaces.first(where: { $0.id == selectedID }) ?? store.workspaces.first }
    var hasPresentedOverlay: Bool { editor != nil || deletingWorkspace != nil }
    var status: AppletStatus? {
        if store.isOpening { return AppletStatus(kind: .working, label: "Opening workspace") }
        if store.error != nil { return AppletStatus(kind: .needsAttention, label: "Check workspace") }
        return nil
    }

    var actions: [AppletAction] {
        guard store.canSave else { return [AppletAction(id: "reload-workspaces", title: "Reload workspaces", symbol: "arrow.clockwise") { [weak self] in self?.store.reload() }] }
        if let editor {
            guard editor.resourceEditor == nil, !editor.isSaving else { return [] }
            var actions = [
                AppletAction(id: "add-resource", title: "Add resource", symbol: "plus", shortcut: AppletShortcut(key: "n")) { editor.editResource() },
                AppletAction(id: "save-workspace", title: "Save workspace", symbol: "checkmark", shortcut: AppletShortcut(key: .return)) { [weak self] in Task { await self?.saveEditor() } }
            ]
            if let resource = editor.selectedResource {
                actions += [
                    AppletAction(id: "edit-resource", title: "Edit \(resource.name)", symbol: "pencil", shortcut: AppletShortcut(key: .return, modifiers: [])) { editor.editResource(resource) },
                    AppletAction(id: "include-in-workspace", title: "Include in workspace", symbol: "checkmark.circle", shortcut: AppletShortcut(key: .space, modifiers: []), selected: editor.workspace.selectedResourceIDs.contains(resource.id)) { editor.toggleSelected() },
                    AppletAction(id: "remove-resource", title: "Remove \(resource.name)", symbol: "minus.circle", shortcut: AppletShortcut(key: .delete)) { editor.removeSelected() }
                ]
            }
            return actions
        }
        var actions = [AppletAction(id: "new-workspace", title: newDraft == nil ? "New workspace" : "Resume new workspace", symbol: "plus", shortcut: AppletShortcut(key: "n")) { [weak self] in self?.edit() }]
        if let selected {
            actions += [
                AppletAction(id: "open-workspace", title: "Open \(selected.name)", symbol: "arrow.up.right", shortcut: AppletShortcut(key: .return, modifiers: [])) { [weak self] in self?.openSelected() },
                AppletAction(id: "edit-workspace", title: "Edit \(selected.name)", symbol: "pencil", shortcut: AppletShortcut(key: "e")) { [weak self] in self?.edit(selected) },
                AppletAction(id: "delete-workspace", title: "Delete \(selected.name)", symbol: "trash", shortcut: AppletShortcut(key: .delete)) { [weak self] in self?.deletingWorkspace = selected }
            ]
        }
        return actions
    }

    func makeView(context: AppletContext, artwork: NSImage?) -> AnyView {
        AnyView(WorkspacesAppletView(applet: self, restoreFocus: context.restoreFocus))
    }

    func edit(_ workspace: SavedWorkspace? = nil) {
        guard store.canSave else { return }
        if let workspace {
            let draft = drafts[workspace.id] ?? WorkspaceDraft(workspace)
            drafts[workspace.id] = draft
            editor = draft
        } else {
            let draft = newDraft ?? WorkspaceDraft(SavedWorkspace(name: ""))
            newDraft = draft
            editor = draft
        }
    }

    @discardableResult
    func saveEditor() async -> Bool {
        guard !isPersisting, let editor, editor.resourceEditor == nil else { return false }
        let generation = editorGeneration
        let original = editor.workspace
        isPersisting = true
        editor.isSaving = true
        defer { isPersisting = false; editor.isSaving = false }
        var workspace = original
        if workspace.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            workspace.name = workspace.resources.first.map { "\($0.name) workspace" } ?? "Workspace"
        }
        guard await store.save(workspace) else { return false }
        guard editorGeneration == generation, self.editor === editor,
              editor.workspace == original, editor.resourceEditor == nil else { return false }
        selectedID = workspace.id
        editor.workspace = workspace
        drafts[workspace.id] = editor
        if newDraft?.id == workspace.id { newDraft = nil }
        self.editor = nil
        return true
    }

    func confirmDeletion() async -> Bool {
        guard !isPersisting, let workspace = deletingWorkspace else { return false }
        isPersisting = true
        defer { isPersisting = false }
        guard await store.delete(workspace.id) else { return false }
        guard deletingWorkspace?.id == workspace.id, editor == nil else { return false }
        if selectedID == workspace.id { selectedID = store.workspaces.first?.id }
        deletingWorkspace = nil
        return true
    }

    func openSelected() {
        guard let selected else { return }
        let resources = selected.resources.filter { selected.selectedResourceIDs.contains($0.id) }
        if resources.isEmpty { edit(selected) }
        else { Task { await store.open(resources) } }
    }

    func dismissOverlay() {
        if editor?.resourceEditor != nil { editor?.resourceEditor = nil }
        else { editor = nil; deletingWorkspace = nil }
    }

    // Switching tools suspends the complete draft, including a resource editor.
    func deactivate() { deletingWorkspace = nil }

    func handleArrow(_ arrow: AppletArrow, command: Bool) -> Bool {
        guard !command, deletingWorkspace == nil else { return false }
        if let editor { return arrow.isVertical && editor.moveSelection(arrow.offset) }
        guard !store.workspaces.isEmpty else { return false }
        let index = store.workspaces.firstIndex(where: { $0.id == selected?.id }) ?? 0
        selectedID = store.workspaces[(index + arrow.offset + store.workspaces.count) % store.workspaces.count].id
        return true
    }
}

private struct WorkspacesAppletView: View {
    @Bindable var applet: WorkspacesApplet
    var restoreFocus: () -> Void
    @FocusState private var listFocused: Bool

    var body: some View {
        Group {
            if let draft = applet.editor {
                WorkspaceEditor(draft: draft, store: applet.store, onSave: applet.saveEditor, onClose: closeEditor, restoreFocus: restoreFocus)
            } else if let workspace = applet.deletingWorkspace {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Delete \(workspace.name)?").font(.system(size: 14, weight: .semibold))
                    Text("Your apps, folders and links stay where they are.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    ActionFeedback(error: applet.store.error, result: nil)
                    HStack {
                        Button("Keep workspace", action: closeEditor).keyboardShortcut(.cancelAction)
                        Spacer()
                        Button("Delete", role: .destructive) {
                            Task {
                                if await applet.confirmDeletion() { restoreFocus(); listFocused = true }
                            }
                        }
                        .keyboardShortcut(.defaultAction)
                        .disabled(applet.isPersisting)
                    }
                }.padding(24).modifier(FloatingGlass(cornerRadius: NotchLayout.bottomRadius - NotchLayout.contentInset, cornerStyle: .circular))
            } else {
                workspaceList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.horizontal, applet.hasPresentedOverlay ? NotchLayout.contentInset : 24)
        .padding(.top, 8)
        .padding(.bottom, applet.hasPresentedOverlay ? NotchLayout.contentInset : 24)
    }

    private var workspaceList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Open a group of resources together")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 3) {
                        ForEach(applet.store.workspaces) { workspace in
                            Button { applet.selectedID = workspace.id; applet.openSelected() } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "square.grid.2x2").foregroundStyle(.secondary)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(workspace.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                                        Text(workspace.resources.isEmpty ? "Add resources to get started" : workspace.resources.filter { workspace.selectedResourceIDs.contains($0.id) }.map(\.name).joined(separator: ", "))
                                            .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    Spacer()
                                }
                                .padding(12).contentShape(Rectangle())
                                .background(.white.opacity(applet.selected?.id == workspace.id ? 0.09 : 0), in: .rect(cornerRadius: 12))
                            }
                            .buttonStyle(.plain).focusable(false)
                            .id(workspace.id)
                            .onHover { if $0 { applet.selectedID = workspace.id } }
                        }
                    }
                }
                .onChange(of: applet.selectedID) { _, id in if let id { proxy.scrollTo(id) } }
                .overlay {
                    if applet.store.workspaces.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "square.grid.2x2").font(.system(size: 24, weight: .light)).foregroundStyle(.tertiary)
                            Text("Everything for your next project").font(.system(size: 13, weight: .medium))
                            Text("Apps, folders and links, ready in one step.").font(.system(size: 11)).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity)
                    }
                }
            }
            ActionFeedback(error: applet.store.error, result: applet.store.result)
            if !applet.store.canSave { Button("Reload") { applet.store.reload() } }
            Text(applet.store.workspaces.isEmpty ? "⌘N New workspace · ⌘K Actions" : "⌘N New · ⌘E Edit · ⌘K Actions")
                .font(.system(size: 10)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
        }
        .focusable(interactions: .edit).focused($listFocused).focusEffectDisabled()
        .onAppletFocusRestore { listFocused = true }
        .task { await Task.yield(); listFocused = true }
        .onKeyPress(.return) { applet.openSelected(); return .handled }
        .onKeyPress(keys: ["n", "e", .delete], phases: .down) { key in
            guard key.modifiers.intersection([.command, .control, .option, .shift]) == .command else { return .ignored }
            if key.key == "n" { applet.edit(); return .handled }
            guard let selected = applet.selected else { return .ignored }
            if key.key == "e" { applet.edit(selected) }
            else { applet.deletingWorkspace = selected }
            return .handled
        }
    }

    private func closeEditor() {
        applet.dismissOverlay()
        restoreFocus()
        listFocused = true
    }
}
