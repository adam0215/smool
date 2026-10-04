import SwiftUI

@MainActor @Observable
final class FilesApplet: Applet {
    let id = AppletID(rawValue: "files")
    let title = "Files"
    let icon = AppletIcon.symbol("tray.full")
    let tint = Color.cyan
    let store: FileShelfStore
    var showsPathEntry = false
    var pathDraft = ""
    var pathError: String?
    var previewURL: URL?

    init(store: FileShelfStore? = nil) { self.store = store ?? FileShelfStore() }

    var contentHeight: CGFloat { previewURL != nil ? 340 : (showsPathEntry ? 244 : 212) }
    var hasPresentedOverlay: Bool { showsPathEntry || previewURL != nil }
    var status: AppletStatus? {
        store.error.map { AppletStatus(kind: .needsAttention, label: $0, symbol: "exclamationmark.triangle") }
    }

    var actions: [AppletAction] {
        var actions = [
            AppletAction(id: "add-files", title: "Add files", symbol: "plus", shortcut: AppletShortcut(key: "o")) { self.openPathEntry() },
            AppletAction(id: "refresh-shelf", title: "Refresh shelf", symbol: "arrow.clockwise", shortcut: AppletShortcut(key: "r")) { self.store.refresh() }
        ]
        if let file = store.selectedFile {
            if file.url != nil {
                actions.append(AppletAction(id: "preview", title: "Preview", symbol: "eye", shortcut: AppletShortcut(key: .space, modifiers: [])) { self.showPreview(file.url) })
                actions.append(AppletAction(id: "show-in-finder", title: "Show in Finder", symbol: "folder") { NSWorkspace.shared.activateFileViewerSelecting(self.store.selectedURLs) })
            }
            actions.append(AppletAction(id: "remove-from-shelf", title: "Remove from shelf", symbol: "minus.circle", shortcut: AppletShortcut(key: .delete)) { self.store.removeSelected() })
        }
        return actions
    }

    func add(urls: [URL]) { store.add(urls: urls) }

    func openPathEntry() {
        previewURL = nil
        showsPathEntry = true
    }

    func addPaths() {
        let paths = pathDraft.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !paths.isEmpty else {
            pathError = "Enter a file path, or drop files here."
            return
        }

        var urls: [URL] = []
        for line in paths {
            var path = line
            if path.count > 1, (path.first == "\"" && path.last == "\"") || (path.first == "'" && path.last == "'") {
                path = String(path.dropFirst().dropLast())
            }
            if path.hasPrefix("file://"), let url = URL(string: path), url.isFileURL {
                urls.append(url)
            } else {
                let expanded = (path as NSString).expandingTildeInPath
                guard expanded.hasPrefix("/") else {
                    pathError = "Use a full path or one beginning with ~, one file per line."
                    return
                }
                urls.append(URL(fileURLWithPath: expanded))
            }
        }

        pathError = nil
        add(urls: urls)
        showsPathEntry = false
    }

    func showPreview(_ url: URL?) {
        showsPathEntry = false
        previewURL = url
    }

    func makeView(context: AppletContext, artwork: NSImage?) -> AnyView {
        AnyView(FilesAppletView(applet: self))
    }

    func handleArrow(_ arrow: AppletArrow, command: Bool) -> Bool {
        guard arrow.isVertical, !command, !hasPresentedOverlay else { return false }
        store.moveSelection(arrow.offset)
        return true
    }

    func dismissOverlay() { showsPathEntry = false; previewURL = nil }
}
