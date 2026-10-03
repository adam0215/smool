import SwiftUI

@MainActor @Observable
final class WorkspaceDraft: Identifiable {
    var workspace: SavedWorkspace
    var selectedResourceID: UUID?
    var resourceEditor: ActionEditorRequest?
    private var resourceDrafts: [UUID: ActionEditorRequest] = [:]
    private var newResource: ActionEditorRequest?
    let id: UUID
    var selectedResource: SavedAction? { workspace.resources.first { $0.id == selectedResourceID } }

    init(_ workspace: SavedWorkspace) {
        id = workspace.id
        self.workspace = workspace
        selectedResourceID = workspace.resources.first?.id
    }

    func editResource(_ resource: SavedAction? = nil) {
        if let resource {
            let draft = resourceDrafts[resource.id] ?? ActionEditorRequest(action: resource)
            resourceDrafts[resource.id] = draft
            resourceEditor = draft
        } else {
            let draft = newResource ?? ActionEditorRequest()
            newResource = draft
            resourceEditor = draft
        }
    }

    func saveResource(_ action: SavedAction) -> Bool {
        if let index = workspace.resources.firstIndex(where: { $0.id == action.id }) {
            workspace.resources[index] = action
        } else {
            workspace.resources.append(action)
            workspace.selectedResourceIDs.insert(action.id)
        }
        if resourceEditor?.action == nil { newResource = nil }
        resourceDrafts[action.id] = nil
        selectedResourceID = action.id
        return true
    }

    func moveSelection(_ offset: Int) -> Bool {
        guard resourceEditor == nil, !workspace.resources.isEmpty else { return false }
        let index = workspace.resources.firstIndex(where: { $0.id == selectedResourceID }) ?? (offset > 0 ? -1 : 0)
        selectedResourceID = workspace.resources[(index + offset + workspace.resources.count) % workspace.resources.count].id
        return true
    }

    func toggleSelected() {
        guard let id = selectedResourceID else { return }
        if !workspace.selectedResourceIDs.insert(id).inserted { workspace.selectedResourceIDs.remove(id) }
    }

    func removeSelected() {
        guard let id = selectedResourceID else { return }
        let index = workspace.resources.firstIndex { $0.id == id } ?? 0
        workspace.resources.removeAll { $0.id == id }
        workspace.selectedResourceIDs.remove(id)
        resourceDrafts[id] = nil
        selectedResourceID = workspace.resources.isEmpty ? nil : workspace.resources[min(index, workspace.resources.count - 1)].id
    }
}

struct WorkspaceEditor: View {
    @Bindable var draft: WorkspaceDraft
    let store: WorkspaceStore
    var onSave: () -> Void
    var onClose: () -> Void
    var restoreFocus: () -> Void
    @FocusState private var nameFocused: Bool
    @FocusState private var listFocused: Bool

    var body: some View {
        Group {
            if let resource = draft.resourceEditor {
                SavedActionEditor(draft: resource, allowsShortcuts: false, onSave: draft.saveResource) {
                    draft.resourceEditor = nil
                    restoreFocus()
                    listFocused = true
                }
            } else {
                workspaceFields
            }
        }
    }

    private var workspaceFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("Workspace name", text: $draft.workspace.name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15, weight: .semibold))
                    .focused($nameFocused)
                    .accessibilityLabel("Workspace name")
                    .onSubmit { nameFocused = false; listFocused = true }
                Spacer(minLength: 12)
                Button("Back", action: onClose).buttonStyle(.plain)
            }
            Text("Selected resources open together.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(draft.workspace.resources) { resource in
                            Button { draft.selectedResourceID = resource.id; draft.toggleSelected() } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: draft.workspace.selectedResourceIDs.contains(resource.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(draft.workspace.selectedResourceIDs.contains(resource.id) ? .primary : .secondary)
                                    Image(systemName: resource.destination.kind.symbol).frame(width: 18).foregroundStyle(.secondary)
                                    Text(resource.name).lineLimit(1)
                                    Spacer()
                                }
                                .padding(.horizontal, 10).padding(.vertical, 10)
                                .contentShape(Rectangle())
                                .background(.white.opacity(draft.selectedResourceID == resource.id ? 0.09 : 0), in: .rect(cornerRadius: 12))
                            }
                            .buttonStyle(.plain).focusable(false)
                            .accessibilityLabel("\(resource.name), \(draft.workspace.selectedResourceIDs.contains(resource.id) ? "included" : "excluded")")
                            .id(resource.id)
                        }
                        if draft.workspace.resources.isEmpty {
                            Text("Add the apps, folders and links you use together.")
                                .font(.system(size: 12)).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity).padding(.vertical, 18)
                        }
                    }
                }
                .onChange(of: draft.selectedResourceID) { _, id in if let id { proxy.scrollTo(id) } }
            }
            .focusable(interactions: .edit).focused($listFocused).focusEffectDisabled()
            .onAppletFocusRestore {
                nameFocused = false
                listFocused = true
            }
            .onKeyPress(keys: [.upArrow, .downArrow], phases: [.down, .repeat]) { key in
                guard key.modifiers.intersection([.command, .control, .option, .shift]).isEmpty else { return .ignored }
                return draft.moveSelection(key.key == .upArrow ? -1 : 1) ? .handled : .ignored
            }
            .onKeyPress(keys: [.space], phases: .down) { key in
                guard key.modifiers.intersection([.command, .control, .option, .shift]).isEmpty else { return .ignored }
                draft.toggleSelected()
                return .handled
            }
            .onKeyPress(keys: [.return], phases: .down) { key in
                guard key.modifiers.intersection([.command, .control, .option, .shift]).isEmpty else { return .ignored }
                guard let resource = draft.selectedResource else { draft.editResource(); return .handled }
                draft.editResource(resource)
                return .handled
            }
            HStack {
                Button("Add resource  ⌘N") { draft.editResource() }
                    .keyboardShortcut("n", modifiers: .command)
                Spacer()
                Button("Save  ⌘↵", action: onSave)
                    .buttonStyle(FloatingControlStyle())
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!store.canSave)
            }.buttonStyle(.plain)
            ActionFeedback(error: store.error, result: nil)
            Text("↑↓ choose · Space include · ↵ edit · ⌘K actions · Esc back")
                .font(.system(size: 10)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 12)
        }
        .font(.system(size: 12))
        .padding(20)
        .task {
            await Task.yield()
            if draft.workspace.name.isEmpty { nameFocused = true }
            else { listFocused = true }
        }
        .onChange(of: nameFocused) { _, focused in if !focused { listFocused = true } }
        .onKeyPress(.escape) {
            if nameFocused { nameFocused = false; listFocused = true }
            else { onClose() }
            return .handled
        }
        .onKeyPress(keys: ["e", .delete], phases: .down) { key in
            guard key.modifiers.contains(.command), let resource = draft.selectedResource else { return .ignored }
            if key.key == "e" { draft.editResource(resource) }
            else { draft.removeSelected() }
            return .handled
        }
    }
}
