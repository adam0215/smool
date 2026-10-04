@testable import SmoolChecksSupport
import Foundation

@main
struct CodexNavigationChecks {
    @MainActor static func main() {
        let state = CodexAppletState()
        state.page = .history
        state.groupsByProject = true
        let projects = (0..<100).map { CodexProject(id: "project-\($0)", name: "Project \($0)", roots: ["/tmp/project-\($0)"]) }
        let threads = (0..<5_000).map { index in
            var thread = CodexThread(json: .object([
                "id": .string("thread-\(index)"), "title": .string("Thread \(index)"),
                "preview": .string(index == 100 ? "Needle" : ""),
                "cwd": .string("/tmp/project-\(index % 100)")
            ]))!
            thread.project = projects[index % 100]
            return thread
        }
        state.projectID = "project-0"
        state.selection[.history] = "thread-100"
        let selected = state.threadSelection(in: threads, projects: projects)
        precondition(selected.threads.count == 50 && selected.selectedIndex == 1)
        precondition(selected.selectedThread?.id == "thread-100")
        state.searches[.history] = "needle"
        precondition(state.threadSelection(in: threads, projects: projects).threads.map(\.id) == ["thread-100"])
        state.searches[.history] = "nothing matches"
        precondition(state.threadSelection(in: threads, projects: projects).selectedThread == nil)
        state.searches[.history] = ""
        state.projectID = "removed-project"
        precondition(state.threadSelection(in: threads, projects: projects).project?.id == "project-0")
        state.moveProject(1, in: projects)
        precondition(state.projectID == "project-1")
        state.moveProject(-1, in: projects)
        precondition(state.projectID == "project-0")
        state.groupsByProject = false
        precondition(state.threadSelection(in: threads, projects: projects).threads.count == threads.count)
        state.groupsByProject = true

        let empty = CodexProject(id: "empty", name: "Empty", roots: [])
        state.selectProject(empty)
        precondition(state.threadSelection(in: threads, projects: projects + [empty]).threads.isEmpty)
        state.selectProject(projects[0])
        state.openProjects()
        precondition(state.presentation == .projects && state.page == .history && state.groupsByProject)

        // A broad budget catches the former per-row full-catalog sort even on slower machines.
        let elapsed = ContinuousClock().measure {
            for _ in 0..<20 {
                precondition(state.threadSelection(in: threads, projects: projects).threads.count == 50)
            }
        }
        precondition(elapsed < .seconds(5), "Grouped selection must stay responsive with thousands of threads: \(elapsed)")
        print("Passed: grouped selection, search, stale selections, project navigation; 20 selections of 5,000 threads in \(elapsed).")
    }
}
