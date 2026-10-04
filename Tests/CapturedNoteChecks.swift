@testable import SmoolChecksSupport
import SwiftUI

@main
struct CapturedNoteChecks {
    @MainActor static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "smool-captured-note-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suite = "smool.capture.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let parent = directory.appending(path: "notes")
        let url = parent.appending(path: "notes.json")
        let notes = NotesApplet(store: NotesStore(fileURL: url))
        let presentation = NotchPresentation(registry: AppletRegistry([HomeApplet(), notes]), settings: AppSettings(defaults: defaults))
        func preview(_ text: String) -> SelectionPreview { .text(SelectedText(text: text, applicationName: "Fixture")) }

        presentation.presentCapturedSelection(preview("Keep the original captured text"))
        let capture = presentation.capture!
        try Data().write(to: parent)
        let failed = await presentation.saveCapturedNote()
        precondition(failed == nil && presentation.capture === capture)
        precondition(notes.store.notes.count == 1 && capture.noteID == notes.store.selectedID && capture.saveError != nil)
        let failedAgain = await presentation.saveCapturedNote()
        precondition(failedAgain == nil && notes.store.notes.count == 1, "A retry must reuse the same note.")
        try FileManager.default.removeItem(at: parent)
        let saved = await presentation.saveCapturedNote()
        precondition(saved == notes.id && presentation.capture == nil && notes.store.notes.count == 1)
        precondition(NotesStore(fileURL: url).notes.first?.text == "Keep the original captured text")

        presentation.presentCapturedSelection(preview("An earlier selection"))
        let earlier = presentation.capture!
        // Replace the visible selection as saving starts, before its async flush can return.
        withObservationTracking {
            _ = earlier.isSaving
        } onChange: {
            MainActor.assumeIsolated {
                presentation.presentCapturedSelection(.text(SelectedText(text: "The latest selection", applicationName: "Fixture")))
            }
        }
        let staleResult = await presentation.saveCapturedNote()
        precondition(staleResult == nil && presentation.capture !== earlier)
        precondition(presentation.capturedSelection?.selection?.text == "The latest selection")
        precondition(notes.store.notes.count == 2 && !notes.store.hasUnsavedChanges)
        let latestResult = await presentation.saveCapturedNote()
        precondition(latestResult == notes.id && notes.store.notes.count == 3)
        precondition(notes.store.selectedNote?.text == "The latest selection")
        print("Passed: capture save retry is idempotent, awaits persistence, preserves failed text and cannot dismiss a newer selection.")
    }
}
