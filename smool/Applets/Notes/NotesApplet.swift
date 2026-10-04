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
    var commandContext = AppletCommandContext()

    init(store: NotesStore? = nil, onSendToCodex: ((String) -> Void)? = nil) {
        self.store = store ?? NotesStore()
        commandContext.composeInCodex = { onSendToCodex }
        isEditing = self.store.selectedNote != nil
    }

    var contentHeight: CGFloat { 218 }
    var hasPresentedOverlay: Bool { isEditing || pendingDeletion != nil }
    var status: AppletStatus? {
        store.errorMessage.map { _ in AppletStatus(kind: .needsAttention, label: "Notes need attention", symbol: "exclamationmark.triangle") }
    }

    var actions: [AppletAction] {
        var actions: [AppletAction] = []
        if !store.isReadOnly {
            actions.append(AppletAction(id: "new-note", title: "New note", symbol: "square.and.pencil", shortcut: AppletShortcut(key: "n")) { self.createNote() })
        }
        if let note = store.selectedNote {
            if let composeInCodex = commandContext.composeInCodex(), !note.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                actions.append(AppletAction(id: "open-in-codex", title: "Open in Codex", symbol: "arrow.up.right") {
                    self.store.requestSave()
                    composeInCodex(note.text)
                })
            }
            if !store.isReadOnly {
                actions.append(AppletAction(id: "delete-note", title: "Delete note", symbol: "trash", shortcut: AppletShortcut(key: .delete)) { self.requestDeletion() })
            }
        }
        return actions
    }

    @discardableResult
    func createNote(text: String = "") -> UUID? {
        let id = store.createNote(text: text)
        if id != nil { isEditing = true }
        return id
    }

    func makeView(context: AppletContext, artwork: NSImage?) -> AnyView {
        AnyView(NotesAppletView(applet: self, restoreFocus: context.restoreFocus))
    }

    func finishEditing() {
        store.requestSave()
        isEditing = false
    }

    func requestDeletion() {
        guard !store.isReadOnly else { return }
        store.requestSave()
        pendingDeletion = store.selectedNote
    }

    func confirmDeletion() {
        guard let note = pendingDeletion else { return }
        store.delete(note.id)
        pendingDeletion = nil
        isEditing = false
    }

    func handleArrow(_ arrow: AppletArrow, command: Bool) -> Bool {
        guard !isEditing, !hasPresentedOverlay, !command, arrow.isVertical, !store.notes.isEmpty else { return false }
        let index = store.notes.firstIndex { $0.id == store.selectedID } ?? 0
        store.select(store.notes[min(max(index + arrow.offset, 0), store.notes.count - 1)].id)
        return true
    }

    func deactivate() {
        store.requestSave()
        pendingDeletion = nil
    }

    func dismissOverlay() {
        if pendingDeletion != nil {
            pendingDeletion = nil
        } else {
            finishEditing()
        }
    }
}
