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
    var onChooseRecipient: (() -> Void)?
    var onSend: (() -> Void)? = nil
    var onClose: () -> Void

    private enum Focus: Hashable { case navigation, message }
    @FocusState private var focus: Focus?

    private var sendIsEnabled: Bool {
        onSend != nil && canSend && !isSending && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if let onChooseRecipient {
                    Button(action: onChooseRecipient) {
                        HStack(spacing: 5) {
                            Text(recipient).lineLimit(1).truncationMode(.middle)
                            Text("⌘L").font(.system(size: 9))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isSending)
                    .keyboardShortcut("l", modifiers: .command)
                    .accessibilityLabel("Choose recipient, \(recipient)")
                } else {
                    Text(recipient).lineLimit(1).truncationMode(.middle)
                }

                Spacer(minLength: 4)

                Button(action: onClose) {
                    Text("esc")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .frame(width: 28, height: 28)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close draft")
                .help("Close · esc")
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.leading, 8)

            HStack(alignment: .bottom, spacing: 10) {
                TextField(placeholder, text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .disabled(!isEditable)
                    .font(.system(size: 14))
                    .lineLimit(1...4)
                    .focused($focus, equals: .message)
                    .accessibilityLabel("Message to \(recipient)")
                    .padding(.vertical, 8)
                    .padding(.leading, 8)

                if let onSend {
                    if isSending {
                        ShimmeringText("Sending…")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(minHeight: 36)
                            .accessibilityLabel("Sending message")
                    } else {
                        Button {
                            guard sendIsEnabled else { return }
                            onSend()
                        } label: {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 13, weight: .semibold))
                                .frame(width: 36, height: 36)
                                .foregroundStyle(sendIsEnabled ? Color.black : Color.secondary)
                                .background(.white.opacity(sendIsEnabled ? 0.94 : 0.06), in: Circle())
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .disabled(!sendIsEnabled)
                        .keyboardShortcut(.return, modifiers: .command)
                        .accessibilityLabel("Send message")
                        .help("Send · ⌘↵")
                    }
                }
            }

            if onSend != nil || focus == .navigation {
                HStack {
                    if focus == .navigation, isEditable { Text("↵ Edit") }
                    Spacer(minLength: 8)
                    if onSend != nil, !isSending { Text("⌘↵ Send") }
                }
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .frame(minHeight: 2 * (NotchLayout.bottomRadius - NotchLayout.contentInset))
        .modifier(FloatingGlass(
            cornerRadius: NotchLayout.bottomRadius - NotchLayout.contentInset,
            cornerStyle: .circular
        ))
        .fixedSize(horizontal: false, vertical: true)
        .focusable(interactions: .edit)
        .focused($focus, equals: .navigation)
        .focusEffectDisabled()
        .onAppletFocusRestore { focus = .navigation }
        .onKeyPress(.return, phases: .down) { key in
            guard focus == .navigation, key.modifiers.isEmpty, isEditable else { return .ignored }
            focus = .message
            return .handled
        }
        .onKeyPress(.escape) {
            onClose()
            return .handled
        }
        .task {
            await Task.yield()
            guard !Task.isCancelled else { return }
            focus = isEditable ? .message : .navigation
        }
    }
}
