import SwiftUI

@MainActor @Observable
final class FilesApplet: Applet {
    let id = AppletID(rawValue: "files")
    let title = "Files"
    let icon = AppletIcon.symbol("tray.full")
    let tint = Color.cyan
    let store: FileShelfStore
    var showsImporter = false
    var previewURL: URL?

    init(store: FileShelfStore? = nil) { self.store = store ?? FileShelfStore() }

    var contentHeight: CGFloat { 212 }
    var hasPresentedOverlay: Bool { showsImporter || previewURL != nil }
    var status: AppletStatus? {
        store.error.map { AppletStatus(kind: .needsAttention, label: $0, symbol: "exclamationmark.triangle") }
    }

    var actions: [AppletAction] {
        var actions = [
            AppletAction(id: "Add files", symbol: "plus", shortcut: "⌘O") { self.showsImporter = true },
            AppletAction(id: "Refresh shelf", symbol: "arrow.clockwise", shortcut: "⌘R") { self.store.refresh() }
        ]
        if let file = store.selectedFile {
            if file.url != nil {
                actions.append(AppletAction(id: "Preview", symbol: "eye", shortcut: "Space") { self.previewURL = file.url })
                actions.append(AppletAction(id: "Show in Finder", symbol: "folder") { NSWorkspace.shared.activateFileViewerSelecting(self.store.selectedURLs) })
            }
            actions.append(AppletAction(id: "Remove from shelf", symbol: "minus.circle", shortcut: "⌘⌫") { self.store.removeSelected() })
        }
        return actions
    }

    func add(urls: [URL]) { store.add(urls: urls) }

    func makeView(context: AppletContext, artwork: NSImage?) -> AnyView {
        AnyView(FilesAppletView(applet: self))
    }

    func handleArrow(_ arrow: AppletArrow, command: Bool) -> Bool {
        guard arrow.isVertical, !command, !hasPresentedOverlay else { return false }
        store.moveSelection(arrow.offset)
        return true
    }

    func dismissOverlay() { showsImporter = false; previewURL = nil }
}
