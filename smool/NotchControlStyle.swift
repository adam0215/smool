import SwiftUI

struct NotchControlStyle: ButtonStyle {
    var isSelected = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .modifier(GlassInk(illumination: 1, isSelected: isSelected))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .modifier(CardGlass(shape: Capsule(), isSelected: isSelected || configuration.isPressed))
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}
