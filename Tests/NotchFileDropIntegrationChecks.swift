import SwiftUI

@main
struct NotchFileDropIntegrationChecks {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appending(path: "smool-notch-drop-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suite = "smool.notch-drop.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let file = directory.appending(path: "Dropped file.txt")
        try Data("Drag fixture".utf8).write(to: file)
        let files = FilesApplet(store: FileShelfStore(storageURL: directory.appending(path: "shelf.json")))
        let home = HomeApplet()
        let presentation = NotchPresentation(registry: AppletRegistry([home, files]), settings: AppSettings(defaults: defaults))
        let controller = NotchPanelController(presentation: presentation)

        precondition(controller.acceptDroppedFiles([file]))
        precondition(!controller.isOpen && presentation.selection == files.id,
                     "An empty closed shelf accepts files without becoming key or opening content")
        await files.store.finishPendingChanges()
        precondition(files.store.files.count == 1)
        precondition(FileManager.default.fileExists(atPath: file.path))

        presentation.select(home.id)
        presentation.capturedSelection = .text(SelectedText(text: "Preserve this captured draft", applicationName: "Drag check"))
        controller.open()
        let panel = NSApplication.shared.windows.compactMap { $0 as? NotchPanel }.first!
        let editor = NSTextView(frame: CGRect(x: 0, y: 0, width: 120, height: 40))
        editor.string = "An unfinished draft"
        panel.contentView!.addSubview(editor)
        panel.makeFirstResponder(editor)
        let wasKey = panel.isKeyWindow
        precondition(controller.acceptDroppedFiles([file]))
        precondition(controller.isOpen && presentation.selection == home.id && presentation.capturedSelection != nil)
        precondition(panel.firstResponder === editor && editor.string == "An unfinished draft")
        precondition(panel.isKeyWindow == wasKey)
        await files.store.finishPendingChanges()
        precondition(files.store.files.count == 1, "Repeated drops use the existing shelf deduplication")
        presentation.settings.setEnabled(false, for: files.id)
        precondition(!controller.acceptDroppedFiles([file]))
        precondition(!controller.acceptDroppedFiles([]))
        controller.stop()
        print("Passed: closed empty shelf import, open content and draft preservation, first-responder preservation and disabled Files")
    }
}
