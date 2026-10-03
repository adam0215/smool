import SwiftUI

struct NotesAppletView: View {
    @Bindable var applet: NotesApplet
    let onSendToCodex: ((String) -> Void)?
    let restoreFocus: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                if applet.isEditing {
                    Button {
                        applet.store.flush()
                        applet.isEditing = false
                        restoreFocus()
                    } label: { Label("Alla anteckningar", systemImage: "chevron.left") }
                    .keyboardShortcut(.escape, modifiers: [])
                } else {
                    Text("Anteckningar").fontWeight(.medium)
                }

                Spacer()

                Button { applet.createNote() } label: { Image(systemName: "square.and.pencil") }
                    .keyboardShortcut("n", modifiers: .command)
                    .accessibilityLabel("Ny anteckning")
                    .help("Ny anteckning · ⌘N")
                    .disabled(applet.store.isReadOnly)

                if let note = applet.store.selectedNote {
                    Button { applet.pendingDeletion = note } label: { Image(systemName: "trash") }
                        .accessibilityLabel("Ta bort anteckning")
                        .disabled(applet.store.isReadOnly)
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)

            if let error = applet.store.errorMessage {
                HStack(alignment: .top) {
                    Text(error).lineLimit(3).font(.system(size: 10))
                    Spacer(minLength: 2)
                    Button("Försök igen") { applet.store.reload() }
                        .buttonStyle(.plain)
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundStyle(.orange)
            }

            if applet.isEditing, let note = applet.store.selectedNote {
                NotesEditor(
                    text: Binding(get: { applet.store.selectedNote?.text ?? "" }, set: { applet.store.update(note.id, text: $0) }),
                    isReadOnly: applet.store.isReadOnly,
                    saveStatus: applet.store.errorMessage != nil ? "Kunde inte spara" : (applet.store.hasUnsavedChanges ? "Sparar…" : "Sparad"),
                    onSendToCodex: onSendToCodex.map { callback in { applet.store.flush(); callback(applet.store.selectedNote?.text ?? "") } },
                    onClose: { applet.store.flush(); applet.isEditing = false; restoreFocus() }
                )
                .id(note.id)
            } else if applet.store.notes.isEmpty {
                VStack(spacing: 8) {
                    Text(applet.store.isReadOnly ? "Anteckningarna är inte tillgängliga" : "En tanke att spara?")
                        .font(.system(size: 13, weight: .medium))
                    Button("Ny anteckning") { applet.createNote() }
                        .buttonStyle(FloatingControlStyle())
                        .disabled(applet.store.isReadOnly)
                    Text("Sparas automatiskt på den här datorn")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                noteList
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .alert("Ta bort anteckningen?", isPresented: Binding(get: { applet.pendingDeletion != nil }, set: { if !$0 { applet.pendingDeletion = nil } })) {
            Button("Avbryt", role: .cancel) { applet.pendingDeletion = nil }
            Button("Ta bort", role: .destructive) {
                if let note = applet.pendingDeletion { applet.store.delete(note.id) }
                applet.pendingDeletion = nil
                if applet.store.notes.isEmpty { applet.isEditing = false }
            }
        } message: {
            Text("\(applet.pendingDeletion?.title ?? "Anteckningen") tas bort permanent.")
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
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(applet.store.notes) { note in
                        Button {
                            applet.store.select(note.id)
                            applet.isEditing = true
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "note.text").foregroundStyle(.secondary)
                                Text(note.title).lineLimit(1)
                                Spacer(minLength: 4)
                                Text(note.updatedAt, style: .date).font(.system(size: 9)).foregroundStyle(.secondary)
                            }
                            .font(.system(size: 12))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 8)
                            .background(.white.opacity(note.id == applet.store.selectedID ? 0.09 : 0), in: RoundedRectangle(cornerRadius: 8))
                            .contentShape(Rectangle())
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
    }
}
