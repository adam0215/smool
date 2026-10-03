import Foundation

struct ShelfFile: Identifiable, Codable, Sendable {
    let id: UUID
    var bookmark: Data
    var name: String
    var lastKnownURL: URL
}

struct ResolvedShelfFile: Identifiable, Sendable {
    let reference: ShelfFile
    let url: URL?
    var isDirectory = false
    var id: UUID { reference.id }
}

struct FileShelfSnapshot: Sendable {
    let files: [ResolvedShelfFile]
    var message: String?
}

/// All bookmark resolution and disk work happens away from the main actor.
actor FileShelfRepository {
    static let capacity = 40
    private let storageURL: URL
    private var files: [ShelfFile] = []
    private var loaded = false

    init(storageURL: URL) { self.storageURL = storageURL }

    func refresh() throws -> FileShelfSnapshot {
        try load()
        let previous = files
        let resolved = files.map(resolve)
        files = resolved.map(\.reference)
        if files != previous { try save() }
        return FileShelfSnapshot(files: resolved)
    }

    func add(urls: [URL]) throws -> FileShelfSnapshot {
        try load()
        var updated = try refresh().files.map(\.reference)
        var messages: [String] = []
        for url in urls {
            guard url.isFileURL else { continue }
            let url = url.standardizedFileURL
            guard !updated.contains(where: { $0.lastKnownURL.resolvingSymlinksInPath() == url.resolvingSymlinksInPath() }) else { continue }
            guard updated.count < Self.capacity else {
                messages.append("Hyllan rymmer \(Self.capacity) filer. Ta bort en referens för att lägga till fler.")
                break
            }
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            do {
                guard try url.checkResourceIsReachable() else { throw CocoaError(.fileReadNoSuchFile) }
                let bookmark = try Self.bookmark(for: url)
                updated.insert(ShelfFile(id: UUID(), bookmark: bookmark, name: url.lastPathComponent, lastKnownURL: url), at: 0)
            } catch {
                messages.append("\(url.lastPathComponent) kunde inte läggas till. Välj filen igen.")
            }
        }
        // Keep the order of each incoming batch while placing it before older files.
        let newIDs = Set(updated.map(\.id)).subtracting(files.map(\.id))
        updated = updated.filter { newIDs.contains($0.id) }.reversed() + updated.filter { !newIDs.contains($0.id) }
        try save(updated)
        files = updated
        var snapshot = try refresh()
        snapshot.message = messages.isEmpty ? nil : messages.joined(separator: "\n")
        return snapshot
    }

    func remove(id: UUID) throws -> FileShelfSnapshot {
        try load()
        let updated = files.filter { $0.id != id }
        try save(updated)
        files = updated
        return try refresh()
    }

    private func load() throws {
        guard !loaded else { return }
        do {
            files = try JSONDecoder().decode([ShelfFile].self, from: Data(contentsOf: storageURL))
        } catch CocoaError.fileReadNoSuchFile {
            files = []
        }
        // A malformed existing file must never be overwritten by an empty shelf.
        loaded = true
    }

    private func save(_ updated: [ShelfFile]? = nil) throws {
        try FileManager.default.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(updated ?? files).write(to: storageURL, options: .atomic)
    }

    private static func bookmark(for url: URL) throws -> Data {
        do {
            return try url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess], includingResourceValuesForKeys: nil, relativeTo: nil)
        } catch {
            // Non-sandboxed builds can use ordinary persistent bookmarks.
            return try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        }
    }

    private func resolve(_ reference: ShelfFile) -> ResolvedShelfFile {
        var reference = reference
        var stale = false
        let url = (try? URL(resolvingBookmarkData: reference.bookmark, options: [.withSecurityScope, .withoutUI, .withoutMounting], relativeTo: nil, bookmarkDataIsStale: &stale))
            ?? (try? URL(resolvingBookmarkData: reference.bookmark, options: [.withoutUI, .withoutMounting], relativeTo: nil, bookmarkDataIsStale: &stale))
        guard let url else { return ResolvedShelfFile(reference: reference, url: nil) }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        guard (try? url.checkResourceIsReachable()) == true else {
            return ResolvedShelfFile(reference: reference, url: nil)
        }
        reference.name = url.lastPathComponent
        reference.lastKnownURL = url
        if stale, let bookmark = try? Self.bookmark(for: url) { reference.bookmark = bookmark }
        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        return ResolvedShelfFile(reference: reference, url: url, isDirectory: isDirectory)
    }
}

extension ShelfFile: Equatable {}
