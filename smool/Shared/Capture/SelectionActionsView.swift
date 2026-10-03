import SwiftUI

struct SelectionActionsView: View {
    let selection: SelectedText?
    let error: SelectionCaptureError?
    let saveNote: (String) -> Void
    let composeInCodex: (String) -> Void
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(selection.map { "Markerat i \($0.applicationName)" } ?? "Markerad text")
                    .font(.headline)
                Spacer()
                Button(action: dismiss) { Image(systemName: "xmark") }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Stäng")
                    .keyboardShortcut(.escape, modifiers: [])
            }

            if let selection {
                ScrollView {
                    Text(selection.text)
                        .font(.system(size: 12))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 120)

                HStack {
                    Button("Spara anteckning") { saveNote(selection.text) }
                        .keyboardShortcut("s", modifiers: .command)
                    Button("Till Codex…") { composeInCodex(selection.text) }
                        .keyboardShortcut(.return, modifiers: .command)
                }
                .buttonStyle(NotchControlStyle())
            } else {
                Text(error?.localizedDescription ?? "Hämtar markeringen…")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                if case .permission = error {
                    Button("Tillåt åtkomst…", action: SelectedTextCapture.requestPermission)
                        .buttonStyle(NotchControlStyle())
                }
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
