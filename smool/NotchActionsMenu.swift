import SwiftUI

struct NotchActionsMenu: View {
    @Bindable var presentation: NotchPresentation

    var body: some View {
        Button { presentation.showsActions.toggle() } label: {
            Image(systemName: "ellipsis").font(.system(size: 14, weight: .semibold))
                .frame(width: 24, height: 24).contentShape(Rectangle())
        }
        .buttonStyle(.plain).focusable(false)
        .keyboardShortcut("k", modifiers: .command)
        .accessibilityLabel("Åtgärder")
        .help("Åtgärder · ⌘K")
        .popover(isPresented: $presentation.showsActions, arrowEdge: .bottom) {
            ActionList(actions: presentation.activeApplet.actions) { presentation.showsActions = false }
                .preferredColorScheme(.dark)
        }
    }
}
