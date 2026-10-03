import SwiftUI

struct SelectionActionsView: View {
    let selection: SelectedText?
    let error: SelectionCaptureError?
    var canSaveNote = true
    var saveNoteUnavailableReason: String? = nil
    var canComposeInCodex = true
    let saveNote: (String) -> Void
    let composeInCodex: (String) -> Void
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Selected text")
                        .font(.system(size: 12, weight: .semibold))
                    if let selection {
                        Text(selection.applicationName)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 28, height: 28)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Close")
                .help("Close · esc")
                .keyboardShortcut(.escape, modifiers: [])
            }

            if let selection {
                ScrollView {
                    Text(selection.text)
                        .font(.system(size: 12))
                        .lineSpacing(3)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                .frame(maxHeight: 120)
                .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))

                HStack(spacing: 4) {
                    Button { saveNote(selection.text) } label: {
                        Label("Save note", systemImage: "note.text.badge.plus")
                    }
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(!canSaveNote)
                    .help(saveNoteUnavailableReason ?? "Save note · ⌘S")

                    Spacer(minLength: 0)

                    Button { composeInCodex(selection.text) } label: {
                        Label("To Codex…", systemImage: "arrow.up.right")
                    }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!canComposeInCodex)
                }
                .buttonStyle(NotchControlStyle())

                if !canSaveNote || !canComposeInCodex {
                    VStack(alignment: .leading, spacing: 4) {
                        if !canSaveNote {
                            Text(saveNoteUnavailableReason ?? "Enable Notes in Settings to save selected text.")
                        }
                        if !canComposeInCodex {
                            Text("Enable Codex in Settings to create a draft.")
                        }
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text(error?.localizedDescription ?? "Reading the selection…")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if case .permission = error {
                    Button("Allow access…", action: SelectedTextCapture.requestPermission)
                        .buttonStyle(NotchControlStyle())
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
