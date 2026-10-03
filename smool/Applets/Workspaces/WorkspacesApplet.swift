import SwiftUI

@MainActor @Observable
final class WorkspacesApplet: Applet {
    let id = AppletID(rawValue: "workspaces")
    let title = "Arbetsytor"
    let icon = AppletIcon.symbol("square.grid.2x2")
    let tint = Color.teal
    let contentHeight: CGFloat = 300
    let store: WorkspaceStore
    var selectedID: UUID?
    var editor: SavedWorkspace?

    init(store: WorkspaceStore = WorkspaceStore()) { self.store = store }

    var selected: SavedWorkspace? { store.workspaces.first(where: { $0.id == selectedID }) ?? store.workspaces.first }
    var hasPresentedOverlay: Bool { editor != nil }
    var status: AppletStatus? {
        if store.isOpening { return AppletStatus(kind: .working, label: "Öppnar arbetsyta") }
        if store.error != nil { return AppletStatus(kind: .needsAttention, label: "Kontrollera arbetsyta") }
        return nil
    }

    func makeView(context: AppletContext, artwork: NSImage?) -> AnyView {
        AnyView(WorkspacesAppletView(applet: self))
    }

    func dismissOverlay() { editor = nil }

    func handleArrow(_ arrow: AppletArrow, command: Bool) -> Bool {
        guard !command, !arrow.isVertical, editor == nil, !store.workspaces.isEmpty else { return false }
        let index = store.workspaces.firstIndex(where: { $0.id == selected?.id }) ?? 0
        selectedID = store.workspaces[(index + arrow.offset + store.workspaces.count) % store.workspaces.count].id
        return true
    }
}

private struct WorkspacesAppletView: View {
    @Bindable var applet: WorkspacesApplet

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                if let selected = applet.selected {
                    Picker("Arbetsyta", selection: Binding(get: { selected.id }, set: { applet.selectedID = $0 })) {
                        ForEach(applet.store.workspaces) { Text($0.name).tag($0.id) }
                    }.labelsHidden()
                    Menu {
                        Button("Redigera arbetsyta") { applet.editor = selected }
                        Button("Ta bort arbetsyta", role: .destructive) { _ = applet.store.delete(selected.id) }
                    } label: { Image(systemName: "ellipsis") }
                        .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Arbetsytans åtgärder")
                } else { Text("Dina arbetsytor").font(.headline) }
                Spacer()
                Button { applet.editor = SavedWorkspace(name: "") } label: {
                    HStack(spacing: 5) { Image(systemName: "plus"); Text("Ny") }
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .modifier(FloatingGlass(cornerRadius: 20))
                }
                    .buttonStyle(.plain).disabled(!applet.store.canSave)
                    .keyboardShortcut("n", modifiers: .command)
            }
            if let selected = applet.selected {
                if selected.resources.isEmpty {
                    Text("Lägg till appar, mappar, webblänkar och Codex-trådar via Redigera arbetsyta.")
                        .font(.callout).foregroundStyle(.secondary).frame(maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(selected.resources) { resource in
                                HStack {
                                    Toggle(isOn: Binding(get: { selected.selectedResourceIDs.contains(resource.id) }, set: { checked in
                                        var updated = selected
                                        if checked { updated.selectedResourceIDs.insert(resource.id) }
                                        else { updated.selectedResourceIDs.remove(resource.id) }
                                        applet.store.save(updated)
                                    })) {
                                        Label(resource.name, systemImage: resource.destination.kind.symbol).lineLimit(1)
                                    }.toggleStyle(.checkbox)
                                    Spacer()
                                    Button("Öppna") { Task { await applet.store.open([resource]) } }
                                        .disabled(applet.store.isOpening)
                                        .accessibilityLabel("Öppna \(resource.name)")
                                }.padding(.vertical, 4)
                            }
                        }
                    }
                }
                Button {
                    let resources = selected.resources.filter { selected.selectedResourceIDs.contains($0.id) }
                    Task { await applet.store.open(resources) }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.right")
                        Text(applet.store.isOpening ? "Öppnar…" : "Öppna arbetsyta")
                    }
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .modifier(FloatingGlass(cornerRadius: 20))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(applet.store.isOpening || selected.resources.allSatisfy { !selected.selectedResourceIDs.contains($0.id) })
            } else {
                Text("Samla det du behöver för ett projekt. Välj sedan vilka resurser som ska öppnas tillsammans.")
                    .font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            ActionFeedback(error: applet.store.error, result: applet.store.result)
            if !applet.store.canSave { Button("Läs in igen") { applet.store.reload() } }
        }
        .padding(16)
        .sheet(item: $applet.editor) { workspace in
            WorkspaceEditor(workspace: workspace, store: applet.store) { applet.selectedID = $0 }
        }
    }
}
