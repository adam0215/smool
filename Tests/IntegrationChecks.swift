import SwiftUI

@main
struct IntegrationChecks {
    @MainActor static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "smool-integration-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suite = "smool.integration.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let notes = NotesApplet(store: NotesStore(fileURL: directory.appending(path: "notes.json")))
        let files = FilesApplet(store: FileShelfStore(storageURL: directory.appending(path: "files.json")))
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let timers = TimersApplet(store: TimerStore(storageURL: nil, now: { now }, automaticallySchedules: false, completion: {}))
        let codex = CodexApplet()
        let settings = AppSettings(defaults: defaults)
        let presentation = NotchPresentation(registry: AppletRegistry([HomeApplet(), notes, files, timers, codex]), settings: settings)

        let text = "En idé från markerad text\n  med indrag"
        precondition(presentation.saveCapturedNote(text) == notes.id)
        precondition(notes.store.selectedNote?.text == text && notes.isEditing)
        let restored = NotesStore(fileURL: directory.appending(path: "notes.json"))
        precondition(restored.selectedNote?.text == text)
        precondition(presentation.prepareCodexDraft(text) == codex.id)
        precondition(codex.state.showsRecipientPicker && codex.state.pendingText == text)
        precondition(!codex.service.isSending && codex.service.drafts.isEmpty, "A handoff must never submit or pick a recipient")
        settings.setEnabled(false, for: codex.id)
        precondition(presentation.prepareCodexDraft("Do not send") == nil)
        precondition(codex.state.pendingText == text)

        let file = directory.appending(path: "reference.txt")
        try Data("A file reference".utf8).write(to: file)
        precondition(presentation.addFiles([file]) == files.id)
        await files.store.finishPendingChanges()
        precondition(files.store.files.count == 1)
        files.store.remove(id: files.store.files[0].id)
        await files.store.finishPendingChanges()
        precondition(files.store.files.isEmpty && FileManager.default.fileExists(atPath: file.path))
        settings.setEnabled(false, for: files.id)
        precondition(presentation.addFiles([file]) == nil)

        let id = try timers.store.start(input: "25 min", name: "Pasta")
        precondition(presentation.statusItems.count == 1)
        precondition(presentation.statusItems[0].status.countdownDeadline == now.addingTimeInterval(1500))
        timers.store.pause(id)
        precondition(presentation.statusItems[0].status.countdownDeadline == nil)
        timers.isCreating = true
        timers.activateStatus()
        precondition(!timers.isCreating && timers.selectedID == id)
        settings.showTimerStatus = false
        precondition(presentation.statusItems.isEmpty)
        settings.showTimerStatus = true
        settings.setEnabled(false, for: timers.id)
        precondition(presentation.statusItems.isEmpty, "Disabled applets must leave the closed notch")

        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let layout = NotchLayout(screenFrame: screen, notch: .physical(ScreenNotch.referenceSize))
        let size = NotchStatusView.size(layout: layout, hasStatus: true)
        precondition(size.width == 409 && size.height == 32)
        precondition(NotchStatusView.size(layout: layout, hasStatus: false) == layout.collapsedSize)
        let noNotch = NotchLayout(screenFrame: screen)
        precondition(NotchStatusView.size(layout: noNotch, hasStatus: true).width == 224)
        precondition(NotchStatusView.size(layout: noNotch, hasStatus: false).height == 0)

        if let output = CommandLine.arguments.dropFirst().first {
            let items = [
                NotchStatusItem(id: timers.id, status: AppletStatus(kind: .working, label: "Pasta 24:59", symbol: "timer")),
                NotchStatusItem(id: codex.id, status: AppletStatus(kind: .needsAttention, label: "Väntar på dig", symbol: "bubble.left"))
            ]
            let view = NotchStatusView(items: items, layout: layout, activate: { _ in })
                .frame(width: size.width, height: size.height).background(.black).environment(\.colorScheme, .dark)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            guard let image = renderer.cgImage,
                  let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
                preconditionFailure("Closed-notch status did not render")
            }
            try data.write(to: URL(fileURLWithPath: output).appending(path: "integrated-status.png"))
        }
        await presentation.finishPendingChanges()
        print("Passed: cross-applet drafts, notes persistence, file drops, status preferences, routing and camera clearance.")
    }
}
