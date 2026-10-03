import SwiftUI

struct NotesEditor: View {
    @Binding var text: String
    let isReadOnly: Bool
    let saveStatus: String
    let onSendToCodex: (() -> Void)?
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FloatingComposer(
                text: $text,
                recipient: "Anteckning",
                placeholder: "Skriv en tanke…",
                onClose: onClose
            )
            .disabled(isReadOnly)

            HStack {
                Text(saveStatus)
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                if let onSendToCodex {
                    Button(action: onSendToCodex) { Label("Till Codex", systemImage: "arrow.up.right") }
                        .font(.system(size: 11, weight: .medium))
                        .buttonStyle(.plain)
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .help("Öppna som utkast i Codex")
                }
            }
            .padding(.horizontal, 12)
            Spacer(minLength: 0)
        }
    }
}
