import SwiftUI

/// Pages share vertical navigation while each page owns its controls and editing focus.
struct AppletPages<Page: Hashable, Content: View>: View {
    let pages: [Page]
    @Binding var selection: Page
    let title: (Page) -> String
    var isNavigating = true
    var editingHint = "⌘↵ Send · esc Back"
    var navigationHint = "↑↓ Change page · ↵ Open\n⌘K Actions · ? Close help"
    @ViewBuilder let content: (Page) -> Content

    @FocusState private var focused: Bool

    var body: some View {
        content(selection)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .id(selection)
            .modifier(AppletPadding())
            .padding(.horizontal, NotchLayout.contentInset)
            .padding(.bottom, NotchLayout.contentInset)
            .focusable(interactions: .edit)
            .focused($focused)
            .focusEffectDisabled()
            .task { await Task.yield(); focused = isNavigating }
            .onChange(of: isNavigating) { _, navigating in focused = navigating }
            .onKeyPress(keys: [.upArrow, .downArrow], phases: [.down, .repeat]) { press in
                guard isNavigating, press.modifiers.intersection([.command, .control, .option, .shift]).isEmpty else { return .ignored }
                selection = cyclingPage(in: pages, to: selection, offset: press.key == .upArrow ? -1 : 1)
                return .handled
            }
            .notchHelp(isNavigating ? navigationHint : editingHint)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("\(title(selection)), page \((pages.firstIndex(of: selection) ?? 0) + 1) of \(pages.count)")
    }
}
