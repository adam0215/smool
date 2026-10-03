import SwiftUI

struct NotesEditor: View {
    @Binding var text: String
    let isReadOnly: Bool
    let saveStatus: String
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Spacer(minLength: 0)

            HStack {
                Text(saveStatus)
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Text("esc All notes")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)

            FloatingComposer(
                text: $text,
                recipient: "Note",
                placeholder: "Write a thought…",
                isEditable: !isReadOnly,
                onClose: onClose
            )
        }
    }
}
