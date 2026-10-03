import Foundation

@main
struct FilesAppletChecks {
    @MainActor static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "smool-files-applet-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = directory.appending(path: "First file.txt")
        let second = directory.appending(path: "Second file.txt")
        try Data("First".utf8).write(to: first)
        try Data("Second".utf8).write(to: second)
        let store = FileShelfStore(storageURL: directory.appending(path: "shelf.json"))
        let applet = FilesApplet(store: store)

        applet.actions.first { $0.id == "Add files" }!.perform()
        precondition(applet.showsPathEntry && applet.hasPresentedOverlay)
        applet.pathDraft = "An unfinished path"
        applet.dismissOverlay()
        precondition(!applet.hasPresentedOverlay && applet.pathDraft == "An unfinished path")
        applet.openPathEntry()
        applet.addPaths()
        precondition(applet.showsPathEntry && applet.pathError != nil && store.files.isEmpty)

        applet.pathDraft = "\"\(first.path)\"\n\(second.absoluteString)"
        let draft = applet.pathDraft
        applet.addPaths()
        await store.finishPendingChanges()
        precondition(!applet.hasPresentedOverlay && applet.pathError == nil)
        precondition(store.files.count == 2)
        precondition(Set(store.files.compactMap(\.url).map { $0.resolvingSymlinksInPath() }) == Set([first, second].map { $0.resolvingSymlinksInPath() }))
        precondition(applet.pathDraft == draft, "Entered paths remain available when reopening the editor")

        applet.showPreview(first)
        precondition(applet.hasPresentedOverlay && applet.previewURL == first && applet.contentHeight > 212)
        precondition(!applet.handleArrow(.down, command: false), "Preview keeps keyboard navigation within its content")
        applet.dismissOverlay()
        precondition(applet.previewURL == nil && applet.contentHeight == 212)
        precondition(applet.handleArrow(.down, command: false))

        applet.showPreview(second)
        applet.openPathEntry()
        precondition(applet.previewURL == nil && applet.showsPathEntry && applet.pathDraft == draft)
        applet.deactivate()
        precondition(!applet.hasPresentedOverlay && applet.pathDraft == draft)

        applet.openPathEntry()
        applet.pathDraft = directory.appending(path: "Missing file.txt").path
        applet.addPaths()
        await store.finishPendingChanges()
        precondition(store.error != nil && store.files.count == 2)
        precondition(!applet.pathDraft.isEmpty, "Failed additions retain the original path for correction")
        print("Files applet checks passed")
    }
}
