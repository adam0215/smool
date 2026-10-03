import Foundation

@main
struct FileShelfChecks {
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appending(path: "smool-file-tests-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = root.appending(path: "state/shelf.json")
        let first = root.appending(path: "first.txt")
        let second = root.appending(path: "second.txt")
        try Data("first".utf8).write(to: first)
        try Data("second".utf8).write(to: second)

        let repository = FileShelfRepository(storageURL: storage)
        let empty = try await repository.refresh()
        precondition(empty.files.isEmpty)
        let added = try await repository.add(urls: [first, second, first, URL(string: "https://example.com")!])
        precondition(added.files.map(\.reference.name) == ["first.txt", "second.txt"])
        precondition(added.files.allSatisfy { $0.url != nil && !$0.reference.bookmark.isEmpty })
        let firstID = added.files[0].id

        let restored = try await FileShelfRepository(storageURL: storage).refresh()
        precondition(restored.files.map(\.id) == added.files.map(\.id))
        precondition(restored.files.map { $0.url?.resolvingSymlinksInPath().path } == [first.resolvingSymlinksInPath().path, second.resolvingSymlinksInPath().path])

        let renamed = root.appending(path: "renamed.txt")
        try FileManager.default.moveItem(at: first, to: renamed)
        let moved = try await repository.refresh()
        precondition(moved.files[0].id == firstID)
        precondition(moved.files[0].url?.resolvingSymlinksInPath().path == renamed.resolvingSymlinksInPath().path)
        precondition(moved.files[0].reference.name == "renamed.txt")
        let duplicate = try await repository.add(urls: [renamed])
        precondition(duplicate.files.count == 2)

        try FileManager.default.removeItem(at: second)
        let missing = try await repository.refresh()
        precondition(missing.files[1].url == nil)
        precondition(missing.files[1].reference.name == "second.txt")
        let removed = try await repository.remove(id: firstID)
        precondition(removed.files.count == 1)
        let original = try String(contentsOf: renamed, encoding: .utf8)
        precondition(original == "first")

        let invalidStorage = root.appending(path: "broken.json")
        let invalidData = Data("not JSON".utf8)
        try invalidData.write(to: invalidStorage)
        do {
            _ = try await FileShelfRepository(storageURL: invalidStorage).add(urls: [renamed])
            preconditionFailure("Corrupt shelves must not be replaced")
        } catch {
            let preserved = try Data(contentsOf: invalidStorage)
            precondition(preserved == invalidData)
        }

        let invalid = try await repository.add(urls: [root.appending(path: "absent.txt")])
        precondition(invalid.files.count == 1 && invalid.message != nil)
        let folder = root.appending(path: "folder", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let withFolder = try await repository.add(urls: [folder])
        precondition(withFolder.files.first?.isDirectory == true)
        _ = try await repository.remove(id: withFolder.files[0].id)

        var many: [URL] = []
        for index in 0..<45 {
            let url = root.appending(path: "\(index).txt")
            try Data().write(to: url)
            many.append(url)
        }
        let limited = try await repository.add(urls: many)
        precondition(limited.files.count == FileShelfRepository.capacity)
        precondition(limited.message != nil)
        precondition(limited.files.last?.reference.name == "second.txt")
        precondition(limited.files.first?.reference.name == "0.txt")
        print("File shelf persistence, order, deduplication, moved/missing files, deletion, corruption and capacity passed")
    }
}
