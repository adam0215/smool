import SwiftUI

struct NotchActionsMenu: View {
    let presentation: NotchPresentation
    var restoreFocus: () -> Void = {}

    var body: some View {
        Button {
            restoreFocus()
            presentation.showTool(.actions)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).focusable(false)
        .foregroundStyle(presentation.showsActions ? .primary : .secondary)
        .accessibilityLabel("Actions")
        .help("Actions · ⌘K")
    }
}
