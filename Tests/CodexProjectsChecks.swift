@testable import SmoolChecksSupport
import Foundation

@main
struct CodexProjectsChecks {
    static func main() throws {
        let data = Data(#"""
        {
          "local-projects": {
            "parent": {"name": "cdxcmd", "rootPaths": ["/Code/JS"]},
            "smool": {"name": "smool", "rootPaths": ["/Code/Swift/smool"]},
            "fina": {"name": "Fina", "rootPaths": ["/Code/JS/Fina", "/Other/Fina"]},
            "empty": {"name": "No threads yet", "rootPaths": ["/Code/Empty"]}
          },
          "project-order": ["smool", "fina", "parent", "empty"],
          "thread-project-assignments": {
            "worktree": {"projectKind": "local", "projectId": "smool"},
            "moved": {"projectKind": "local", "projectId": "fina"},
            "removed": {"projectKind": "local", "projectId": "gone"},
            "cloud": {"projectKind": "cloud", "projectId": "smool"}
          },
          "projectless-thread-ids": ["unassigned"],
          "thread-workspace-root-hints": {"hint": "/Code/Swift/smool"}
        }
        """#.utf8)
        let catalog = CodexProjects(json: try JSONDecoder().decode(CodexJSON.self, from: data))
        precondition(catalog.projects.map(\.name) == ["smool", "Fina", "cdxcmd", "No threads yet"])
        precondition(catalog.project(for: "worktree", cwd: "/tmp/worktrees/abc/smool")?.id == "smool")
        precondition(catalog.project(for: "moved", cwd: "/Code/Swift/smool")?.id == "fina")
        precondition(catalog.project(for: "hint", cwd: "/tmp/worktree")?.id == "smool")
        precondition(catalog.project(for: "nested", cwd: "/Code/JS/Fina/Sources")?.id == "fina")
        precondition(catalog.project(for: "second-root", cwd: "/Other/Fina")?.id == "fina")
        precondition(catalog.project(for: "boundary", cwd: "/Code/JS/Fina-other")?.id == "parent")
        for id in ["unassigned", "removed", "cloud"] {
            precondition(catalog.project(for: id, cwd: "/Code/Swift/smool") == nil)
        }
        precondition(catalog.project(for: "loose", cwd: "/tmp/anv") == nil)
        precondition(CodexProjects(json: .null).projects.isEmpty)
        print("Passed: saved project names/order, worktree memberships, nested roots, projectless threads and removed projects.")
    }
}
