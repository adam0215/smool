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
    @State private var loading = false
    @State private var error: String?
    @FocusState private var nameFocused: Bool

    private var kinds: [ActionKind] {
        allowsShortcuts ? [.application, .folder, .website, .shortcut] : [.application, .folder, .website, .codexThread]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(original == nil ? "Lägg till resurs" : "Redigera resurs").font(.headline)
            TextField("Namn", text: $name).focused($nameFocused)
            Picker("Typ", selection: $kind) {
                ForEach(kinds) { Text($0.title).tag($0) }
            }
            switch kind {
            case .application, .folder:
                Button(kind == .application ? "Välj app…" : "Välj mapp…", action: chooseLocal)
                if let localDestination, localDestination.kind == kind {
                    Text(localDestination.detail).font(.caption).lineLimit(2).truncationMode(.middle)
                }
            case .website:
                TextField("https://exempel.se", text: $text).accessibilityLabel("Webbadress")
            case .codexThread:
                TextField("Tråd-ID eller codex://threads/…", text: $text).accessibilityLabel("Codex-tråd")
            case .shortcut:
                Picker("Genväg", selection: $shortcutID) {
                    Text("Välj genväg").tag(nil as UUID?)
                    ForEach(shortcuts) { Text($0.name).tag(Optional($0.id)) }
                }
                Button(loading ? "Hämtar…" : "Hämta mina genvägar") { Task { await loadShortcuts() } }.disabled(loading)
                Text("Genvägen körs först när du väljer Kör i listan.").font(.caption).foregroundStyle(.secondary)
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
            HStack {
                Button("Avbryt") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Spara", action: save).keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .textFieldStyle(.roundedBorder)
        .padding(20).frame(width: 380)
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
        .onChange(of: kind) { _, _ in error = nil }
    }

    private func chooseLocal() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = kind == .application
        panel.canChooseDirectories = kind == .folder
        panel.allowsMultipleSelection = false
        if kind == .application { panel.allowedContentTypes = [.applicationBundle] }
        panel.prompt = "Välj"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                localDestination = try ActionDestination.local(url, kind: kind)
                if name.isEmpty { name = url.deletingPathExtension().lastPathComponent }
                error = nil
            } catch { self.error = error.localizedDescription }
        }
    }

    private func loadShortcuts() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            shortcuts = try await ShortcutCatalog.load()
            error = shortcuts.isEmpty ? "Inga genvägar hittades. Skapa en i appen Genvägar." : nil
        } catch { self.error = error.localizedDescription }
    }

    private func save() {
        do {
            let destination: ActionDestination
            switch kind {
            case .website: destination = try .web(text)
            case .codexThread: destination = try .thread(text)
            case .application, .folder:
                guard let localDestination, localDestination.kind == kind else { throw ActionFailure(message: "Välj en app eller mapp först.") }
                destination = localDestination
            case .shortcut:
                guard let shortcut = shortcuts.first(where: { $0.id == shortcutID }) else { throw ActionFailure(message: "Välj en genväg först.") }
                destination = .shortcut(id: shortcut.id, name: shortcut.name)
            }
            let action = SavedAction(id: original?.id ?? UUID(), name: name.trimmingCharacters(in: .whitespacesAndNewlines), destination: destination)
            try validateActions([action], allowShortcuts: allowsShortcuts)
            if onSave(action) { dismiss() }
            else { error = "Det gick inte att spara. Dina ändringar finns kvar här." }
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
                .font(.caption).frame(maxHeight: 64)
        } else if let result {
            Text(result).font(.caption).foregroundStyle(.secondary)
        }
    }
}
