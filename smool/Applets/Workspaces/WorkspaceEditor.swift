import SwiftUI

struct WorkspaceEditor: View {
    @State var workspace: SavedWorkspace
    let store: WorkspaceStore
    var onSaved: (UUID) -> Void = { _ in }
    @Environment(\.dismiss) private var dismiss
    @State private var editor: ActionEditorRequest?
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Redigera arbetsyta").font(.headline)
            TextField("Arbetsytans namn", text: $workspace.name).textFieldStyle(.roundedBorder).focused($nameFocused)
            Text("Välj resurser som ska ingå när du öppnar arbetsytan.").font(.caption).foregroundStyle(.secondary)
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(workspace.resources) { resource in
                        HStack {
                            Toggle(isOn: Binding(get: { workspace.selectedResourceIDs.contains(resource.id) }, set: { selected in
                                if selected { workspace.selectedResourceIDs.insert(resource.id) }
                                else { workspace.selectedResourceIDs.remove(resource.id) }
                            })) { Label(resource.name, systemImage: resource.destination.kind.symbol).lineLimit(1) }
                                .toggleStyle(.checkbox)
                            Spacer()
                            Button { editor = ActionEditorRequest(action: resource) } label: { Image(systemName: "pencil") }
                                .accessibilityLabel("Redigera \(resource.name)")
                            Button(role: .destructive) {
                                workspace.resources.removeAll { $0.id == resource.id }
                                workspace.selectedResourceIDs.remove(resource.id)
                            } label: { Image(systemName: "trash") }
                                .accessibilityLabel("Ta bort \(resource.name)")
                        }
                    }
                }
            }.frame(height: 180)
            Button("Lägg till resurs", systemImage: "plus") { editor = ActionEditorRequest() }
            ActionFeedback(error: store.error, result: nil)
            HStack {
                Button("Avbryt") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Spara") {
                    if store.save(workspace) { onSaved(workspace.id); dismiss() }
                }
                    .keyboardShortcut(.defaultAction)
                    .disabled(workspace.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !store.canSave)
            }
        }
        .padding(20).frame(width: 430)
        .task { nameFocused = true }
        .sheet(item: $editor) { request in
            SavedActionEditor(original: request.action, allowsShortcuts: false) { action in
                if let index = workspace.resources.firstIndex(where: { $0.id == action.id }) { workspace.resources[index] = action }
                else { workspace.resources.append(action); workspace.selectedResourceIDs.insert(action.id) }
                return true
            }
        }
    }
}
