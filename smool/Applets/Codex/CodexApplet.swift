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
        if state.page == .usage { return 176 }
        return state.isExpanded ? 510 : 300
    }

    var background: AppletBackground? {
        AppletBackground(color: HomeGlow.color(for: .codex), horizontalPosition: 0.75)
    }

    var hasPresentedOverlay: Bool {
        if case .composer = state.scope { return true }
        return state.showsProjects || state.showsRecipientPicker
    }

    /// Presents a recipient picker. This never sends or connects a thread by itself.
    func beginComposing(_ text: String) {
        state.pendingText = text
        state.scope = .deck
        state.page = .history
        state.showsRecipientPicker = true
    }

    var attention: [CodexThreadAttention] {
        service.threads.compactMap { thread in
            guard thread.isConnected, let status = service.attentionByThread[thread.id] else { return nil }
            return CodexThreadAttention(threadID: thread.id, title: thread.title, status: status,
                                        isUnread: service.unreadThreadIDs.contains(thread.id),
                                        url: CodexDesktopProtocol.threadURL(thread.id))
        }
    }

    var status: AppletStatus? {
        let items = attention
        if let item = items.first(where: { $0.status.needsAttention }) {
            return AppletStatus(kind: .needsAttention, label: item.status.label, symbol: "bubble.left.and.exclamationmark.bubble.right")
        }
        if items.contains(where: { $0.status == .working }) {
            return AppletStatus(kind: .working, label: "Codex is working", symbol: "waveform")
        }
        if items.contains(where: { $0.isUnread && $0.status == .idle }) {
            return AppletStatus(kind: .completed, label: "Codex is done", symbol: "checkmark")
        }
        return nil
    }

    func activateStatus() {
        let items = attention
        guard let item = items.first(where: { $0.status.needsAttention })
                ?? items.first(where: { $0.isUnread })
                ?? items.first(where: { $0.status == .working }) else { return }
        state.page = .history
        state.groupsByProject = false
        state.searches[.history] = ""
        state.selection[.history] = item.threadID
        state.scope = .deck
        service.selectThread(item.threadID)
    }

    func setStatusMonitoring(_ enabled: Bool) { service.setStatusMonitoring(enabled) }

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

    func dismissOverlay() {
        state.showsProjects = false
        state.showsRecipientPicker = false
        state.scope = .deck
    }

    var actions: [AppletAction] {
        let state = state
        let service = service
        var actions = [
            AppletAction(id: "Search threads", symbol: "magnifyingglass", shortcut: "⌘F") {
                if state.page == .usage { state.page = .history }
                state.scope = .search
            },
            AppletAction(id: "Show archived", symbol: "archivebox", shortcut: "⇧⌘A", selected: service.includesArchived) {
                state.page = .history
                state.scope = .deck
                Task { await service.setIncludesArchived(!service.includesArchived) }
            },
            AppletAction(id: "Choose project", symbol: "folder", shortcut: "⌘P") { state.openProjects() },
            AppletAction(id: "Group by project", symbol: "folder", shortcut: "⇧⌘P", selected: state.groupsByProject) {
                state.groupsByProject.toggle()
                state.page = .history
                state.scope = .deck
            },
            AppletAction(id: "Active threads", symbol: "waveform", selected: state.page == .active) { state.scope = .deck; state.page = .active },
            AppletAction(id: "Previous threads", symbol: "clock", selected: state.page == .history) { state.scope = .deck; state.page = .history },
            AppletAction(id: "Usage", symbol: "chart.pie", selected: state.page == .usage) { state.scope = .deck; state.page = .usage }
        ]
        if state.groupsByProject, state.page == .history, state.scope == .deck {
            actions.insert(contentsOf: [
                AppletAction(id: "Previous project", symbol: "chevron.left", shortcut: "⌘←") { state.moveProject(-1, in: service.projects) },
                AppletAction(id: "Next project", symbol: "chevron.right", shortcut: "⌘→") { state.moveProject(1, in: service.projects) }
            ], at: 3)
        }
        return actions
    }
}

struct CodexThreadAttention {
    let threadID: String
    let title: String
    let status: CodexAttention
    let isUnread: Bool
    let url: URL?
}
