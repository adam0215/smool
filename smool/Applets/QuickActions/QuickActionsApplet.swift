import SwiftUI

@MainActor @Observable
final class QuickActionsApplet: Applet {
    let id = AppletID(rawValue: "quick-actions")
    let title = "Actions"
    let icon = AppletIcon.symbol("bolt")
    let tint = Color.orange
    let store: QuickActionStore
    var selectedID: UUID?
    var highlightedID: String?
    var editor: ActionEditorRequest? {
        didSet { editorGeneration += 1 }
    }
    private var editorGeneration = 0
    private(set) var isPersisting = false
    var deletingAction: SavedAction?
    private var drafts: [UUID: ActionEditorRequest] = [:]
    private var newDraft: ActionEditorRequest?
    var commandContext = AppletCommandContext()

    init(store: QuickActionStore = QuickActionStore()) { self.store = store }

    var contentHeight: CGFloat {
        if editor != nil { return 250 }
        if deletingAction != nil { return 180 }
        return 280
    }

    var hasPresentedOverlay: Bool { editor != nil || deletingAction != nil }
    var status: AppletStatus? {
        if store.runningID != nil { return AppletStatus(kind: .working, label: "Running action") }
        if store.error != nil { return AppletStatus(kind: .needsAttention, label: "Check action") }
        return nil
    }

    var entries: [AppletAction] {
        var result = commandContext.hostActions().map { action in
            AppletAction(id: "context:\(action.id)", title: action.title, symbol: action.symbol,
                         shortcut: action.shortcut, selected: action.selected, detail: action.detail, perform: action.perform)
        }
        result += store.actions.map { action in
            AppletAction(id: action.id.uuidString, title: action.name, symbol: action.destination.kind.symbol,
                  detail: action.destination.detail) { [weak self] in
                guard let self else { return }
                selectedID = action.id
                Task { await store.run(action) }
            }
        }
        if store.canSave {
            result.append(AppletAction(id: "new", title: newDraft == nil ? "Save an action" : "Resume new action", symbol: "plus", shortcut: AppletShortcut(key: "n", modifiers: [.command, .shift])) { [weak self] in self?.edit() })
            if let selected = store.actions.first(where: { $0.id == selectedID }) {
                result.append(AppletAction(id: "edit", title: "Edit \(selected.name)", symbol: "pencil", shortcut: AppletShortcut(key: "e", modifiers: [.command, .shift])) { [weak self] in self?.edit(selected) })
                result.append(AppletAction(id: "delete", title: "Delete \(selected.name)", symbol: "trash", shortcut: AppletShortcut(key: .delete, modifiers: [.command, .shift])) { [weak self] in self?.deletingAction = selected })
                if store.actions.first?.id != selected.id {
                    result.append(AppletAction(id: "move-up", title: "Move \(selected.name) up", symbol: "arrow.up") { [weak self] in Task { await self?.move(selected.id, offset: -1) } })
                }
                if store.actions.last?.id != selected.id {
                    result.append(AppletAction(id: "move-down", title: "Move \(selected.name) down", symbol: "arrow.down") { [weak self] in Task { await self?.move(selected.id, offset: 1) } })
                }
            }
        }
        return result
    }

    func makeView(context: AppletContext, artwork: NSImage?) -> AnyView {
        AnyView(QuickActionsAppletView(applet: self, restoreFocus: context.restoreFocus))
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

    func save(_ action: SavedAction) async -> Bool {
        guard !isPersisting, let draft = editor else { return false }
        let generation = editorGeneration
        let fields = (draft.name, draft.input, draft.destination, draft.usesShortcut)
        isPersisting = true
        draft.isSaving = true
        defer { isPersisting = false; draft.isSaving = false }
        guard await store.save(action) else { return false }
        guard editorGeneration == generation, editor === draft,
              fields == (draft.name, draft.input, draft.destination, draft.usesShortcut) else { return false }
        if draft.action == nil { newDraft = nil }
        drafts[action.id] = nil
        selectedID = action.id
        highlightedID = action.id.uuidString
        return true
    }

    func confirmDeletion() async -> Bool {
        guard !isPersisting, let action = deletingAction else { return false }
        isPersisting = true
        defer { isPersisting = false }
        guard await store.delete(action.id) else { return false }
        guard deletingAction?.id == action.id, editor == nil else { return false }
        if selectedID == action.id { selectedID = store.actions.first?.id }
        highlightedID = nil
        deletingAction = nil
        return true
    }

    private func move(_ id: UUID, offset: Int) async {
        guard !isPersisting else { return }
        isPersisting = true
        defer { isPersisting = false }
        _ = await store.move(id, offset: offset)
    }

    func dismissOverlay() {
        editor = nil
        deletingAction = nil
    }

    func highlight(_ entry: AppletAction) {
        highlightedID = entry.id
        if let id = UUID(uuidString: entry.id) { selectedID = id }
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
                    ActionFeedback(error: applet.store.error, result: nil)
                    HStack {
                        Button("Keep action", action: closeEditor).keyboardShortcut(.cancelAction)
                        Spacer()
                        Button("Delete", role: .destructive) {
                            Task {
                                if await applet.confirmDeletion() { restoreFocus(); listFocused = true }
                            }
                        }
                        .keyboardShortcut(.defaultAction)
                        .disabled(applet.isPersisting)
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
        .padding(.bottom, applet.hasPresentedOverlay ? NotchLayout.contentInset : 24)
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
                                    if entry.selected { Image(systemName: "checkmark").foregroundStyle(.secondary) }
                                    if let shortcut = entry.shortcut, shortcut.paletteShortcut != nil {
                                        Text(shortcut.label).font(.system(size: 10)).foregroundStyle(.secondary)
                                    }
                                    if UUID(uuidString: entry.id) == applet.store.runningID, applet.store.runningID != nil { ProgressView().controlSize(.mini) }
                                }
                                .padding(.horizontal, 12).padding(.vertical, 9)
                                .contentShape(Rectangle())
                                .background(.white.opacity(applet.highlightedID == entry.id ? 0.09 : 0), in: .rect(cornerRadius: 12))
                            }
                            .buttonStyle(.plain).focusable(false)
                            .id(entry.id)
                            .onHover { if $0 { applet.highlight(entry) } }
                        }
                    }
                }
                .onChange(of: applet.highlightedID) { _, id in if let id { proxy.scrollTo(id) } }
            }
            ActionFeedback(error: applet.store.error, result: applet.store.result)
            if !applet.store.canSave { Button("Reload saved actions") { applet.store.reload() } }
        }
        .background {
            // Register commands even when their rows are outside the lazy list's viewport.
            ForEach(applet.entries.filter { $0.shortcut?.paletteShortcut != nil }) { action in
                Button(action.title, action: action.perform)
                    .keyboardShortcut(action.shortcut?.paletteShortcut)
                    .hidden()
            }
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
