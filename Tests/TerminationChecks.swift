import Foundation

@main
struct TerminationChecks {
    @MainActor static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "smool-exit-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suite = "smool.exit.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let parent = directory.appending(path: "notes")
        let url = parent.appending(path: "notes.json")
        let store = NotesStore(fileURL: url)
        let notes = NotesApplet(store: store)
        let settings = AppSettings(defaults: defaults)
        let presentation = NotchPresentation(registry: AppletRegistry([HomeApplet(), notes]), settings: settings)
        settings.setEnabled(false, for: notes.id)

        let id = store.createNote(text: "Must survive a failed save")!
        try Data().write(to: parent)
        let canQuit = await presentation.finishPendingChanges()
        precondition(!canQuit, "Unsaved notes must prevent exit even when their applet is disabled")
        precondition(store.hasUnsavedChanges && store.selectedNote?.id == id)
        precondition(store.selectedNote?.text == "Must survive a failed save")

        try FileManager.default.removeItem(at: parent)
        let canRetry = await presentation.finishPendingChanges()
        precondition(canRetry && !store.hasUnsavedChanges)
        precondition(NotesStore(fileURL: url).selectedNote?.text == "Must survive a failed save")
        print("Passed: failed save prevents termination, preserves text and supports retry.")
    }
}
