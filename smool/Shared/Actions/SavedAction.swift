import Foundation

struct ActionFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

enum ActionKind: String, Codable, CaseIterable, Identifiable {
    case application, folder, website, codexThread, shortcut

    var id: Self { self }
    var title: String {
        switch self {
        case .application: "App"
        case .folder: "Folder"
        case .website: "Web link"
        case .codexThread: "Codex thread"
        case .shortcut: "Apple Shortcut"
        }
    }
    var symbol: String {
        switch self {
        case .application: "app"
        case .folder: "folder"
        case .website: "globe"
        case .codexThread: "bubble.left.and.bubble.right"
        case .shortcut: "square.stack.3d.up"
        }
    }
}

struct SavedAction: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var name: String
    var destination: ActionDestination
}

enum ActionDestination: Codable, Equatable, Sendable {
    case application(URL, bookmark: Data)
    case folder(URL, bookmark: Data)
    case website(URL)
    case codexThread(URL)
    case shortcut(id: UUID, name: String)

    var kind: ActionKind {
        switch self {
        case .application: .application
        case .folder: .folder
        case .website: .website
        case .codexThread: .codexThread
        case .shortcut: .shortcut
        }
    }

    var detail: String {
        switch self {
        case .application(let url, _), .folder(let url, _): url.path
        case .website(let url), .codexThread(let url): url.absoluteString
        case .shortcut(_, let name): name
        }
    }

    static func web(_ input: String) throws -> Self {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.contains(where: { $0.isWhitespace || $0.isNewline }),
              let parts = URLComponents(string: text),
              ["http", "https"].contains(parts.scheme?.lowercased() ?? ""),
              let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil,
              let url = parts.url else {
            throw ActionFailure(message: "Enter a complete http or https address without login credentials.")
        }
        return .website(url)
    }

    static func thread(_ input: String) throws -> Self {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let id = UUID(uuidString: text) {
            return .codexThread(URL(string: "codex://threads/\(id.uuidString.lowercased())")!)
        }
        guard let parts = URLComponents(string: text), parts.scheme == "codex", parts.host == "threads",
              parts.user == nil, parts.password == nil, parts.port == nil,
              parts.query == nil, parts.fragment == nil,
              parts.path.first == "/", UUID(uuidString: String(parts.path.dropFirst())) != nil,
              let url = parts.url else {
            throw ActionFailure(message: "Enter a thread ID or a codex://threads/ link.")
        }
        return .codexThread(url)
    }

    static func local(_ url: URL, kind: ActionKind) throws -> Self {
        try validateLocal(url, kind: kind)
        let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        return kind == .application ? .application(url, bookmark: bookmark) : .folder(url, bookmark: bookmark)
    }

    static func validateLocal(_ url: URL, kind: ActionKind) throws {
        guard url.isFileURL, kind == .application || kind == .folder else {
            throw ActionFailure(message: "Choose a local app or folder.")
        }
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isApplicationKey])
        guard values.isDirectory == true,
              kind == .application ? values.isApplication == true : values.isApplication != true else {
            throw ActionFailure(message: kind == .application ? "Choose an app." : "Choose a folder, not an app.")
        }
    }

    func validate() throws {
        switch self {
        case .website(let url): _ = try Self.web(url.absoluteString)
        case .codexThread(let url): _ = try Self.thread(url.absoluteString)
        case .application(let url, let data), .folder(let url, let data):
            guard url.isFileURL, !data.isEmpty else { throw ActionFailure(message: "Choose the app or folder again.") }
        case .shortcut(_, let name):
            guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ActionFailure(message: "Choose a shortcut.")
            }
        }
    }
}

struct ActionFile<Value: Codable> {
    let url: URL

    static func location(_ name: String) -> URL {
        URL.applicationSupportDirectory.appendingPathComponent("smool", isDirectory: true).appendingPathComponent(name)
    }

    func load(default fallback: Value) throws -> Value {
        guard FileManager.default.fileExists(atPath: url.path) else { return fallback }
        return try JSONDecoder().decode(Value.self, from: Data(contentsOf: url))
    }

    func save(_ value: Value) throws {
        let data = try JSONEncoder().encode(value)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}

func validateActions(_ actions: [SavedAction], allowShortcuts: Bool) throws {
    guard Set(actions.map(\.id)).count == actions.count else {
        throw ActionFailure(message: "The list contains duplicate IDs.")
    }
    for action in actions {
        guard !action.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ActionFailure(message: "Give the resource a name.")
        }
        guard allowShortcuts || action.destination.kind != .shortcut else {
            throw ActionFailure(message: "Add shortcuts in Quick Actions.")
        }
        try action.destination.validate()
    }
}
