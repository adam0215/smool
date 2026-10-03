import Foundation

@main
struct NotesAppletChecks {
    @MainActor
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "smool-notes-applet-checks-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "notes.json")
        let store = NotesStore(fileURL: url)
        var codexDraft: String?
        let applet = NotesApplet(store: store, onSendToCodex: { codexDraft = $0 })
        precondition(applet.id.rawValue == "notes" && applet.title == "Notes")
        precondition(!applet.handleArrow(.down, command: false))
        let first = applet.createNote(text: "Selected text")!
        precondition(applet.isEditing && store.selectedNote?.text == "Selected text")
        applet.actions.first { $0.id == "Open in Codex" }!.perform()
        precondition(codexDraft == "Selected text", "Codex receives the note as a draft")
        precondition(!applet.handleArrow(.down, command: false), "Editor keeps arrow keys for caret navigation")
        let second = applet.createNote(text: "Second")!
        applet.isEditing = false
        precondition(!applet.handleArrow(.down, command: true))
        precondition(applet.handleArrow(.down, command: false) && store.selectedID == first)
        precondition(applet.handleArrow(.down, command: false) && store.selectedID == first)
        precondition(applet.handleArrow(.up, command: false) && store.selectedID == second)
        applet.actions.first { $0.id == "Delete note" }!.perform()
        precondition(applet.hasPresentedOverlay && !applet.handleArrow(.down, command: false))
        applet.dismissOverlay()
        precondition(!applet.hasPresentedOverlay && store.notes.count == 2, "Cancelling deletion keeps both notes")
        store.update(second, text: "Flush on leaving")
        applet.finishEditing()
        precondition(!applet.isEditing && !store.hasUnsavedChanges)
        precondition(NotesStore(fileURL: url).selectedNote?.text == "Flush on leaving", "Leaving the editor preserves its text on disk")
        applet.deactivate()
        let restored = NotesApplet(store: NotesStore(fileURL: url))
        precondition(restored.isEditing && restored.store.selectedNote?.text == "Flush on leaving")
        precondition(restored.hasPresentedOverlay)
        restored.requestDeletion()
        restored.dismissOverlay()
        precondition(restored.isEditing && restored.store.notes.count == 2, "Cancelling deletion returns to the draft")
        restored.dismissOverlay()
        precondition(!restored.isEditing && !restored.hasPresentedOverlay, "Escape leaves editing before the host closes")
        restored.requestDeletion()
        restored.confirmDeletion()
        precondition(restored.store.notes.count == 1 && restored.store.selectedID == first)
        precondition(!restored.isEditing && !restored.hasPresentedOverlay, "Deleting returns to note navigation")
        restored.requestDeletion()
        restored.confirmDeletion()
        precondition(restored.store.notes.isEmpty && !restored.isEditing)
        precondition(!restored.actions.contains { $0.id == "Delete note" || $0.id == "Open in Codex" })
        print("Notes applet checks passed")
    }
}
