import SwiftUI
import UniformTypeIdentifiers

struct SavedActionEditor: View {
    var original: SavedAction?
    var allowsShortcuts: Bool
    var onSave: (SavedAction) -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var kind = ActionKind.website
    @State private var text = ""
    @State private var localDestination: ActionDestination?
    @State private var shortcuts: [AvailableShortcut] = []
    @State private var shortcutID: UUID?
    @State private var openPanel: NSOpenPanel?
    @State private var loading = false
    @State private var error: String?
    @FocusState private var nameFocused: Bool

    private var kinds: [ActionKind] {
        allowsShortcuts ? [.application, .folder, .website, .shortcut] : [.application, .folder, .website, .codexThread]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(original == nil ? "Add resource" : "Edit resource")
                .font(.system(size: 14, weight: .semibold))

            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Name").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                    TextField("Resource name", text: $name)
                        .focused($nameFocused)
                        .accessibilityLabel("Name")
                }

                Picker("Type", selection: $kind) {
                    ForEach(kinds) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
                .controlSize(.regular)

                destinationFields
            }

            if let error {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .controlSize(.regular)
        }
        .font(.system(size: 12))
        .textFieldStyle(EditorTextFieldStyle())
        .padding(20)
        .frame(width: 380)
        .task {
            if let original {
                name = original.name
                kind = original.destination.kind
                text = original.destination.detail
                localDestination = original.destination
                if case .shortcut(let id, let name) = original.destination {
                    shortcutID = id
                    shortcuts = [AvailableShortcut(id: id, name: name)]
                }
            }
            nameFocused = true
        }
        .onChange(of: kind) { _, _ in
            cancelLocalPicker()
            error = nil
        }
        .onDisappear(perform: cancelLocalPicker)
    }

    @ViewBuilder
    private var destinationFields: some View {
        switch kind {
        case .application, .folder:
            VStack(alignment: .leading, spacing: 8) {
                Button(action: chooseLocal) {
                    Label(kind == .application ? "Choose app…" : "Choose folder…", systemImage: kind.symbol)
                }
                .disabled(openPanel != nil)

                if let localDestination, localDestination.kind == kind {
                    Text(localDestination.detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
            }
        case .website:
            TextField("https://example.com", text: $text)
                .accessibilityLabel("Website URL")
        case .codexThread:
            TextField("Thread ID or codex://threads/…", text: $text)
                .accessibilityLabel("Codex thread")
        case .shortcut:
            VStack(alignment: .leading, spacing: 10) {
                Picker("Shortcut", selection: $shortcutID) {
                    Text("Choose shortcut").tag(nil as UUID?)
                    ForEach(shortcuts) { Text($0.name).tag(Optional($0.id)) }
                }
                .pickerStyle(.menu)

                Button(loading ? "Loading…" : "Load my shortcuts") {
                    Task { await loadShortcuts() }
                }
                .disabled(loading)

                Text("The shortcut only runs when you choose Run in the list.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func chooseLocal() {
        guard openPanel == nil else { return }
        let selectedKind = kind
        let panel = NSOpenPanel()
        panel.canChooseFiles = selectedKind == .application
        panel.canChooseDirectories = selectedKind == .folder
        panel.allowsMultipleSelection = false
        if selectedKind == .application { panel.allowedContentTypes = [.applicationBundle] }
        panel.prompt = "Choose"
        openPanel = panel

        panel.begin { [weak panel] response in
            guard let panel, openPanel === panel else { return }
            openPanel = nil
            guard response == .OK, kind == selectedKind, let url = panel.url else { return }
            do {
                localDestination = try ActionDestination.local(url, kind: selectedKind)
                if name.isEmpty { name = url.deletingPathExtension().lastPathComponent }
                error = nil
            } catch { self.error = error.localizedDescription }
        }
    }

    private func cancelLocalPicker() {
        let panel = openPanel
        openPanel = nil
        panel?.cancel(nil)
    }

    private func loadShortcuts() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            shortcuts = try await ShortcutCatalog.load()
            error = shortcuts.isEmpty ? "No shortcuts found. Create one in the Shortcuts app." : nil
        } catch { self.error = error.localizedDescription }
    }

    private func save() {
        do {
            let destination: ActionDestination
            switch kind {
            case .website: destination = try .web(text)
            case .codexThread: destination = try .thread(text)
            case .application, .folder:
                guard let localDestination, localDestination.kind == kind else { throw ActionFailure(message: "Choose an app or folder first.") }
                destination = localDestination
            case .shortcut:
                guard let shortcut = shortcuts.first(where: { $0.id == shortcutID }) else { throw ActionFailure(message: "Choose a shortcut first.") }
                destination = .shortcut(id: shortcut.id, name: shortcut.name)
            }
            let action = SavedAction(id: original?.id ?? UUID(), name: name.trimmingCharacters(in: .whitespacesAndNewlines), destination: destination)
            try validateActions([action], allowShortcuts: allowsShortcuts)
            if onSave(action) { dismiss() }
            else { error = "Could not save. Your changes are still here." }
        } catch { self.error = error.localizedDescription }
    }
}

struct ActionEditorRequest: Identifiable {
    let id = UUID()
    var action: SavedAction?
}

struct ActionFeedback: View {
    var error: String?
    var result: String?

    var body: some View {
        if let error {
            ScrollView { Text(error).foregroundStyle(.red).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                .font(.system(size: 11)).frame(maxHeight: 64)
        } else if let result {
            Text(result).font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }
}

struct EditorTextFieldStyle: TextFieldStyle {
    @Environment(\.colorSchemeContrast) private var contrast

    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .textFieldStyle(.plain)
            .font(.system(size: 12))
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(.primary.opacity(contrast == .increased ? 0.45 : 0.08), lineWidth: 1)
                    .allowsHitTesting(false)
            }
    }
}
