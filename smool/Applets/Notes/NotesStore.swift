import Foundation
import Observation

struct QuickNote: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let createdAt: Date
    var updatedAt: Date
    var text: String

    var title: String {
        let line = text.split(whereSeparator: \.isNewline).first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return line.map { String($0.trimmingCharacters(in: .whitespaces).prefix(60)) } ?? "Ny anteckning"
    }
}

private struct NotesDocument: Codable, Sendable {
    var version = 1
    var notes: [QuickNote] = []
    var selectedID: UUID?
}

/// Serializes writes so a pending autosave cannot overwrite a later flush.
private final class NotesDisk: @unchecked Sendable {
    let url: URL
    private let queue = DispatchQueue(label: "smool.notes.persistence", qos: .utility)

    init(url: URL) { self.url = url }

    func load() throws -> NotesDocument {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch CocoaError.fileReadNoSuchFile {
            return NotesDocument()
        }
        let document = try JSONDecoder().decode(NotesDocument.self, from: data)
        guard document.version == 1, Set(document.notes.map(\.id)).count == document.notes.count else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return document
    }

    func save(_ document: NotesDocument, completion: @escaping @Sendable (Result<Void, Error>) -> Void) {
        queue.async { completion(self.write(document)) }
    }

    func flush(_ document: NotesDocument) -> Result<Void, Error> {
        queue.sync { write(document) }
    }

    private func write(_ document: NotesDocument) -> Result<Void, Error> {
        Result {
            let data = try JSONEncoder().encode(document)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        }
    }
}

@MainActor @Observable
final class NotesStore {
    private(set) var notes: [QuickNote] = []
    private(set) var selectedID: UUID?
    private(set) var errorMessage: String?
    private(set) var isReadOnly = false
    private(set) var hasUnsavedChanges = false

    @ObservationIgnored private let disk: NotesDisk
    @ObservationIgnored private let debounce: Duration
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var revision = 0

    var selectedNote: QuickNote? { notes.first { $0.id == selectedID } }

    init(fileURL: URL? = nil, debounce: Duration = .milliseconds(500)) {
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        disk = NotesDisk(url: fileURL ?? applicationSupport.appending(path: "smool/notes.json"))
        self.debounce = debounce
        reload()
    }

    func reload() {
        guard !hasUnsavedChanges else { flush(); return }
        do {
            let document = try disk.load()
            notes = document.notes
            selectedID = notes.contains { $0.id == document.selectedID } ? document.selectedID : notes.first?.id
            errorMessage = nil
            isReadOnly = false
        } catch {
            isReadOnly = true
            errorMessage = "Anteckningarna kunde inte läsas. Den sparade filen har inte ändrats. \(error.localizedDescription)"
        }
    }

    @discardableResult
    func createNote(text: String = "") -> UUID? {
        guard !isReadOnly else { return nil }
        let now = Date()
        let note = QuickNote(id: UUID(), createdAt: now, updatedAt: now, text: text)
        notes.insert(note, at: 0)
        selectedID = note.id
        changed()
        return note.id
    }

    func select(_ id: UUID) {
        guard !isReadOnly, notes.contains(where: { $0.id == id }), selectedID != id else { return }
        selectedID = id
        changed()
    }

    func update(_ id: UUID, text: String) {
        guard !isReadOnly, let index = notes.firstIndex(where: { $0.id == id }), notes[index].text != text else { return }
        notes[index].text = text
        notes[index].updatedAt = Date()
        changed()
    }

    /// The caller confirms deletion before calling this method.
    func delete(_ id: UUID) {
        guard !isReadOnly, let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes.remove(at: index)
        if selectedID == id {
            selectedID = notes.isEmpty ? nil : notes[min(index, notes.count - 1)].id
        }
        changed()
        flush()
    }

    func flush() {
        saveTask?.cancel()
        saveTask = nil
        guard hasUnsavedChanges, !isReadOnly else { return }
        revision += 1
        didSave(disk.flush(document), revision: revision)
    }

    private var document: NotesDocument { NotesDocument(notes: notes, selectedID: selectedID) }

    private func changed() {
        hasUnsavedChanges = true
        revision += 1
        saveTask?.cancel()
        saveTask = Task { [weak self, debounce] in
            do { try await Task.sleep(for: debounce) } catch { return }
            guard let self, !Task.isCancelled else { return }
            let savedRevision = revision
            disk.save(document) { [weak self] result in
                Task { @MainActor in self?.didSave(result, revision: savedRevision) }
            }
        }
    }

    private func didSave(_ result: Result<Void, Error>, revision savedRevision: Int) {
        guard savedRevision == revision else { return }
        switch result {
        case .success:
            hasUnsavedChanges = false
            errorMessage = nil
        case .failure(let error):
            errorMessage = "Kunde inte spara. Texten finns kvar här. \(error.localizedDescription)"
        }
    }
}
