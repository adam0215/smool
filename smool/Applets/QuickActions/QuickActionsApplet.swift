import SwiftUI

@MainActor @Observable
final class QuickActionsApplet: Applet {
    let id = AppletID(rawValue: "quick-actions")
    let title = "Snabbåtgärder"
    let icon = AppletIcon.symbol("bolt")
    let tint = Color.orange
    let contentHeight: CGFloat = 300
    let store: QuickActionStore
    var selectedID: UUID?
    var editor: ActionEditorRequest?

    init(store: QuickActionStore = QuickActionStore()) { self.store = store }

    var hasPresentedOverlay: Bool { editor != nil }
    var status: AppletStatus? {
        if store.runningID != nil { return AppletStatus(kind: .working, label: "Kör snabbåtgärd") }
        if store.error != nil { return AppletStatus(kind: .needsAttention, label: "Kontrollera snabbåtgärd") }
        return nil
    }

    func makeView(context: AppletContext, artwork: NSImage?) -> AnyView {
        AnyView(QuickActionsAppletView(applet: self))
    }

    func dismissOverlay() { editor = nil }

    func handleArrow(_ arrow: AppletArrow, command: Bool) -> Bool {
        guard !command, arrow.isVertical, editor == nil, !store.actions.isEmpty else { return false }
        let index = store.actions.firstIndex(where: { $0.id == selectedID }) ?? (arrow.offset > 0 ? -1 : 0)
        selectedID = store.actions[(index + arrow.offset + store.actions.count) % store.actions.count].id
        return true
    }
}

private struct QuickActionsAppletView: View {
    @Bindable var applet: QuickActionsApplet
    @FocusState private var listFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Dina snabbåtgärder").font(.headline)
                Spacer()
                Button { applet.editor = ActionEditorRequest() } label: {
                    HStack(spacing: 5) { Image(systemName: "plus"); Text("Lägg till") }
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .modifier(FloatingGlass(cornerRadius: 20))
                }
                    .buttonStyle(.plain).disabled(!applet.store.canSave)
                    .keyboardShortcut("n", modifiers: .command)
            }
            if applet.store.actions.isEmpty {
                Text("Samla appar, mappar, webblänkar och Apple Genvägar här.")
                    .font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(Array(applet.store.actions.enumerated()), id: \.element.id) { index, action in
                                row(action, index: index).id(action.id)
                            }
                        }
                    }
                    .onChange(of: applet.selectedID) { _, id in if let id { proxy.scrollTo(id) } }
                }
            }
            ActionFeedback(error: applet.store.error, result: applet.store.result)
            if !applet.store.canSave { Button("Läs in igen") { applet.store.reload() } }
        }
        .padding(16)
        .focusable(interactions: .edit).focused($listFocused).focusEffectDisabled()
        .task {
            if applet.selectedID == nil { applet.selectedID = applet.store.actions.first?.id }
            await Task.yield()
            listFocused = true
        }
        .onChange(of: applet.editor?.id) { _, id in
            if id == nil { listFocused = true }
        }
        .sheet(item: $applet.editor) { request in
            SavedActionEditor(original: request.action, allowsShortcuts: true) { action in
                guard applet.store.save(action) else { return false }
                applet.selectedID = action.id
                return true
            }
        }
        .onKeyPress(.return) {
            guard applet.editor == nil, let action = applet.store.actions.first(where: { $0.id == applet.selectedID }) else { return .ignored }
            Task { await applet.store.run(action) }
            return .handled
        }
    }

    private func row(_ action: SavedAction, index: Int) -> some View {
        HStack(spacing: 10) {
            Button {
                applet.selectedID = action.id
                Task { await applet.store.run(action) }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: action.destination.kind.symbol).frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(action.name).lineLimit(1)
                        Text(action.destination.detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                    Spacer()
                    if applet.store.runningID == action.id { ProgressView().controlSize(.mini) }
                    else { Image(systemName: "play.fill").font(.caption) }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain).disabled(applet.store.runningID != nil)
            .accessibilityLabel("Kör \(action.name)")
            Menu {
                Button("Redigera") { applet.editor = ActionEditorRequest(action: action) }
                Button("Flytta upp") { applet.store.move(action.id, offset: -1) }.disabled(index == 0)
                Button("Flytta ned") { applet.store.move(action.id, offset: 1) }.disabled(index == applet.store.actions.count - 1)
                Button("Ta bort", role: .destructive) {
                    applet.store.delete(action.id)
                    if applet.selectedID == action.id { applet.selectedID = applet.store.actions.first?.id }
                }
            } label: { Image(systemName: "ellipsis") }
                .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Åtgärder för \(action.name)")
        }
        .padding(9)
        .background(.white.opacity(applet.selectedID == action.id ? 0.1 : 0.03), in: .rect(cornerRadius: 9))
    }
}
