import SwiftUI

@MainActor
final class CodexApplet: Applet {
    let id = AppletID(rawValue: "codex")
    let title = "Codex"
    let icon = AppletIcon.asset("Codex")
    let tint = Color.purple
    let homeShortcut: HomeApp? = .codex
    let state = CodexAppletState()
    let service = CodexService()

    var contentHeight: CGFloat {
        if case .composer = state.scope { return max(156, state.composerHeight + 40) }
        return state.page == .usage ? 176 : 156
    }

    var background: AppletBackground? {
        AppletBackground(color: HomeGlow.color(for: .codex), horizontalPosition: 0.75)
    }

    var hasPresentedOverlay: Bool { state.showsProjects }

    var pages: [AppletPage] {
        CodexPage.allCases.map { page in
            AppletPage(id: page.rawValue, isSelected: state.page == page) {
                self.state.scope = .deck
                self.state.page = page
            }
        }
    }

    func makeView(context: AppletContext, artwork: NSImage?) -> AnyView {
        AnyView(CodexAppletView(service: service, state: state, restoreFocus: context.restoreFocus))
    }

    func handleArrow(_ arrow: AppletArrow, command: Bool) -> Bool {
        guard !state.showsProjects, state.scope == .deck else { return false }
        if command {
            guard !arrow.isVertical, state.groupsByProject, state.page == .history else { return false }
            state.moveProject(arrow.offset, in: service.projects)
        } else {
            guard arrow.isVertical else { return false }
            state.page = cyclingPage(in: CodexPage.allCases, to: state.page, offset: arrow.offset)
        }
        return true
    }

    func dismissOverlay() { state.showsProjects = false }

    var actions: [AppletAction] {
        let state = state
        let service = service
        var actions = [
            AppletAction(id: "Sök trådar", symbol: "magnifyingglass", shortcut: "⌘F") {
                if state.page == .usage { state.page = .history }
                state.scope = .search
            },
            AppletAction(id: "Visa arkiverade", symbol: "archivebox", shortcut: "⇧⌘A", selected: service.includesArchived) {
                state.page = .history
                state.scope = .deck
                Task { await service.setIncludesArchived(!service.includesArchived) }
            },
            AppletAction(id: "Välj projekt", symbol: "folder", shortcut: "⌘P") { state.openProjects() },
            AppletAction(id: "Gruppera per projekt", symbol: "folder", shortcut: "⇧⌘P", selected: state.groupsByProject) {
                state.groupsByProject.toggle()
                state.page = .history
                state.scope = .deck
            },
            AppletAction(id: "Aktiva trådar", symbol: "waveform", selected: state.page == .active) { state.scope = .deck; state.page = .active },
            AppletAction(id: "Tidigare trådar", symbol: "clock", selected: state.page == .history) { state.scope = .deck; state.page = .history },
            AppletAction(id: "Användning", symbol: "chart.pie", selected: state.page == .usage) { state.scope = .deck; state.page = .usage }
        ]
        if state.groupsByProject, state.page == .history, state.scope == .deck {
            actions.insert(contentsOf: [
                AppletAction(id: "Föregående projekt", symbol: "chevron.left", shortcut: "⌘←") { state.moveProject(-1, in: service.projects) },
                AppletAction(id: "Nästa projekt", symbol: "chevron.right", shortcut: "⌘→") { state.moveProject(1, in: service.projects) }
            ], at: 3)
        }
        return actions
    }
}
