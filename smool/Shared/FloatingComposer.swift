import SwiftUI

/// A single floating glass surface. Place ordinary controls inside it without
/// applying another glass effect to each control.
struct FloatingGlass: ViewModifier {
    var cornerRadius: CGFloat = 24

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        Group {
            if reduceTransparency {
                content.background(Color(nsColor: .windowBackgroundColor), in: shape)
            } else {
                content.glassEffect(.regular, in: shape)
            }
        }
        .overlay {
            if reduceTransparency || contrast == .increased {
                shape.strokeBorder(.primary.opacity(contrast == .increased ? 0.6 : 0.2), lineWidth: 1)
                    .allowsHitTesting(false)
            }
        }
    }
}

/// For standalone floating actions. Controls embedded in content use a plain style.
struct FloatingControlStyle: PrimitiveButtonStyle {
    var isProminent = false

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        if reduceTransparency {
            if isProminent {
                Button(configuration).buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
            } else {
                Button(configuration).buttonStyle(.bordered).buttonBorderShape(.capsule)
            }
        } else if isProminent {
            Button(configuration).buttonStyle(.glassProminent).buttonBorderShape(.capsule)
        } else {
            Button(configuration).buttonStyle(.glass).buttonBorderShape(.capsule)
        }
    }
}

/// The caller owns sending, errors and draft lifetime. Closing or sending never
/// clears the binding; callers can preserve edits made during an in-flight send.
struct FloatingComposer: View {
    @Binding var text: String
    var recipient: String
    var placeholder = "Skriv ett meddelande…"
    var isSending = false
    var canSend = true
    var onChooseRecipient: (() -> Void)?
    var onSend: (() -> Void)? = nil
    var onClose: () -> Void

    @FocusState private var isFocused: Bool

    private var sendIsEnabled: Bool {
        onSend != nil && canSend && !isSending && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if let onChooseRecipient {
                    Button(action: onChooseRecipient) {
                        HStack(spacing: 5) {
                            Text(recipient).lineLimit(1).truncationMode(.middle)
                            Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isSending)
                    .accessibilityLabel("Välj mottagare, \(recipient)")
                } else {
                    Text(recipient).lineLimit(1).truncationMode(.middle)
                }

                Spacer(minLength: 4)

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 24, height: 24)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Stäng utkast")
                .help("Stäng · esc")
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)

            HStack(alignment: .bottom, spacing: 10) {
                TextField(placeholder, text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .lineLimit(1...5)
                    .focused($isFocused)
                    .accessibilityLabel("Meddelande till \(recipient)")
                    .padding(.vertical, 5)

                if let onSend {
                    Button {
                        guard sendIsEnabled else { return }
                        onSend()
                    } label: {
                        Group {
                            if isSending {
                                ProgressView().controlSize(.mini)
                            } else {
                                Image(systemName: "arrow.up")
                                    .font(.system(size: 13, weight: .semibold))
                            }
                        }
                        .frame(width: 28, height: 28)
                        .background(.primary.opacity(sendIsEnabled ? 0.12 : 0.04), in: Circle())
                        .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!sendIsEnabled)
                    .keyboardShortcut(.return, modifiers: .command)
                    .accessibilityLabel(isSending ? "Skickar meddelande" : "Skicka meddelande")
                    .help("Skicka · ⌘↵")
                }
            }
            .padding(.vertical, 10)
            .padding(.leading, 18)
            .padding(.trailing, 10)
            .modifier(FloatingGlass())
        }
        .fixedSize(horizontal: false, vertical: true)
        .onKeyPress(.escape) {
            onClose()
            return .handled
        }
        .task {
            await Task.yield()
            isFocused = true
        }
    }
}
