import SwiftUI

struct NotesAppletView: View {
    @Bindable var applet: NotesApplet
    let restoreFocus: () -> Void
    @FocusState private var listIsFocused: Bool
    @FocusState private var deletionIsFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let note = applet.pendingDeletion {
                deletionConfirmation(note)
            } else {
                header

                if let error = applet.store.errorMessage {
                    HStack(alignment: .top) {
                        Text(error).lineLimit(3).font(.system(size: 11))
                        Spacer(minLength: 2)
                        Button("Try again") { applet.store.reload() }
                            .buttonStyle(.plain)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(.orange)
                    .padding(.horizontal, applet.isEditing ? 24 : 0)
                }

                if applet.isEditing, let note = applet.store.selectedNote {
                    NotesEditor(
                        text: Binding(get: { applet.store.selectedNote?.text ?? "" }, set: { applet.store.update(note.id, text: $0) }),
                        isReadOnly: applet.store.isReadOnly,
                        saveStatus: applet.store.errorMessage != nil ? "Could not save" : (applet.store.hasUnsavedChanges ? "Saving…" : "Saved"),
                        onClose: closeEditor
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
                        Text("Saved automatically on this Mac")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .focusable()
                    .focusEffectDisabled()
                    .focused($listIsFocused)
                    .onAppletFocusRestore { listIsFocused = true }
                    .task { listIsFocused = true }
                } else {
                    noteList
                    Text("↑↓ Select · ↵ Edit · ⌘K Actions")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.horizontal, applet.isEditing && applet.pendingDeletion == nil ? NotchLayout.contentInset : 32)
        .padding(.top, 12)
        .padding(.bottom, applet.isEditing && applet.pendingDeletion == nil ? NotchLayout.contentInset : 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background {
            Button("Delete note") { applet.requestDeletion() }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(applet.store.isReadOnly || applet.store.selectedNote == nil || applet.pendingDeletion != nil)
                .hidden()
        }
        .onKeyPress(.return) {
            guard !applet.isEditing, applet.pendingDeletion == nil, applet.store.selectedNote != nil else { return .ignored }
            applet.isEditing = true
            return .handled
        }
        .onDisappear { applet.store.flush() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in applet.store.flush() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            if applet.isEditing {
                Button(action: closeEditor) { Label("All notes", systemImage: "chevron.left") }
                    .accessibilityLabel("All notes, Escape")
            } else {
                Text("Notes")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
            }

            Spacer()

            Button { applet.createNote() } label: {
                Text("New note  ⌘N")
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
            }
            .keyboardShortcut("n", modifiers: .command)
            .disabled(applet.store.isReadOnly)
        }
        .buttonStyle(.plain)
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, applet.isEditing ? 24 : 0)
    }

    private func deletionConfirmation(_ note: QuickNote) -> some View {
        VStack(spacing: 12) {
            Text("Delete this note?")
                .font(.system(size: 15, weight: .semibold))
            Text(note.title)
                .font(.system(size: 13))
                .lineLimit(2)
                .multilineTextAlignment(.center)
            Text("This cannot be undone.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            HStack(spacing: 24) {
                Button("Keep note  esc") { applet.dismissOverlay() }
                    .keyboardShortcut(.escape, modifiers: [])
                Button("Delete  ⌘⌫", role: .destructive) {
                    applet.confirmDeletion()
                    restoreFocus()
                }
                .keyboardShortcut(.delete, modifiers: .command)
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .medium))
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .focusable()
        .focusEffectDisabled()
        .focused($deletionIsFocused)
        .onAppletFocusRestore { deletionIsFocused = true }
        .task { deletionIsFocused = true }
    }

    private func closeEditor() {
        applet.finishEditing()
        restoreFocus()
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
                                Text(note.updatedAt, format: .dateTime.day().month(.abbreviated).year().locale(Locale(identifier: "en_GB")))
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
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
        .onAppletFocusRestore { listIsFocused = true }
        .task { listIsFocused = true }
        .onDisappear { listIsFocused = false }
    }
}
