import Darwin
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

    var suggestedName: String {
        switch self {
        case .application(let url, _):
            let bundle = Bundle(url: url)
            return bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                ?? url.deletingPathExtension().lastPathComponent
        case .folder(let url, _):
            return url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
        case .website(let url):
            let host = url.host ?? url.absoluteString
            return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        case .codexThread(let url):
            return "Thread \(url.lastPathComponent.prefix(8))"
        case .shortcut(_, let name):
            return name
        }
    }

    static func inferred(_ input: String) throws -> Self {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw ActionFailure(message: "Enter an app name, folder path, website or Codex thread.")
        }
        if UUID(uuidString: text) != nil || text.lowercased().hasPrefix("codex:") {
            return try thread(text)
        }

        let localURL: URL?
        if text.lowercased().hasPrefix("file:") {
            guard let parts = URLComponents(string: text),
                  parts.host == nil || parts.host == "" || parts.host == "localhost",
                  parts.user == nil, parts.password == nil, parts.port == nil,
                  parts.query == nil, parts.fragment == nil,
                  parts.path.hasPrefix("/"), let url = parts.url else {
                throw ActionFailure(message: "Enter a local app or folder path.")
            }
            localURL = url
        } else if text.hasPrefix("/") || text.hasPrefix("~/") || text == "~" {
            localURL = URL(fileURLWithPath: (text as NSString).expandingTildeInPath)
        } else {
            localURL = installedApplication(named: text)
        }
        if let url = localURL {
            let values = try url.resourceValues(forKeys: [.isApplicationKey])
            return try local(url, kind: values.isApplication == true ? .application : .folder)
        }
        return try web(text)
    }

    private static func installedApplication(named input: String) -> URL? {
        guard !input.contains("/"), !input.contains(":") else { return nil }
        let name = input.lowercased().hasSuffix(".app") ? input : input + ".app"
        let directories = ["~/Applications", "/Applications", "/System/Applications",
                           "/Applications/Utilities", "/System/Applications/Utilities"]
        for directory in directories {
            let url = URL(fileURLWithPath: (directory as NSString).expandingTildeInPath)
            let contents = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
            if let match = contents?.first(where: { $0.lastPathComponent.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
                return match
            }
        }
        return nil
    }

    static func web(_ input: String) throws -> Self {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasScheme = text.range(of: "^[a-zA-Z][a-zA-Z0-9+.-]*:", options: .regularExpression) != nil
        let hasPort = text.range(of: "^[^/:?#]+:[0-9]+(?:[/?#]|$)", options: .regularExpression) != nil
        let address = hasScheme && !hasPort ? text : "https://" + text
        guard !text.contains(where: { $0.isWhitespace || $0.isNewline || $0 == "\\" }),
              text.range(of: "%(?![0-9a-fA-F]{2})", options: .regularExpression) == nil,
              var parts = URLComponents(string: address),
              ["http", "https"].contains(parts.scheme?.lowercased() ?? ""),
              let host = parts.host, validWebHost(host, requiresDomain: !hasScheme || hasPort),
              parts.user == nil, parts.password == nil,
              parts.port.map({ (1...65535).contains($0) }) ?? true,
              parts.url != nil else {
            throw ActionFailure(message: "Enter a website address, such as example.com, without login credentials.")
        }
        parts.scheme = parts.scheme?.lowercased()
        parts.host = host.lowercased()
        return .website(parts.url!)
    }

    private static func validWebHost(_ host: String, requiresDomain: Bool) -> Bool {
        if host.lowercased() == "localhost" { return true }
        if host.hasPrefix("["), host.hasSuffix("]") {
            var address = in6_addr()
            return inet_pton(AF_INET6, String(host.dropFirst().dropLast()), &address) == 1
        }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        return (!requiresDomain || labels.count > 1) && labels.allSatisfy { label in
            !label.isEmpty && label.first != "-" && label.last != "-"
                && label.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }
        }
    }

    static func thread(_ input: String) throws -> Self {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let id = UUID(uuidString: text) {
            return .codexThread(URL(string: "codex://threads/\(id.uuidString.lowercased())")!)
        }
        guard let parts = URLComponents(string: text), parts.scheme?.lowercased() == "codex", parts.host?.lowercased() == "threads",
              parts.user == nil, parts.password == nil, parts.port == nil,
              parts.query == nil, parts.fragment == nil,
              parts.path.first == "/",
              let id = UUID(uuidString: String(parts.path.dropFirst())) else {
            throw ActionFailure(message: "Enter a thread ID or a codex://threads/ link.")
        }
        return .codexThread(URL(string: "codex://threads/\(id.uuidString.lowercased())")!)
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
