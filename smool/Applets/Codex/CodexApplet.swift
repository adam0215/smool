import SwiftUI

@MainActor
final class CodexApplet: Applet {
    let id = AppletID(rawValue: "codex")
    let title = "Codex"
    let icon = AppletIcon.asset("Codex")
    let tint = Color.purple
    let state: CodexAppletState
    let service: CodexService
    private var connectionTask: Task<Void, Never>?

    init(service: CodexService = CodexService(), state: CodexAppletState = CodexAppletState()) {
        self.service = service
        self.state = state
    }

    var contentHeight: CGFloat {
        if state.presentation == .request { return 340 }
        if state.page == .usage { return 176 }
        if state.page == .newThread { return state.newThread.error == nil ? 200 : 256 }
        return 256
    }

    var background: AppletBackground? {
        AppletBackground(color: HomePalette.codex, horizontalPosition: 0.75)
    }

    var hasPresentedOverlay: Bool { state.presentation != .deck }

    /// Presents a recipient picker. This never sends or connects a thread by itself.
    func beginComposing(_ text: String) {
        state.pendingText = text
        cancelConnection()
        state.page = .history
        state.presentation = .recipientPicker
    }

    var attention: [CodexThreadAttention] {
        service.threads.compactMap { thread in
            guard thread.isConnected, let status = service.attentionByThread[thread.id] else { return nil }
            return CodexThreadAttention(threadID: thread.id, title: thread.title, status: status,
                                        isUnread: service.unreadThreadIDs.contains(thread.id),
                                        url: service.isLocallyOwned(thread.id) ? nil : CodexDesktopProtocol.threadURL(thread.id))
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
        state.page = .active
        state.groupsByProject = false
        state.searches[.active] = ""
        state.selection[.active] = item.threadID
        state.retainedActiveThreadIDs = [item.threadID]
        state.presentation = .deck
        service.selectThread(item.threadID)
    }

    func setStatusMonitoring(_ enabled: Bool) { service.setStatusMonitoring(enabled) }

    var pages: [AppletPage] {
        CodexPage.allCases.map { page in
            AppletPage(id: page.rawValue, isSelected: state.page == page) {
                self.state.presentation = .deck
                self.state.page = page
            }
        }
    }

    func makeView(context: AppletContext, artwork: NSImage?) -> AnyView {
        AnyView(CodexAppletView(applet: self, restoreFocus: context.restoreFocus))
    }

    func handleArrow(_ arrow: AppletArrow, command: Bool) -> Bool {
        guard state.presentation == .deck else { return false }
        if command {
            guard !arrow.isVertical, state.groupsByProject, state.page == .history else { return false }
            state.moveProject(arrow.offset, in: service.projects)
        } else {
            guard arrow.isVertical else { return false }
            state.page = cyclingPage(in: CodexPage.allCases, to: state.page, offset: arrow.offset)
        }
        return true
    }

    func deactivate() { dismissOverlay() }

    func dismissOverlay() {
        cancelConnection()
        state.presentation = .deck
    }

    func cancelConnection() {
        connectionTask?.cancel()
        connectionTask = nil
    }

    func compose(_ thread: CodexThread) {
        cancelConnection()
        state.selection[state.page] = thread.id
        state.presentation = .composer(thread)
    }

    func beginSearch() {
        cancelConnection()
        if state.page == .usage || state.page == .newThread { state.page = .history }
        state.presentation = .search
        state.searchFocusRequest += 1
    }

    func refreshOrConnect() {
        if case .composer(let thread) = state.presentation {
            guard connectionTask == nil, service.isConnectingThreadID == nil else { return }
            connectionTask = Task {
                defer { if !Task.isCancelled { connectionTask = nil } }
                state.sendErrors[thread.id] = nil
                let connected = await service.ensureConnected(to: thread)
                guard !Task.isCancelled, case .composer(let recipient) = state.presentation,
                      recipient.id == thread.id else { return }
                if connected { state.composerFocusRequest += 1 }
                else { state.sendErrors[thread.id] = service.error }
            }
        } else {
            Task {
                await service.refresh()
                guard !Task.isCancelled, let thread = previewThread else { return }
                await service.loadHistoryPreview(thread, force: true)
            }
        }
    }

    var previewThread: CodexThread? {
        guard let thread = state.threadSelection(in: service.displayedThreads, projects: service.projects).selectedThread else { return nil }
        if state.page == .history { return thread }
        guard state.page == .active, service.activities[thread.id]?.latestMessage == nil,
              activityIssue(for: thread.id) != nil else { return nil }
        return service.threads.first { $0.id == thread.id } ?? thread
    }

    func activityIssue(for id: String) -> String? {
        service.sessionErrors[id] ?? service.activityErrors[id]
            ?? (service.threads.first { $0.id == id }?.isConnected != true
                ? service.liveError ?? "Live activity is unavailable." : nil)
    }

    var actions: [AppletAction] {
        let state = state
        let service = service
        var actions = [
            AppletAction(id: "search-threads", title: "Search threads", symbol: "magnifyingglass", shortcut: AppletShortcut(key: "f")) { self.beginSearch() },
            AppletAction(id: "show-archived", title: "Show archived", symbol: "archivebox", shortcut: AppletShortcut(key: "a", modifiers: [.command, .shift]), selected: service.includesArchived) {
                state.page = .history
                state.presentation = .deck
                Task { await service.setIncludesArchived(!service.includesArchived) }
            },
            AppletAction(id: "choose-project", title: "Choose project", symbol: "folder", shortcut: AppletShortcut(key: "p")) { state.openProjects() },
            AppletAction(id: "group-by-project", title: "Group by project", symbol: "folder", shortcut: AppletShortcut(key: "p", modifiers: [.command, .shift]), selected: state.groupsByProject) {
                state.groupsByProject.toggle()
                state.page = .history
                state.presentation = .deck
            },
            AppletAction(id: "active-threads", title: "Active threads", symbol: "waveform", selected: state.page == .active) { state.presentation = .deck; state.page = .active },
            AppletAction(id: "previous-threads", title: "Previous threads", symbol: "clock", selected: state.page == .history) { state.presentation = .deck; state.page = .history },
            AppletAction(id: "new-thread", title: "New thread", symbol: "plus", selected: state.page == .newThread) { state.page = .newThread; state.presentation = .newThread },
            AppletAction(id: "usage", title: "Usage", symbol: "chart.pie", selected: state.page == .usage) { state.presentation = .deck; state.page = .usage }
        ]
        if state.page == .newThread {
            actions.insert(AppletAction(id: "write-new-thread", title: "Write new thread", symbol: "square.and.pencil", shortcut: AppletShortcut(key: "n")) {
                state.presentation = .newThread
            }, at: 0)
        }
        if let thread = state.threadSelection(in: service.displayedThreads, projects: service.projects).selectedThread,
           state.page != .usage {
            actions.insert(contentsOf: [
                AppletAction(id: "write-to-thread", title: "Write to thread", symbol: "square.and.pencil", shortcut: AppletShortcut(key: "n")) { self.compose(thread) }
            ], at: 0)
            if service.isLocallyOwned(thread.id) {
                if let request = service.localRequests(for: thread.id).first {
                    actions.insert(AppletAction(id: "review-request", title: "Review request", symbol: "bubble.left.and.exclamationmark.bubble.right") {
                        state.requestID = request.id
                        state.presentation = .request
                    }, at: 0)
                }
                actions.append(AppletAction(id: "stop-turn", title: "Stop turn", symbol: "stop.fill", shortcut: AppletShortcut(key: ".")) {
                    Task { await service.cancelLocalTurn(thread.id) }
                })
            } else if let url = CodexDesktopProtocol.threadURL(thread.id) {
                actions.append(AppletAction(id: "open-in-codex", title: "Open in Codex", symbol: "arrow.up.right", shortcut: AppletShortcut(key: .return, modifiers: [])) { NSWorkspace.shared.open(url) })
            }
        }
        if state.pendingText != nil {
            actions.append(AppletAction(id: "choose-recipient-for-saved-draft", title: "Choose recipient for saved draft", symbol: "square.and.pencil") {
                state.presentation = .recipientPicker
            })
        }
        if case .composer = state.presentation {
            actions.append(AppletAction(id: "connect-thread", title: "Connect thread", symbol: "arrow.triangle.2.circlepath", shortcut: AppletShortcut(key: "r")) { self.refreshOrConnect() })
        } else {
            actions.append(AppletAction(id: "refresh", title: "Refresh", symbol: "arrow.clockwise", shortcut: AppletShortcut(key: "r")) { self.refreshOrConnect() })
        }
        if state.groupsByProject, state.page == .history, state.presentation == .deck {
            actions.insert(contentsOf: [
                AppletAction(id: "previous-project", title: "Previous project", symbol: "chevron.left", shortcut: AppletShortcut(key: .leftArrow)) { state.moveProject(-1, in: service.projects) },
                AppletAction(id: "next-project", title: "Next project", symbol: "chevron.right", shortcut: AppletShortcut(key: .rightArrow)) { state.moveProject(1, in: service.projects) }
            ], at: 3)
        }
        if state.presentation == .projects || state.presentation == .recipientPicker {
            actions.removeAll { ["search-threads", "write-to-thread", "write-new-thread"].contains($0.id) }
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
