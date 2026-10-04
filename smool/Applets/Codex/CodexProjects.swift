import Foundation

struct CodexProject: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let roots: [String]

    static let unassigned = CodexProject(id: "", name: "No project", roots: [])
}

/// The desktop stores sidebar names, order and explicit memberships separately from a thread's cwd.
struct CodexProjects: Sendable {
    let projects: [CodexProject]
    private let assignments: [String: CodexJSON]
    private let projectless: Set<String>
    private let rootHints: [String: CodexJSON]

    init(json: CodexJSON) {
        let saved = json["local-projects"].object.compactMap { id, value -> CodexProject? in
            guard let name = value["name"].string else { return nil }
            return CodexProject(id: id, name: name, roots: value["rootPaths"].array.compactMap(\.string))
        }
        let order = json["project-order"].array.compactMap(\.string)
        let ranks = Dictionary(order.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: min)
        projects = saved.sorted {
            let lhs = ranks[$0.id] ?? Int.max, rhs = ranks[$1.id] ?? Int.max
            return lhs == rhs ? $0.name.localizedStandardCompare($1.name) == .orderedAscending : lhs < rhs
        }
        assignments = json["thread-project-assignments"].object
        projectless = Set(json["projectless-thread-ids"].array.compactMap(\.string))
        rootHints = json["thread-workspace-root-hints"].object
    }

    func project(for threadID: String, cwd: String) -> CodexProject? {
        if projectless.contains(threadID) { return nil }
        if let assignment = assignments[threadID] {
            guard assignment["projectKind"].string == "local" else { return nil }
            return projects.first { $0.id == assignment["projectId"].string }
        }
        let path = rootHints[threadID]?.string ?? cwd
        // Match a saved root, preferring nested projects over their parent workspace.
        return projects.flatMap { project in project.roots.map { (project, $0) } }
            .filter { path == $0.1 || path.hasPrefix($0.1 + "/") }
            .max { $0.1.count < $1.1.count }?.0
    }

    static func read(from url: URL) async throws -> CodexProjects {
        try await Task.detached(priority: .utility) {
            let data = try Data(contentsOf: url)
            return CodexProjects(json: try JSONDecoder().decode(CodexJSON.self, from: data))
        }.value
    }
}
