import Foundation

@main
struct FileShelfStoreChecks {
    @MainActor static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "smool-shelf-store-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = root.appending(path: "first.txt")
        let second = root.appending(path: "second.txt")
        try Data().write(to: first)
        try Data().write(to: second)
        let storage = root.appending(path: "shelf.json")
        let store = FileShelfStore(storageURL: storage)
        store.refresh()
        store.add(urls: [first])
        store.add(urls: [second])
        await store.finishPendingChanges()
        precondition(store.files.map(\.reference.name) == ["second.txt", "first.txt"])
        precondition(!store.isLoading && store.error == nil)
        store.moveSelection(100)
        precondition(store.selectedFile?.reference.name == "first.txt")
        store.moveSelection(-100)
        precondition(store.selectedFile?.reference.name == "second.txt")
        store.remove(id: store.selectedFile!.id)
        store.refresh()
        await store.finishPendingChanges()
        precondition(store.selectedFile?.reference.name == "first.txt")
        precondition(FileManager.default.fileExists(atPath: second.path))
        let restored = FileShelfStore(storageURL: storage)
        restored.refresh()
        await restored.finishPendingChanges()
        precondition(restored.files.map(\.id) == store.files.map(\.id))

        let blockedPath = root.appending(path: "not-a-directory")
        try Data().write(to: blockedPath)
        let blocked = FileShelfStore(storageURL: blockedPath.appending(path: "shelf.json"))
        blocked.add(urls: [first])
        await blocked.finishPendingChanges()
        precondition(blocked.error != nil)
        precondition(blocked.files.isEmpty)
        precondition(FileManager.default.fileExists(atPath: first.path))
        print("File shelf queued writes, selection, restore and storage failure passed")
    }
}
