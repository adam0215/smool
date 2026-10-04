import SwiftUI

/// A single floating glass surface. Place ordinary controls inside it without
/// applying another glass effect to each control.
struct FloatingGlass: ViewModifier {
    var cornerRadius: CGFloat = 24
    var cornerStyle: RoundedCornerStyle = .continuous

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: cornerStyle)

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

/// A quiet busy indication. The timeline exists only while the text is visible and active.
struct ShimmeringText: View {
    let text: String
    var isActive = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isVisible = false

    init(_ text: String, isActive: Bool = true) {
        self.text = text
        self.isActive = isActive
    }

    var body: some View {
        Text(text)
            .overlay {
                if isActive, isVisible, !reduceMotion {
                    TimelineView(.animation(minimumInterval: 1.0 / 24)) { context in
                        let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.8) / 2.8
                        LinearGradient(
                            colors: [.clear, .white.opacity(0.45), .clear],
                            startPoint: UnitPoint(x: phase * 2 - 1, y: 0.5),
                            endPoint: UnitPoint(x: phase * 2, y: 0.5)
                        )
                        .mask(Text(text))
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
            .onAppear { isVisible = true }
            .onDisappear { isVisible = false }
    }
}

/// The caller owns sending, errors and draft lifetime. Closing or sending never
/// clears the binding; callers can preserve edits made during an in-flight send.
struct FloatingComposer: View {
    @Binding var text: String
    var recipient: String
    var placeholder = "Write a message…"
    var isEditable = true
    var isSending = false
    var canSend = true
    var focusRequest = 0
    var isEditing = true
    var onBeginEditing: (() -> Void)?
    var onSend: (() -> Void)? = nil
    var onClose: () -> Void

    @FocusState private var messageFocused: Bool
    @State private var selection: TextSelection?

    private var sendIsEnabled: Bool {
        onSend != nil && canSend && !isSending && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField(placeholder, text: $text, selection: $selection, axis: .vertical)
                .textFieldStyle(.plain)
                .disabled(!isEditable)
                .font(.system(size: 14))
                .lineLimit(1...4)
                .focused($messageFocused)
                .accessibilityLabel("Message to \(recipient)")
                .padding(.vertical, 8)
                .padding(.leading, 10)
                .onKeyPress(.return, phases: .down) { key in
                    guard onSend != nil else { return .ignored }
                    let modifiers = key.modifiers.intersection([.command, .control, .option, .shift])
                    if modifiers == .shift {
                        let range: Range<String.Index>
                        if case .selection(let selected) = selection?.indices { range = selected }
                        else { range = text.endIndex..<text.endIndex }
                        let offset = text.distance(from: text.startIndex, to: range.lowerBound)
                        text.replaceSubrange(range, with: "\n")
                        selection = TextSelection(insertionPoint: text.index(text.startIndex, offsetBy: offset + 1))
                        return .handled
                    }
                    guard modifiers.isEmpty else { return .ignored }
                    if sendIsEnabled { onSend?() }
                    return .handled
                }

            if let onSend {
                Button {
                    guard sendIsEnabled else { return }
                    onSend()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 32, height: 32)
                        .foregroundStyle(sendIsEnabled ? Color.black : Color.secondary)
                        .background(.white.opacity(sendIsEnabled ? 0.94 : 0.06), in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(!sendIsEnabled)
                .accessibilityLabel(isSending ? "Sending message" : "Send message")
                .help("Send message")
            }
        }
        .padding(8)
        .modifier(FloatingGlass(cornerRadius: 24, cornerStyle: .circular))
        .fixedSize(horizontal: false, vertical: true)
        .onAppletFocusRestore {
            guard isEditing else { return }
            messageFocused = false
        }
        .onChange(of: messageFocused) { _, focused in
            if focused { onBeginEditing?() }
        }
        .onChange(of: focusRequest) { _, _ in messageFocused = isEditing && isEditable }
        .onChange(of: isEditing) { _, editing in messageFocused = editing && isEditable }
        .onKeyPress(.escape) {
            messageFocused = false
            onClose()
            return .handled
        }
        .task {
            await Task.yield()
            guard !Task.isCancelled else { return }
            messageFocused = isEditing && isEditable
        }
    }
}
