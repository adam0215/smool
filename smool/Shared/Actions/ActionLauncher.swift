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

    func perform(_ action: SavedAction) async throws {
        try action.destination.validate()
        switch action.destination {
        case .application(_, let data), .folder(_, let data):
            var stale = false
            let url: URL
            do {
                url = try URL(resolvingBookmarkData: data, options: [.withoutUI, .withoutMounting], relativeTo: nil, bookmarkDataIsStale: &stale)
                try ActionDestination.validateLocal(url, kind: action.destination.kind)
            } catch {
                throw ActionFailure(message: "Resursen kunde inte hittas. Välj appen eller mappen igen via Redigera.")
            }
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            try await openURL(url)
        case .website(let url), .codexThread(let url): try await openURL(url)
        case .shortcut(let id, _): try await runShortcut(id)
        }
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
                throw ActionFailure(message: "Kunde inte läsa listan från Genvägar.")
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
                throw ActionFailure(message: "Genvägar kunde inte slutföra åtgärden. Öppna appen Genvägar och kontrollera att genvägen finns och har behörighet.")
            }
            return String(decoding: data, as: UTF8.self)
        }.value
    }
}
