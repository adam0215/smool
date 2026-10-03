import SwiftUI

@MainActor @Observable
final class NotesApplet: Applet {
    let id = AppletID(rawValue: "notes")
    let title = "Notes"
    let icon = AppletIcon.symbol("note.text")
    let tint = Color.yellow
    let store: NotesStore
    var isEditing = false
    var pendingDeletion: QuickNote?
    private let onSendToCodex: ((String) -> Void)?

    init(store: NotesStore? = nil, onSendToCodex: ((String) -> Void)? = nil) {
        self.store = store ?? NotesStore()
        self.onSendToCodex = onSendToCodex
        isEditing = self.store.selectedNote != nil
    }

    var contentHeight: CGFloat { 218 }
    var hasPresentedOverlay: Bool { pendingDeletion != nil }
    var status: AppletStatus? {
        store.errorMessage.map { _ in AppletStatus(kind: .needsAttention, label: "Notes need attention", symbol: "exclamationmark.triangle") }
    }

    var actions: [AppletAction] {
        [AppletAction(id: "New note", symbol: "square.and.pencil", shortcut: "⌘N") { self.createNote() }]
    }

    @discardableResult
    func createNote(text: String = "") -> UUID? {
        let id = store.createNote(text: text)
        if id != nil { isEditing = true }
        return id
    }

    func makeView(context: AppletContext, artwork: NSImage?) -> AnyView {
        AnyView(NotesAppletView(applet: self, onSendToCodex: onSendToCodex ?? context.composeInCodex, restoreFocus: context.restoreFocus))
    }

    func handleArrow(_ arrow: AppletArrow, command: Bool) -> Bool {
        guard !isEditing, !hasPresentedOverlay, !command, arrow.isVertical, !store.notes.isEmpty else { return false }
        let index = store.notes.firstIndex { $0.id == store.selectedID } ?? 0
        store.select(store.notes[min(max(index + arrow.offset, 0), store.notes.count - 1)].id)
        return true
    }

    func deactivate() {
        store.flush()
        pendingDeletion = nil
    }

    func dismissOverlay() { pendingDeletion = nil }
}
