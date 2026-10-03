import SwiftUI

@MainActor @Observable
final class QuickActionsApplet: Applet {
    let id = AppletID(rawValue: "quick-actions")
    let title = "Actions"
    let icon = AppletIcon.symbol("bolt")
    let tint = Color.orange
    let contentHeight: CGFloat = 320
    let store: QuickActionStore
    var selectedID: UUID?
    var highlightedID: String?
    var editor: ActionEditorRequest?
    var deletingAction: SavedAction?
    private var drafts: [UUID: ActionEditorRequest] = [:]
    private var newDraft: ActionEditorRequest?
    @ObservationIgnored private var hostActions: [AppletAction] = []

    init(store: QuickActionStore = QuickActionStore()) { self.store = store }

    var hasPresentedOverlay: Bool { editor != nil || deletingAction != nil }
    var status: AppletStatus? {
        if store.runningID != nil { return AppletStatus(kind: .working, label: "Running action") }
        if store.error != nil { return AppletStatus(kind: .needsAttention, label: "Check action") }
        return nil
    }

    struct Entry: Identifiable {
        let id: String
        let title: String
        let symbol: String
        var detail = ""
        var shortcut = ""
        var savedID: UUID?
        let perform: () -> Void

        var keyboardShortcut: KeyboardShortcut? {
            // Return runs the highlighted row. Command-arrows belong to host navigation.
            guard !shortcut.isEmpty, !["↵", "⌘←", "⌘→"].contains(shortcut) else { return nil }
            var modifiers: EventModifiers = []
            if shortcut.contains("⌘") { modifiers.insert(.command) }
            if shortcut.contains("⇧") { modifiers.insert(.shift) }
            if shortcut.contains("⌥") { modifiers.insert(.option) }
            if shortcut.contains("⌃") { modifiers.insert(.control) }
            let character = shortcut.filter { !"⌘⇧⌥⌃".contains($0) }
            let key: KeyEquivalent
            switch character {
            case "Space", "␣": key = .space
            case "↵": key = .return
            case "⌫": key = .delete
            default:
                guard character.count == 1, let value = character.lowercased().first else { return nil }
                key = KeyEquivalent(value)
            }
            return KeyboardShortcut(key, modifiers: modifiers)
        }
    }

    var entries: [Entry] {
        var result = hostActions.map { action in
            Entry(id: "context:\(action.id)", title: action.id, symbol: action.symbol, shortcut: action.shortcut, perform: action.perform)
        }
        result += store.actions.map { action in
            Entry(id: action.id.uuidString, title: action.name, symbol: action.destination.kind.symbol,
                  detail: action.destination.detail, savedID: action.id) { [weak self] in
                guard let self else { return }
                selectedID = action.id
                Task { await store.run(action) }
            }
        }
        if store.canSave {
            result.append(Entry(id: "new", title: newDraft == nil ? "Save an action" : "Resume new action", symbol: "plus", shortcut: "⇧⌘N") { [weak self] in self?.edit() })
            if let selected = store.actions.first(where: { $0.id == selectedID }) {
                result.append(Entry(id: "edit", title: "Edit \(selected.name)", symbol: "pencil", shortcut: "⇧⌘E") { [weak self] in self?.edit(selected) })
                result.append(Entry(id: "delete", title: "Delete \(selected.name)", symbol: "trash", shortcut: "⇧⌘⌫") { [weak self] in self?.deletingAction = selected })
                if store.actions.first?.id != selected.id {
                    result.append(Entry(id: "move-up", title: "Move \(selected.name) up", symbol: "arrow.up") { [weak self] in self?.store.move(selected.id, offset: -1) })
                }
                if store.actions.last?.id != selected.id {
                    result.append(Entry(id: "move-down", title: "Move \(selected.name) down", symbol: "arrow.down") { [weak self] in self?.store.move(selected.id, offset: 1) })
                }
            }
        }
        return result
    }

    func makeView(context: AppletContext, artwork: NSImage?) -> AnyView {
        hostActions = context.hostActions
        return AnyView(QuickActionsAppletView(applet: self, restoreFocus: context.restoreFocus))
    }

    func edit(_ action: SavedAction? = nil) {
        guard store.canSave else { return }
        if let action {
            let draft = drafts[action.id] ?? ActionEditorRequest(action: action)
            drafts[action.id] = draft
            editor = draft
        } else {
            let draft = newDraft ?? ActionEditorRequest()
            newDraft = draft
            editor = draft
        }
    }

    func save(_ action: SavedAction) -> Bool {
        guard store.save(action) else { return false }
        if editor?.action == nil { newDraft = nil }
        drafts[action.id] = nil
        selectedID = action.id
        highlightedID = action.id.uuidString
        return true
    }

    func dismissOverlay() {
        editor = nil
        deletingAction = nil
    }

    func highlight(_ entry: Entry) {
        highlightedID = entry.id
        if let id = entry.savedID { selectedID = id }
    }

    func handleArrow(_ arrow: AppletArrow, command: Bool) -> Bool {
        guard !command, arrow.isVertical, !hasPresentedOverlay else { return false }
        let items = entries
        guard !items.isEmpty else { return false }
        let index = items.firstIndex(where: { $0.id == highlightedID }) ?? (arrow.offset > 0 ? -1 : 0)
        highlight(items[(index + arrow.offset + items.count) % items.count])
        return true
    }

    func activateSelected() {
        let items = entries
        (items.first(where: { $0.id == highlightedID }) ?? items.first)?.perform()
    }
}

private struct QuickActionsAppletView: View {
    @Bindable var applet: QuickActionsApplet
    var restoreFocus: () -> Void
    @FocusState private var listFocused: Bool

    var body: some View {
        Group {
            if let draft = applet.editor {
                SavedActionEditor(draft: draft, allowsShortcuts: true, onSave: applet.save, onClose: closeEditor)
            } else if let action = applet.deletingAction {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Delete \(action.name)?").font(.system(size: 14, weight: .semibold))
                    Text("This removes the saved action from smool.").font(.system(size: 12)).foregroundStyle(.secondary)
                    HStack {
                        Button("Keep action", action: closeEditor).keyboardShortcut(.cancelAction)
                        Spacer()
                        Button("Delete", role: .destructive) {
                            applet.store.delete(action.id)
                            applet.selectedID = applet.store.actions.first?.id
                            applet.highlightedID = nil
                            closeEditor()
                        }.keyboardShortcut(.defaultAction)
                    }
                }
                .padding(24).modifier(FloatingGlass(cornerRadius: NotchLayout.bottomRadius - NotchLayout.contentInset, cornerStyle: .circular))
            } else {
                actionList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.horizontal, applet.hasPresentedOverlay ? NotchLayout.contentInset : 24)
        .padding(.top, 8)
        .padding(.bottom, applet.hasPresentedOverlay ? NotchLayout.contentInset : 16)
    }

    private var actionList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Commands for this view and your saved actions")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(applet.entries) { entry in
                            Button { applet.highlight(entry); entry.perform() } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: entry.symbol).frame(width: 20).foregroundStyle(.secondary)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(entry.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                                        if !entry.detail.isEmpty {
                                            Text(entry.detail).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                                        }
                                    }
                                    Spacer(minLength: 8)
                                    Text(entry.keyboardShortcut == nil ? "" : entry.shortcut).font(.system(size: 10)).foregroundStyle(.secondary)
                                    if entry.savedID != nil, entry.savedID == applet.store.runningID { ProgressView().controlSize(.mini) }
                                }
                                .padding(.horizontal, 12).padding(.vertical, 9)
                                .contentShape(Rectangle())
                                .background(.white.opacity(applet.highlightedID == entry.id ? 0.09 : 0), in: .rect(cornerRadius: 12))
                            }
                            .buttonStyle(.plain).focusable(false)
                            .keyboardShortcut(entry.keyboardShortcut)
                            .id(entry.id)
                            .onHover { if $0 { applet.highlight(entry) } }
                        }
                    }
                }
                .onChange(of: applet.highlightedID) { _, id in if let id { proxy.scrollTo(id) } }
            }
            ActionFeedback(error: applet.store.error, result: applet.store.result)
            if !applet.store.canSave { Button("Reload saved actions") { applet.store.reload() } }
            HStack {
                Text("↑↓ choose · ↵ run · ⇧⌘N new action · ⇧⌘E edit · Esc back")
                Spacer(minLength: 0)
            }.font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .focusable(interactions: .edit).focused($listFocused).focusEffectDisabled()
        .onAppletFocusRestore { listFocused = true }
        .task {
            if applet.highlightedID == nil, let first = applet.entries.first { applet.highlight(first) }
            await Task.yield()
            listFocused = true
        }
        .onKeyPress(keys: [.return], phases: .down) { key in
            guard key.modifiers.intersection([.command, .control, .option, .shift]).isEmpty else { return .ignored }
            applet.activateSelected()
            return .handled
        }
    }

    private func closeEditor() {
        applet.dismissOverlay()
        restoreFocus()
        listFocused = true
    }
}
