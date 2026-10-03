import SwiftUI

struct WorkspaceEditor: View {
    @State var workspace: SavedWorkspace
    let store: WorkspaceStore
    var onSaved: (UUID) -> Void = { _ in }
    @Environment(\.dismiss) private var dismiss
    @State private var editor: ActionEditorRequest?
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Edit workspace")
                .font(.system(size: 14, weight: .semibold))

            VStack(alignment: .leading, spacing: 6) {
                Text("Name")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("Workspace name", text: $workspace.name)
                    .textFieldStyle(EditorTextFieldStyle())
                    .focused($nameFocused)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Choose what opens with this workspace.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(workspace.resources) { resource in
                            resourceRow(resource)
                        }
                    }
                }
                .overlay {
                    if workspace.resources.isEmpty {
                        VStack(spacing: 6) {
                            Image(systemName: "square.stack.3d.up")
                                .font(.system(size: 22, weight: .light))
                            Text("Add your first resource")
                                .font(.system(size: 12, weight: .medium))
                            Text("Apps, folders, websites and Codex threads")
                                .font(.system(size: 11))
                        }
                        .foregroundStyle(.secondary)
                    }
                }
                .frame(height: 180)

                Button("Add resource", systemImage: "plus") { editor = ActionEditorRequest() }
                    .buttonStyle(NotchControlStyle())
            }

            ActionFeedback(error: store.error, result: nil)

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") {
                    if store.save(workspace) {
                        onSaved(workspace.id)
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(workspace.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !store.canSave)
            }
            .controlSize(.regular)
        }
        .font(.system(size: 12))
        .padding(20)
        .frame(width: 430)
        .task { nameFocused = true }
        .sheet(item: $editor) { request in
            SavedActionEditor(original: request.action, allowsShortcuts: false) { action in
                if let index = workspace.resources.firstIndex(where: { $0.id == action.id }) {
                    workspace.resources[index] = action
                } else {
                    workspace.resources.append(action)
                    workspace.selectedResourceIDs.insert(action.id)
                }
                return true
            }
        }
    }

    private func resourceRow(_ resource: SavedAction) -> some View {
        HStack(spacing: 8) {
            Toggle(isOn: Binding(
                get: { workspace.selectedResourceIDs.contains(resource.id) },
                set: { selected in
                    if selected { workspace.selectedResourceIDs.insert(resource.id) }
                    else { workspace.selectedResourceIDs.remove(resource.id) }
                }
            )) {
                Label(resource.name, systemImage: resource.destination.kind.symbol)
                    .lineLimit(1)
            }
            .toggleStyle(.checkbox)

            Spacer(minLength: 4)

            Button { editor = ActionEditorRequest(action: resource) } label: {
                Image(systemName: "pencil").frame(width: 28, height: 28)
            }
            .accessibilityLabel("Edit \(resource.name)")
            .help("Edit resource")

            Button(role: .destructive) {
                workspace.resources.removeAll { $0.id == resource.id }
                workspace.selectedResourceIDs.remove(resource.id)
            } label: {
                Image(systemName: "trash").frame(width: 28, height: 28)
            }
            .accessibilityLabel("Remove \(resource.name)")
            .help("Remove resource")
        }
        .buttonStyle(.plain)
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .padding(.vertical, 6)
        .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
    }
}
