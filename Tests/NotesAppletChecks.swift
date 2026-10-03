import Foundation

@main
struct NotesAppletChecks {
    @MainActor
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "smool-notes-applet-checks-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "notes.json")
        let store = NotesStore(fileURL: url)
        let applet = NotesApplet(store: store)
        precondition(applet.id.rawValue == "notes" && applet.title == "Anteckningar")
        precondition(!applet.handleArrow(.down, command: false))
        let first = applet.createNote(text: "Selected text")!
        precondition(applet.isEditing && store.selectedNote?.text == "Selected text")
        precondition(!applet.handleArrow(.down, command: false), "Editor keeps arrow keys for caret navigation")
        let second = applet.createNote(text: "Second")!
        applet.isEditing = false
        precondition(!applet.handleArrow(.down, command: true))
        precondition(applet.handleArrow(.down, command: false) && store.selectedID == first)
        precondition(applet.handleArrow(.down, command: false) && store.selectedID == first)
        precondition(applet.handleArrow(.up, command: false) && store.selectedID == second)
        applet.pendingDeletion = store.selectedNote
        precondition(applet.hasPresentedOverlay && !applet.handleArrow(.down, command: false))
        applet.dismissOverlay()
        precondition(!applet.hasPresentedOverlay)
        store.update(second, text: "Flush on leaving")
        applet.deactivate()
        let restored = NotesApplet(store: NotesStore(fileURL: url))
        precondition(restored.isEditing && restored.store.selectedNote?.text == "Flush on leaving")
        print("Notes applet checks passed")
    }
}
