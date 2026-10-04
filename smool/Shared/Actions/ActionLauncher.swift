import AppKit

@MainActor
struct ActionLauncher {
    var openURL: (URL) async throws -> Void
    var runShortcut: (UUID) async throws -> Void

    static var live: Self {
        Self(openURL: { url in
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            _ = try await NSWorkspace.shared.open(url, configuration: configuration)
        }, runShortcut: { id in
            _ = try await ShortcutCatalog.command(["run", id.uuidString])
        })
    }

    @discardableResult
    func perform(_ action: SavedAction) async throws -> ActionDestination {
        try action.destination.validate()
        switch action.destination {
        case .application, .folder:
            let resolved = try action.destination.resolvedLocal()
            let accessing = resolved.url.startAccessingSecurityScopedResource()
            defer { if accessing { resolved.url.stopAccessingSecurityScopedResource() } }
            try await openURL(resolved.url)
            return resolved.destination
        case .website(let url), .codexThread(let url): try await openURL(url)
        case .shortcut(let id, _): try await runShortcut(id)
        }
        return action.destination
    }
}

struct AvailableShortcut: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
}

enum ShortcutCatalog {
    static func load() async throws -> [AvailableShortcut] {
        let output = try await command(["list", "--show-identifiers"], captureOutput: true, timeout: 15)
        return try parse(output)
    }

    static func parse(_ output: String) throws -> [AvailableShortcut] {
        try output.split(whereSeparator: \.isNewline).map { line in
            guard let start = line.range(of: " (", options: .backwards), line.last == ")",
                  let id = UUID(uuidString: String(line[start.upperBound..<line.index(before: line.endIndex)])) else {
                throw ActionFailure(message: "Could not read the list from Shortcuts.")
            }
            return AvailableShortcut(id: id, name: String(line[..<start.lowerBound]))
        }
    }

    static func command(_ arguments: [String], captureOutput: Bool = false, timeout: TimeInterval? = nil) async throws -> String {
        try await Task.detached {
            let process = Process()
            let output = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
            process.arguments = arguments
            process.standardOutput = captureOutput ? output : FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.standardInput = FileHandle.nullDevice
            try process.run()
            if let timeout {
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                    if process.isRunning { process.terminate() }
                }
            }
            let data = captureOutput ? output.fileHandleForReading.readDataToEndOfFile() : Data()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                throw ActionFailure(message: "Shortcuts could not complete the action. Open Shortcuts and check that the shortcut exists and has permission.")
            }
            return String(decoding: data, as: UTF8.self)
        }.value
    }
}
