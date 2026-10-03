import AppKit
import Observation
import UniformTypeIdentifiers

@MainActor @Observable
final class FileShelfStore {
    private(set) var files: [ResolvedShelfFile] = []
    private(set) var isLoading = false
    private(set) var error: String?
    private(set) var selection: UUID?
    private(set) var selectedIDs: Set<UUID> = []
    private var selectionAnchor: UUID?

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

    var selectedFile: ResolvedShelfFile? { files.first { $0.id == selection } }
    var selectedURLs: [URL] { files.filter { selectedIDs.contains($0.id) }.compactMap(\.url) }

    func select(_ id: UUID, extending: Bool = false, toggling: Bool = false) {
        guard let index = files.firstIndex(where: { $0.id == id }) else { return }
        if extending, let anchor = selectionAnchor,
           let anchorIndex = files.firstIndex(where: { $0.id == anchor }) {
            let range = Set(files[min(index, anchorIndex)...max(index, anchorIndex)].map(\.id))
            selectedIDs = toggling ? selectedIDs.union(range) : range
            selection = id
        } else if toggling {
            if selectedIDs.remove(id) == nil {
                selectedIDs.insert(id)
                selection = id
            } else if selection == id {
                selection = files.first { selectedIDs.contains($0.id) }?.id
            }
            selectionAnchor = id
        } else {
            selectedIDs = [id]
            selection = id
            selectionAnchor = id
        }
    }

    func selectAll() {
        selectedIDs = Set(files.map(\.id))
        selection = selection ?? files.first?.id
        selectionAnchor = selection
    }

    func removeSelected() {
        let ids = files.filter { selectedIDs.contains($0.id) }.map(\.id)
        for id in ids { remove(id: id) }
    }

    func refresh() { enqueue { try await $0.refresh() } }
    func add(urls: [URL]) { enqueue { try await $0.add(urls: urls) } }
    func remove(id: UUID) { enqueue { try await $0.remove(id: id) } }
    func reportImportError(_ error: Error) {
        self.error = "The file could not be selected. \(error.localizedDescription)"
    }

    func finishPendingChanges() async { await pending?.value }

    func moveSelection(_ offset: Int, extending: Bool = false) {
        guard !files.isEmpty else { return }
        let current = files.firstIndex { $0.id == selection } ?? 0
        select(files[min(max(current + offset, 0), files.count - 1)].id, extending: extending)
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
                self.error = "The file shelf could not be saved or loaded. Your saved references are kept. \(error.localizedDescription)"
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
        let availableIDs = Set(files.map(\.id))
        let hadSelection = !selectedIDs.isEmpty
        selectedIDs.formIntersection(availableIDs)
        if let selection, !selectedIDs.contains(selection) { self.selection = nil }
        if selectedIDs.isEmpty, hadSelection || selectionAnchor == nil, let first = files.first {
            select(first.id)
        } else if selection == nil {
            selection = files.first { selectedIDs.contains($0.id) }?.id
        }
        if let selectionAnchor, !availableIDs.contains(selectionAnchor) {
            self.selectionAnchor = selection
        }
    }

    deinit {
        for url in accessedURLs { url.stopAccessingSecurityScopedResource() }
    }
}
