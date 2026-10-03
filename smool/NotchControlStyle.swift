import SwiftUI

struct ShortcutLabel: View {
    let title: String
    let keys: String

    init(_ title: String, keys: String) {
        self.title = title
        self.keys = keys
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
            Text(keys)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }
}

/// Controls embedded in applet content. Floating actions use FloatingControlStyle.
struct NotchControlStyle: ButtonStyle {
    var isSelected = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.white.opacity(isSelected ? 0.12 : 0), in: Capsule())
            .overlay {
                Capsule().strokeBorder(.white.opacity(isSelected ? 0.32 : 0), lineWidth: 0.5)
            }
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.65 : 1)
    }
}
