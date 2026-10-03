import SwiftUI

struct NotesAppletView: View {
    @Bindable var applet: NotesApplet
    let onSendToCodex: ((String) -> Void)?
    let restoreFocus: () -> Void
    @FocusState private var listIsFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                if applet.isEditing {
                    Button {
                        applet.store.flush()
                        applet.isEditing = false
                        restoreFocus()
                    } label: { Label("All notes", systemImage: "chevron.left") }
                    .keyboardShortcut(.escape, modifiers: [])
                } else {
                    Text("Notes")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                }

                Spacer()

                Button { applet.createNote() } label: {
                    Image(systemName: "square.and.pencil")
                        .frame(width: 28, height: 28)
                        .contentShape(Circle())
                }
                    .keyboardShortcut("n", modifiers: .command)
                    .accessibilityLabel("New note")
                    .help("New note · ⌘N")
                    .disabled(applet.store.isReadOnly)

                if let note = applet.store.selectedNote {
                    Button { applet.pendingDeletion = note } label: {
                        Image(systemName: "trash")
                            .frame(width: 28, height: 28)
                            .contentShape(Circle())
                    }
                        .accessibilityLabel("Delete note")
                        .disabled(applet.store.isReadOnly)
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(.horizontal, applet.isEditing ? 16 : 0)

            if let error = applet.store.errorMessage {
                HStack(alignment: .top) {
                    Text(error).lineLimit(3).font(.system(size: 11))
                    Spacer(minLength: 2)
                    Button("Try again") { applet.store.reload() }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(.orange)
                .padding(.horizontal, applet.isEditing ? 16 : 0)
            }

            if applet.isEditing, let note = applet.store.selectedNote {
                NotesEditor(
                    text: Binding(get: { applet.store.selectedNote?.text ?? "" }, set: { applet.store.update(note.id, text: $0) }),
                    isReadOnly: applet.store.isReadOnly,
                    saveStatus: applet.store.errorMessage != nil ? "Could not save" : (applet.store.hasUnsavedChanges ? "Saving…" : "Saved"),
                    onSendToCodex: onSendToCodex.map { callback in { applet.store.flush(); callback(applet.store.selectedNote?.text ?? "") } },
                    onClose: { applet.store.flush(); applet.isEditing = false; restoreFocus() }
                )
                .id(note.id)
            } else if applet.store.notes.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "note.text")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                    Text(applet.store.isReadOnly ? "Notes are unavailable" : "A thought to keep?")
                        .font(.system(size: 13, weight: .medium))
                    Button("New note") { applet.createNote() }
                        .buttonStyle(NotchControlStyle(isSelected: true))
                        .disabled(applet.store.isReadOnly)
                    Text("Saved automatically on this Mac")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                noteList
            }
        }
        .padding(.horizontal, applet.isEditing ? NotchLayout.contentInset : 24)
        .padding(.top, 8)
        .padding(.bottom, applet.isEditing ? NotchLayout.contentInset : 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .alert("Delete this note?", isPresented: Binding(get: { applet.pendingDeletion != nil }, set: { if !$0 { applet.pendingDeletion = nil } })) {
            Button("Cancel", role: .cancel) { applet.pendingDeletion = nil }
            Button("Delete", role: .destructive) {
                if let note = applet.pendingDeletion { applet.store.delete(note.id) }
                applet.pendingDeletion = nil
                if applet.store.notes.isEmpty { applet.isEditing = false }
            }
        } message: {
            Text("\(applet.pendingDeletion?.title ?? "This note") will be permanently deleted.")
        }
        .onKeyPress(.return) {
            guard !applet.isEditing, applet.store.selectedNote != nil else { return .ignored }
            applet.isEditing = true
            return .handled
        }
        .onDisappear { applet.store.flush() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in applet.store.flush() }
    }

    private var noteList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(applet.store.notes) { note in
                        Button {
                            applet.store.select(note.id)
                            applet.isEditing = true
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "note.text")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 20)
                                Text(note.title).lineLimit(1)
                                Spacer(minLength: 4)
                                Text(note.updatedAt, style: .date).font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                            .font(.system(size: 13))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 11)
                            .background(.white.opacity(note.id == applet.store.selectedID ? 0.09 : 0), in: RoundedRectangle(cornerRadius: 14))
                            .contentShape(.rect(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                        .id(note.id)
                        .accessibilityAddTraits(note.id == applet.store.selectedID ? .isSelected : [])
                    }
                }
            }
            .onChange(of: applet.store.selectedID) { _, id in
                if let id { proxy.scrollTo(id) }
            }
        }
        .focusable()
        .focusEffectDisabled()
        .focused($listIsFocused)
        .task { listIsFocused = true }
        .onDisappear { listIsFocused = false }
    }
}
