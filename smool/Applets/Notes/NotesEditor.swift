import SwiftUI

struct NotesEditor: View {
    @Binding var text: String
    let isReadOnly: Bool
    let saveStatus: String
    let onSendToCodex: (() -> Void)?
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FloatingComposer(
                text: $text,
                recipient: "Note",
                placeholder: "Write a thought…",
                isEditable: !isReadOnly,
                onClose: onClose
            )

            HStack {
                Text(saveStatus)
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                if let onSendToCodex {
                    Button(action: onSendToCodex) { Label("To Codex", systemImage: "arrow.up.right") }
                        .font(.system(size: 11, weight: .medium))
                        .buttonStyle(NotchControlStyle())
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .help("Open as a draft in Codex")
                }
            }
            .padding(.horizontal, 16)
            Spacer(minLength: 0)
        }
    }
}
