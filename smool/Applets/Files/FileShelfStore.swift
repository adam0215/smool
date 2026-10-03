import AppKit
import Observation
import UniformTypeIdentifiers

@MainActor @Observable
final class FileShelfStore {
    private(set) var files: [ResolvedShelfFile] = []
    private(set) var isLoading = false
    private(set) var error: String?
    var selection: UUID?

    @ObservationIgnored private let repository: FileShelfRepository
    @ObservationIgnored private var pending: Task<Void, Never>?
    @ObservationIgnored private var accessedURLs: [URL] = []
    @ObservationIgnored private var queuedOperations = 0
    @ObservationIgnored private var icons: [String: NSImage] = [:]

    init(storageURL: URL? = nil) {
        let url = storageURL ?? URL.applicationSupportDirectory
            .appending(path: "smool", directoryHint: .isDirectory)
            .appending(path: "file-shelf.json")
        repository = FileShelfRepository(storageURL: url)
    }

    var selectedFile: ResolvedShelfFile? { files.first { $0.id == selection } ?? files.first }

    func refresh() { enqueue { try await $0.refresh() } }
    func add(urls: [URL]) { enqueue { try await $0.add(urls: urls) } }
    func remove(id: UUID) { enqueue { try await $0.remove(id: id) } }
    func reportImportError(_ error: Error) {
        self.error = "Filen kunde inte väljas. \(error.localizedDescription)"
    }

    func finishPendingChanges() async { await pending?.value }

    func moveSelection(_ offset: Int) {
        guard !files.isEmpty else { return }
        let current = files.firstIndex { $0.id == selection } ?? 0
        selection = files[min(max(current + offset, 0), files.count - 1)].id
    }

    func icon(for file: ResolvedShelfFile) -> NSImage {
        let type = file.isDirectory ? UTType.folder : UTType(filenameExtension: file.reference.lastKnownURL.pathExtension) ?? .data
        if let icon = icons[type.identifier] { return icon }
        // A type icon does not read each file or trigger remote thumbnail downloads.
        let icon = NSWorkspace.shared.icon(for: type)
        icons[type.identifier] = icon
        return icon
    }

    private func enqueue(_ operation: @escaping @Sendable (FileShelfRepository) async throws -> FileShelfSnapshot) {
        let previous = pending
        queuedOperations += 1
        isLoading = true
        pending = Task {
            await previous?.value
            do {
                let snapshot = try await operation(repository)
                apply(snapshot)
            } catch {
                self.error = "Filhyllan kunde inte sparas eller läsas. Dina sparade referenser finns kvar. \(error.localizedDescription)"
            }
            queuedOperations -= 1
            isLoading = queuedOperations > 0
        }
    }

    private func apply(_ snapshot: FileShelfSnapshot) {
        let urls = Set(snapshot.files.compactMap(\.url))
        for url in accessedURLs where !urls.contains(url) { url.stopAccessingSecurityScopedResource() }
        accessedURLs.removeAll { !urls.contains($0) }
        for url in urls where !accessedURLs.contains(url) {
            if url.startAccessingSecurityScopedResource() { accessedURLs.append(url) }
        }
        files = snapshot.files
        error = snapshot.message
        if !files.contains(where: { $0.id == selection }) { selection = files.first?.id }
    }

    deinit {
        for url in accessedURLs { url.stopAccessingSecurityScopedResource() }
    }
}
