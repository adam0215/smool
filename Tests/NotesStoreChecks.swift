@testable import SmoolChecksSupport
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
        expect(await store.flush())
        precondition(!store.hasUnsavedChanges && store.errorMessage == nil)

        let restored = NotesStore(fileURL: url)
        precondition(restored.selectedID == first)
        precondition(restored.notes.map(\.id) == [draft, first])
        precondition(restored.notes[0].text.isEmpty, "Empty drafts must survive restart")
        precondition(restored.notes[1].text == "Edited\nBody 📝")
        restored.delete(first)
        expect(await restored.flush())
        precondition(restored.selectedID == draft)
        precondition(NotesStore(fileURL: url).notes.count == 1)
        restored.delete(draft)
        expect(await restored.flush())
        precondition(restored.selectedID == nil && restored.notes.isEmpty)

        let saved = store.createNote(text: "debounced")!
        try await Task.sleep(for: .milliseconds(100))
        precondition(NotesStore(fileURL: url).selectedNote?.text == "debounced")
        store.update(saved, text: "latest flush")
        expect(await store.flush())
        try await Task.sleep(for: .milliseconds(40))
        precondition(NotesStore(fileURL: url).selectedNote?.text == "latest flush")

        let corruptURL = directory.appending(path: "corrupt.json")
        let corruptData = Data("invalid json".utf8)
        try corruptData.write(to: corruptURL)
        let corrupt = NotesStore(fileURL: corruptURL)
        precondition(corrupt.isReadOnly && corrupt.errorMessage != nil)
        precondition(corrupt.createNote(text: "must not replace original") == nil)
        expect(await corrupt.flush())
        let preservedData = try Data(contentsOf: corruptURL)
        precondition(preservedData == corruptData)

        let blocker = directory.appending(path: "blocker")
        let failing = NotesStore(fileURL: blocker.appending(path: "notes.json"))
        let unsaved = failing.createNote(text: "Keep this text")!
        try Data().write(to: blocker)
        expect(await failing.flush() == false)
        precondition(failing.errorMessage != nil && failing.hasUnsavedChanges)
        precondition(failing.selectedNote?.id == unsaved && failing.selectedNote?.text == "Keep this text")
        try FileManager.default.removeItem(at: blocker)
        expect(await failing.flush())
        precondition(failing.errorMessage == nil && !failing.hasUnsavedChanges)
        precondition(NotesStore(fileURL: blocker.appending(path: "notes.json")).selectedNote?.text == "Keep this text")
        let racingURL = directory.appending(path: "racing.json")
        let racing = NotesStore(fileURL: racingURL, debounce: .seconds(60))
        let largeText = String(repeating: "Long note text.\n", count: 1_000_000)
        let racingID = racing.createNote(text: largeText)!
        racing.requestSave()
        let draining = Task { await racing.flush() }
        await Task.yield()
        racing.update(racingID, text: "Edited while saving")
        racing.requestSave()
        expect(await draining.value)
        precondition(!racing.hasUnsavedChanges)
        precondition(NotesStore(fileURL: racingURL).selectedNote?.text == "Edited while saving")

        for index in 0..<20 {
            racing.update(racingID, text: "Revision \(index)")
            racing.requestSave()
        }
        expect(await racing.flush())
        precondition(NotesStore(fileURL: racingURL).selectedNote?.text == "Revision 19")
        precondition(racing.errorMessage == nil && !racing.hasUnsavedChanges)
        print("Notes store checks passed")
    }

    static func expect(_ result: Bool) { precondition(result) }
}
