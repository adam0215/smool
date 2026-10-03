import SwiftUI

@MainActor @Observable
final class ActionEditorRequest: Identifiable {
    let id = UUID()
    let action: SavedAction?
    var name: String
    var input: String
    var destination: ActionDestination?
    var usesShortcut: Bool

    init(action: SavedAction? = nil) {
        self.action = action
        name = action?.name ?? ""
        input = action?.destination.detail ?? ""
        destination = action?.destination
        usesShortcut = action?.destination.kind == .shortcut
    }

    func savedAction() throws -> SavedAction {
        let resolved: ActionDestination
        if let destination, destination.detail == input, (destination.kind == .shortcut) == usesShortcut {
            resolved = destination
        } else if usesShortcut {
            throw ActionFailure(message: "Choose a shortcut first.")
        } else {
            resolved = try .inferred(input)
        }
        let enteredName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return SavedAction(id: action?.id ?? id, name: enteredName.isEmpty ? resolved.suggestedName : enteredName, destination: resolved)
    }
}

struct SavedActionEditor: View {
    @Bindable var draft: ActionEditorRequest
    var allowsShortcuts: Bool
    var onSave: (SavedAction) -> Bool
    var onClose: () -> Void
    @State private var shortcuts: [AvailableShortcut] = []
    @State private var loading = false
    @State private var error: String?
    @FocusState private var field: Field?

    private enum Field: Hashable { case destination, name }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(draft.action.map { "Edit \($0.name)" } ?? (allowsShortcuts ? "Save an action" : "Add a resource"))
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Spacer()
                Button("Back", action: onClose).buttonStyle(.plain)
            }

            if draft.usesShortcut {
                shortcutFields
            } else {
                TextField("App name, folder path, website or Codex thread", text: $draft.input)
                    .focused($field, equals: .destination)
                    .accessibilityLabel("Resource")
                    .onSubmit(save)
                HStack {
                    Text("Examples: Safari, ~/Documents, example.com")
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    if allowsShortcuts {
                        Button("Shortcut ⌘J") {
                            draft.usesShortcut = true
                            field = nil
                            Task { await loadShortcuts() }
                        }.keyboardShortcut("j", modifiers: .command)
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 10))
            }

            TextField("Name (optional)", text: $draft.name)
                .focused($field, equals: .name)
                .accessibilityLabel("Optional name")
                .onSubmit(save)

            if let error {
                Text(error).font(.system(size: 11)).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Text("Tab fields · Esc back · draft kept")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Button("Save  ⌘↵", action: save)
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .font(.system(size: 12))
        .textFieldStyle(EditorTextFieldStyle())
        .padding(20)
        .modifier(FloatingGlass(cornerRadius: NotchLayout.bottomRadius - NotchLayout.contentInset, cornerStyle: .circular))
        .task { await Task.yield(); field = .destination }
        .onKeyPress(.escape) {
            if field != nil { field = nil }
            else { onClose() }
            return .handled
        }
    }

    private var shortcutFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(shortcutName).lineLimit(1)
                Spacer()
                Button("↑") { moveShortcut(-1) }.keyboardShortcut(.upArrow, modifiers: .option)
                    .accessibilityLabel("Previous shortcut")
                Button("↓") { moveShortcut(1) }.keyboardShortcut(.downArrow, modifiers: .option)
                    .accessibilityLabel("Next shortcut")
            }
            HStack {
                Text("⌥↑↓ choose shortcut").foregroundStyle(.secondary)
                Spacer()
                Button(loading ? "Loading…" : "Reload ⌘R") { Task { await loadShortcuts() } }
                    .keyboardShortcut("r", modifiers: .command).disabled(loading)
                Button("Link or app ⌘J") { draft.usesShortcut = false; field = .destination }
                    .keyboardShortcut("j", modifiers: .command)
            }
            .font(.system(size: 10))
        }
        .buttonStyle(.plain)
        .task {
            if case .shortcut(let id, let name) = draft.destination {
                shortcuts = [AvailableShortcut(id: id, name: name)]
            }
            await loadShortcuts()
        }
    }

    private var shortcutName: String {
        if case .shortcut(_, let name) = draft.destination { return name }
        return loading ? "Loading shortcuts…" : "Choose a shortcut with ⌥↓"
    }

    private func moveShortcut(_ offset: Int) {
        guard !shortcuts.isEmpty else { return }
        let selectedID: UUID?
        if case .shortcut(let id, _) = draft.destination { selectedID = id }
        else { selectedID = nil }
        let index = shortcuts.firstIndex { $0.id == selectedID } ?? (offset > 0 ? -1 : 0)
        let shortcut = shortcuts[(index + offset + shortcuts.count) % shortcuts.count]
        draft.destination = .shortcut(id: shortcut.id, name: shortcut.name)
        draft.input = shortcut.name
    }

    private func loadShortcuts() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            shortcuts = try await ShortcutCatalog.load()
            error = shortcuts.isEmpty ? "No shortcuts found. Create one in Shortcuts." : nil
        } catch { self.error = error.localizedDescription }
    }

    private func save() {
        do {
            let action = try draft.savedAction()
            try validateActions([action], allowShortcuts: allowsShortcuts)
            if onSave(action) { onClose() }
            else { error = "Could not save. Your changes are still here." }
        } catch { self.error = error.localizedDescription }
    }
}

struct ActionFeedback: View {
    var error: String?
    var result: String?

    var body: some View {
        if let error {
            ScrollView { Text(error).foregroundStyle(.red).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                .font(.system(size: 11)).frame(maxHeight: 48)
        } else if let result {
            Text(result).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
        }
    }
}

struct EditorTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .padding(.vertical, 8)
            .overlay(alignment: .bottom) { Rectangle().fill(.primary.opacity(0.1)).frame(height: 1) }
    }
}
