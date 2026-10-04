import SwiftUI

struct AppletPadding: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

@MainActor @Observable
final class NotchHelpState {
    var text: String?
}

private struct NotchHelpKey: EnvironmentKey {
    static let defaultValue: NotchHelpState? = nil
}

extension EnvironmentValues {
    var notchHelp: NotchHelpState? {
        get { self[NotchHelpKey.self] }
        set { self[NotchHelpKey.self] = newValue }
    }
}

private struct NotchHelp: ViewModifier {
    let text: String
    @Environment(\.notchHelp) private var help

    private var isVisible: Bool { help?.text == text }

    func body(content: Content) -> some View {
        content
            .overlay {
                if isVisible {
                    Text(text)
                        .font(.system(size: 12, weight: .medium))
                        .lineSpacing(7)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.black.opacity(0.94), in: .rect(cornerRadius: 24))
                        .onTapGesture { help?.text = nil }
                }
            }
            .onDisappear { if isVisible { help?.text = nil } }
            .onKeyPress("?") { help?.text = isVisible ? nil : text; return .handled }
            .onKeyPress(.escape) {
                guard isVisible else { return .ignored }
                help?.text = nil
                return .handled
            }
    }
}

extension View {
    func notchHelp(_ text: String) -> some View { modifier(NotchHelp(text: text)) }
}
