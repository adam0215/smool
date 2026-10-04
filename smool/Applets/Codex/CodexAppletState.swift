import SwiftUI

enum CodexPage: String, CaseIterable {
    case active = "Active threads"
    case history = "Previous threads"
    case newThread = "New thread"
    case usage = "Usage"
}

enum CodexPresentation: Equatable {
    case deck, search, newThread, request
    case composer(CodexThread)
    case projects
    case recipientPicker
}

@MainActor @Observable
final class CodexAppletState {
    var groupsByProject = UserDefaults.standard.bool(forKey: "codex.groupsByProject") {
        didSet { UserDefaults.standard.set(groupsByProject, forKey: "codex.groupsByProject") }
    }
    let newThread = CodexNewThreadDraft()
    var projectID: String?
    var pendingText: String?
    var sendErrors: [String: String] = [:]
    var requestID: String?
    var requestAnswers: [String: [String: String]] = [:]
    var retainedActiveThreadIDs: Set<String> = []
    var page = CodexPage.active
    var presentation = CodexPresentation.deck
    var composerFocusRequest = 0
    var searchFocusRequest = 0
    var selection: [CodexPage: String] = [:]
    var searches: [CodexPage: String] = [:]

    func threadSelection(in threads: [CodexThread], projects: [CodexProject]) -> CodexThreadSelection {
        guard page == .active || page == .history else {
            return CodexThreadSelection(threads: [], selectedIndex: nil, project: nil)
        }
        let project = page == .history && groupsByProject ? selectedProject(in: projects) : nil
        let query = (searches[page] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let visible = threads.filter { thread in
            (page != .active || thread.isActive || retainedActiveThreadIDs.contains(thread.id))
                && (project == nil || (thread.project?.id ?? "") == project?.id)
                && (query.isEmpty || thread.title.localizedStandardContains(query) || thread.preview.localizedStandardContains(query))
        }
        let index = visible.firstIndex { $0.id == selection[page] } ?? (visible.isEmpty ? nil : 0)
        return CodexThreadSelection(threads: visible, selectedIndex: index, project: project)
    }

    func selectedProject(in projects: [CodexProject]) -> CodexProject? {
        let id = page == .newThread ? newThread.projectID : projectID
        let available = page == .newThread ? projects.filter { !$0.roots.isEmpty } : projects
        return available.first { $0.id == id } ?? available.first
    }

    func selectProject(_ project: CodexProject) {
        if page == .newThread {
            guard newThread.thread == nil, !newThread.isSubmitting else { return }
            newThread.projectID = project.id
            return
        }
        projectID = project.id
        groupsByProject = true
        page = .history
        if presentation != .projects { presentation = .deck }
    }

    func moveProject(_ offset: Int, in projects: [CodexProject]) {
        guard let current = selectedProject(in: projects) else { return }
        let id = cyclingPage(in: projects.map(\.id), to: current.id, offset: offset)
        if let next = projects.first(where: { $0.id == id }) { selectProject(next) }
    }

    func openProjects() {
        if page == .newThread, newThread.isSubmitting || newThread.thread != nil { return }
        if page != .newThread {
            page = .history
            groupsByProject = true
        }
        presentation = .projects
    }
}

struct CodexThreadSelection {
    let threads: [CodexThread]
    let selectedIndex: Int?
    let project: CodexProject?

    var selectedThread: CodexThread? { selectedIndex.map { threads[$0] } }
}
