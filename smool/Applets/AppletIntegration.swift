import Foundation
import Observation

@MainActor @Observable
final class CapturedSelection {
    let preview: SelectionPreview
    var noteID: UUID?
    var isSaving = false
    var saveError: String?

    init(preview: SelectionPreview) { self.preview = preview }
}

/// Cross-applet handoffs live at the composition boundary. Feature views only use AppletContext.
extension NotchPresentation {
    func connectAppletCommands() {
        let context = AppletCommandContext(
            hostActions: { [weak self] in self?.hostActions ?? [] },
            composeInCodex: { [weak self] in
                guard let self, settings.isEnabled(AppletID(rawValue: "codex")) else { return nil }
                return composeInCodex
            }
        )
        (registeredApplets.applet(for: AppletID(rawValue: "notes")) as? NotesApplet)?.commandContext = context
        (registeredApplets.applet(for: AppletID(rawValue: "quick-actions")) as? QuickActionsApplet)?.commandContext = context
    }

    var statusItems: [NotchStatusItem] {
        let preferences: [(String, Bool)] = [
            ("timers", settings.showTimerStatus),
            ("codex", settings.showCodexStatus)
        ]
        return preferences.compactMap { name, visible in
            guard visible, let applet = registry.applet(for: AppletID(rawValue: name)),
                  let status = applet.status else { return nil }
            return NotchStatusItem(id: applet.id, status: status)
        }
    }

    func updateBackgroundServices() {
        let id = AppletID(rawValue: "codex")
        let codex = registeredApplets.applet(for: id) as? CodexApplet
        codex?.setStatusMonitoring(settings.isEnabled(id) && settings.showCodexStatus)
    }

    func stopBackgroundServices() {
        (registeredApplets.applet(for: AppletID(rawValue: "codex")) as? CodexApplet)?.setStatusMonitoring(false)
    }

    func prepareCodexDraft(_ text: String) -> AppletID? {
        let id = AppletID(rawValue: "codex")
        guard let codex = registry.applet(for: id) as? CodexApplet else { return nil }
        codex.beginComposing(text)
        return id
    }

    private var notes: NotesApplet? {
        registeredApplets.applet(for: AppletID(rawValue: "notes")) as? NotesApplet
    }

    var canSaveCapturedNote: Bool {
        settings.isEnabled(AppletID(rawValue: "notes")) && notes?.store.isReadOnly == false && capture?.isSaving == false
    }

    var capturedNoteUnavailableReason: String? {
        if notes?.store.isReadOnly == true { return "Notes could not be loaded. Your selection is still here." }
        if capture?.isSaving == true { return "Saving your note…" }
        return nil
    }

    func saveCapturedNote() async -> AppletID? {
        guard canSaveCapturedNote, let capture, let text = capture.preview.selection?.text, let notes else { return nil }
        capture.isSaving = true
        capture.saveError = nil
        defer { capture.isSaving = false }

        if capture.noteID == nil || !notes.store.notes.contains(where: { $0.id == capture.noteID }) {
            guard let id = notes.createNote(text: text) else { return nil }
            capture.noteID = id
        }
        guard await notes.store.flush() else {
            capture.saveError = notes.store.errorMessage
            return nil
        }
        guard self.capture === capture, settings.isEnabled(notes.id) else { return nil }
        dismissPresentation()
        return notes.id
    }

    var canRetryPendingChanges: Bool { failedSaveAppletID == AppletID(rawValue: "notes") }

    func retryPendingChanges() async {
        _ = await flushPendingChanges()
    }

    func addFiles(_ urls: [URL]) -> AppletID? {
        let id = AppletID(rawValue: "files")
        guard let files = registry.applet(for: id) as? FilesApplet else { return nil }
        files.add(urls: urls)
        return id
    }

    @discardableResult
    func finishPendingChanges() async -> Bool {
        guard await flushPendingChanges() else { return false }
        for applet in registeredApplets.applets { applet.deactivate() }
        return true
    }

    private func flushPendingChanges() async -> Bool {
        let notes = self.notes
        let files = registeredApplets.applet(for: AppletID(rawValue: "files")) as? FilesApplet
        let actions = registeredApplets.applet(for: NotchHostTool.actions.appletID) as? QuickActionsApplet
        let workspaces = registeredApplets.applet(for: NotchHostTool.workspaces.appletID) as? WorkspacesApplet
        let initialActionFailure = actions?.store.failedWriteGeneration
        let initialWorkspaceFailure = workspaces?.store.failedWriteGeneration

        var failures: [String] = []
        var firstFailure: AppletID?
        repeat {
            // Drain together, then check for edits made while another store was saving.
            async let notesSaved = notes?.store.flush()
            async let filesFinished: Void? = files?.store.finishPendingChanges()
            async let actionsSaved = actions?.store.finishPendingChanges()
            async let workspacesSaved = workspaces?.store.finishPendingChanges()
            let results = await (notesSaved, filesFinished, actionsSaved, workspacesSaved)

            if results.0 == false {
                failures.append("Notes")
                firstFailure = notes?.id
            }
            if results.2 == false || actions?.store.failedWriteGeneration != initialActionFailure {
                failures.append("Actions")
                firstFailure = firstFailure ?? actions?.id
            }
            if results.3 == false || workspaces?.store.failedWriteGeneration != initialWorkspaceFailure {
                failures.append("Workspaces")
                firstFailure = firstFailure ?? workspaces?.id
            }
            // A failed write aborts this quit attempt; another pass must not hide it.
            if !failures.isEmpty { break }
        } while notes?.store.hasUnsavedChanges == true || files?.store.isLoading == true
            || actions?.store.hasPendingChanges == true || workspaces?.store.hasPendingChanges == true

        failedSaveAppletID = firstFailure
        if failures.isEmpty { terminationError = nil }
        else {
            let recovery = firstFailure == AppletID(rawValue: "notes")
                ? "Your text is still in smool. Try saving again before quitting."
                : "Return to \(failures.first!) and save your changes again before quitting."
            terminationError = "Changes to \(failures.joined(separator: ", ")) could not be saved. \(recovery)"
        }
        return failures.isEmpty
    }
}
