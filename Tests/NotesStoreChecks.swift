import Foundation

@main
struct NotesStoreChecks {
    @MainActor
    static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "smool-notes-checks-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "nested/notes.json")
        let store = NotesStore(fileURL: url, debounce: .milliseconds(10))
        precondition(store.notes.isEmpty && !store.isReadOnly)

        let first = store.createNote(text: "\n First line\nBody")!
        let draft = store.createNote()!
        precondition(store.notes.map(\.id) == [draft, first])
        precondition(store.notes[1].title == "First line")
        store.select(first)
        store.update(first, text: "Edited\nBody 📝")
        precondition(store.notes.map(\.id) == [draft, first], "Editing must not reorder the list")
        store.flush()
        precondition(!store.hasUnsavedChanges && store.errorMessage == nil)

        let restored = NotesStore(fileURL: url)
        precondition(restored.selectedID == first)
        precondition(restored.notes.map(\.id) == [draft, first])
        precondition(restored.notes[0].text.isEmpty, "Empty drafts must survive restart")
        precondition(restored.notes[1].text == "Edited\nBody 📝")
        restored.delete(first)
        precondition(restored.selectedID == draft)
        precondition(NotesStore(fileURL: url).notes.count == 1)
        restored.delete(draft)
        precondition(restored.selectedID == nil && restored.notes.isEmpty)

        let saved = store.createNote(text: "debounced")!
        try await Task.sleep(for: .milliseconds(100))
        precondition(NotesStore(fileURL: url).selectedNote?.text == "debounced")
        store.update(saved, text: "latest flush")
        store.flush()
        try await Task.sleep(for: .milliseconds(40))
        precondition(NotesStore(fileURL: url).selectedNote?.text == "latest flush")

        let corruptURL = directory.appending(path: "corrupt.json")
        let corruptData = Data("invalid json".utf8)
        try corruptData.write(to: corruptURL)
        let corrupt = NotesStore(fileURL: corruptURL)
        precondition(corrupt.isReadOnly && corrupt.errorMessage != nil)
        precondition(corrupt.createNote(text: "must not replace original") == nil)
        corrupt.flush()
        let preservedData = try Data(contentsOf: corruptURL)
        precondition(preservedData == corruptData)

        let blocker = directory.appending(path: "blocker")
        let failing = NotesStore(fileURL: blocker.appending(path: "notes.json"))
        let unsaved = failing.createNote(text: "Keep this text")!
        try Data().write(to: blocker)
        failing.flush()
        precondition(failing.errorMessage != nil && failing.hasUnsavedChanges)
        precondition(failing.selectedNote?.id == unsaved && failing.selectedNote?.text == "Keep this text")
        try FileManager.default.removeItem(at: blocker)
        failing.flush()
        precondition(failing.errorMessage == nil && !failing.hasUnsavedChanges)
        precondition(NotesStore(fileURL: blocker.appending(path: "notes.json")).selectedNote?.text == "Keep this text")
        print("Notes store checks passed")
    }
}
