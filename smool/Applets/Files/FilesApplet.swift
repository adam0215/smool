import SwiftUI

@MainActor @Observable
final class FilesApplet: Applet {
    let id = AppletID(rawValue: "files")
    let title = "Filhylla"
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
            AppletAction(id: "Lägg till filer", symbol: "plus", shortcut: "⌘O") { self.showsImporter = true },
            AppletAction(id: "Uppdatera filhyllan", symbol: "arrow.clockwise", shortcut: "⌘R") { self.store.refresh() }
        ]
        if let file = store.selectedFile {
            if let url = file.url {
                actions.append(AppletAction(id: "Förhandsvisa", symbol: "eye", shortcut: "mellanslag") { self.previewURL = url })
                actions.append(AppletAction(id: "Visa i Finder", symbol: "folder") { NSWorkspace.shared.activateFileViewerSelecting([url]) })
            }
            actions.append(AppletAction(id: "Ta bort från hyllan", symbol: "minus.circle", shortcut: "⌘⌫") { self.store.remove(id: file.id) })
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
