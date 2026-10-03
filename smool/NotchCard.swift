import SwiftUI

struct NotchCard: ViewModifier {
    var elevated = true

    func body(content: Content) -> some View {
        let padded = content
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        if elevated {
            padded.modifier(CardGlass(shape: UnevenRoundedRectangle(
                topLeadingRadius: 16, bottomLeadingRadius: 56,
                bottomTrailingRadius: 56, topTrailingRadius: 16
            ), isSelected: true))
        } else {
            padded
        }
    }
}

private struct NotchHelp: ViewModifier {
    let text: String
    @State private var isVisible = false

    func body(content: Content) -> some View {
        content
            .overlay {
                if isVisible {
                    Text(text)
                        .font(.system(size: 12, weight: .medium))
                        .lineSpacing(7)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.black.opacity(0.94), in: .rect(cornerRadius: 24))
                        .onTapGesture { isVisible = false }
                }
            }
            .onKeyPress("?") { isVisible.toggle(); return .handled }
            .onKeyPress(.escape) {
                guard isVisible else { return .ignored }
                isVisible = false
                return .handled
            }
    }
}

extension View {
    func notchHelp(_ text: String) -> some View { modifier(NotchHelp(text: text)) }
}
