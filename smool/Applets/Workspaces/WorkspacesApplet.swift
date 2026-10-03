import SwiftUI

@MainActor @Observable
final class WorkspacesApplet: Applet {
    let id = AppletID(rawValue: "workspaces")
    let title = "Workspaces"
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
        if store.isOpening { return AppletStatus(kind: .working, label: "Opening workspace") }
        if store.error != nil { return AppletStatus(kind: .needsAttention, label: "Check workspace") }
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
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                if let selected = applet.selected {
                    Picker("Workspace", selection: Binding(get: { selected.id }, set: { applet.selectedID = $0 })) {
                        ForEach(applet.store.workspaces) { Text($0.name).tag($0.id) }
                    }.labelsHidden()
                        .pickerStyle(.menu)
                        .font(.system(size: 13, weight: .semibold))
                        .tint(.primary)
                    Menu {
                        Button("Edit workspace") { applet.editor = selected }
                        Button("Delete workspace", role: .destructive) { _ = applet.store.delete(selected.id) }
                    } label: { Image(systemName: "ellipsis") }
                        .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Workspace actions")
                } else { Text("Your workspaces").font(.system(size: 13, weight: .semibold)) }
                Spacer()
                Button { applet.editor = SavedWorkspace(name: "") } label: {
                    Label("New", systemImage: "plus")
                }
                    .buttonStyle(NotchControlStyle()).disabled(!applet.store.canSave)
                    .keyboardShortcut("n", modifiers: .command)
            }
            if let selected = applet.selected {
                if selected.resources.isEmpty {
                    Text("Add apps, folders, links and Codex threads from Edit workspace.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .multilineTextAlignment(.center)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(selected.resources) { resource in
                                HStack {
                                    Toggle(isOn: Binding(get: { selected.selectedResourceIDs.contains(resource.id) }, set: { checked in
                                        var updated = selected
                                        if checked { updated.selectedResourceIDs.insert(resource.id) }
                                        else { updated.selectedResourceIDs.remove(resource.id) }
                                        applet.store.save(updated)
                                    })) {
                                        HStack(spacing: 10) {
                                            Image(systemName: resource.destination.kind.symbol)
                                                .foregroundStyle(.secondary)
                                                .frame(width: 20)
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text(resource.name)
                                                    .font(.system(size: 13, weight: .medium))
                                                    .lineLimit(1)
                                                Text(resource.destination.detail)
                                                    .font(.system(size: 11))
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(1)
                                                    .truncationMode(.middle)
                                            }
                                        }
                                    }.toggleStyle(.checkbox)
                                    Spacer()
                                    Button { Task { await applet.store.open([resource]) } } label: {
                                        Image(systemName: "arrow.up.right")
                                            .font(.system(size: 11, weight: .medium))
                                            .frame(width: 28, height: 28)
                                            .contentShape(Circle())
                                    }
                                        .buttonStyle(.plain)
                                        .foregroundStyle(.secondary)
                                        .disabled(applet.store.isOpening)
                                        .accessibilityLabel("Open \(resource.name)")
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(.white.opacity(selected.selectedResourceIDs.contains(resource.id) ? 0.055 : 0.02), in: .rect(cornerRadius: 14))
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
                        Text(applet.store.isOpening ? "Opening…" : "Open workspace")
                    }
                }
                .buttonStyle(NotchControlStyle(isSelected: true))
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(applet.store.isOpening || selected.resources.allSatisfy { !selected.selectedResourceIDs.contains($0.id) })
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                    Text("Everything for your next project")
                        .font(.system(size: 13, weight: .medium))
                    Text("Group apps, folders and links, then open them together.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            ActionFeedback(error: applet.store.error, result: applet.store.result)
            if !applet.store.canSave { Button("Reload") { applet.store.reload() } }
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 16)
        .sheet(item: $applet.editor) { workspace in
            WorkspaceEditor(workspace: workspace, store: applet.store) { applet.selectedID = $0 }
        }
    }
}
