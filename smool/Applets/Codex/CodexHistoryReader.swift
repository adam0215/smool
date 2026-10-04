import Foundation
import Observation

struct CodexHistoryPreview: Equatable {
    var message: CodexActivityItem?
    var isLoading = false
    var error: String?
    let updatedAt: Date
    var status: String?
    var isActive = false
}

/// Owns the cancellable newest-message read and its small preview cache.
@MainActor @Observable
final class CodexHistoryReader {
    private(set) var previews: [String: CodexHistoryPreview] = [:]
    @ObservationIgnored private let request: @MainActor (String, CodexJSON) async throws -> CodexJSON
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var token = UUID()
    @ObservationIgnored private var loadingID: String?
    @ObservationIgnored private var accessOrder: [String] = []

    init(request: @escaping @MainActor (String, CodexJSON) async throws -> CodexJSON) {
        self.request = request
    }

    /// Read a bounded newest-first slice without resuming or following the thread.
    func load(_ thread: CodexThread, force: Bool = false) async {
        accessOrder.removeAll { $0 == thread.id }
        accessOrder.append(thread.id)
        while accessOrder.count > 12 {
            previews[accessOrder.removeFirst()] = nil
        }
        if !force, let cached = previews[thread.id], !cached.isLoading,
           cached.updatedAt == thread.updatedAt, cached.status == thread.status, cached.isActive == thread.isActive {
            if loadingID != thread.id { cancel() }
            return
        }

        cancel()
        let requestToken = UUID()
        token = requestToken
        loadingID = thread.id
        previews[thread.id] = CodexHistoryPreview(isLoading: true, updatedAt: thread.updatedAt,
                                                   status: thread.status, isActive: thread.isActive)
        let requestTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if token == requestToken {
                    task = nil
                    loadingID = nil
                }
            }
            do {
                var cursor: String?
                var seenCursors: Set<String> = []
                var message: CodexActivityItem?
                var exhausted = false
                // Installed app-server schema: thread/items/list returns { turnId, item }
                // entries. Metadata thread.preview is the opening prompt, not the latest reply.
                for _ in 0..<4 {
                    try Task.checkCancellation()
                    var params: [String: CodexJSON] = [
                        "threadId": .string(thread.id), "limit": .number(50), "sortDirection": .string("desc")
                    ]
                    if let cursor { params["cursor"] = .string(cursor) }
                    let response = try await request("thread/items/list", .object(params))
                    try Task.checkCancellation()
                    guard token == requestToken else { return }
                    let page = try CodexListPage(response, limit: 50)
                    guard page.entries.allSatisfy({
                        $0["turnId"].string?.isEmpty == false && $0["item"]["type"].string?.isEmpty == false
                    }) else {
                        throw CodexConnectionError(message: "Codex returned an unsupported history item.")
                    }
                    for entry in page.entries {
                        let item = entry["item"]
                        let id = "turn:\(entry["turnId"].string ?? "unknown")/\(item["id"].string ?? "message")"
                        if let latest = CodexActivityPresentation.message(item, id: id) {
                            message = latest
                            break
                        }
                    }
                    if message != nil { break }
                    cursor = page.nextCursor
                    if cursor == nil { exhausted = true; break }
                    if let cursor, !seenCursors.insert(cursor).inserted { break }
                }
                previews[thread.id] = CodexHistoryPreview(
                    message: message,
                    error: message == nil && !exhausted ? "No recent message found in the preview window. Open the thread in Codex." : nil,
                    updatedAt: thread.updatedAt, status: thread.status, isActive: thread.isActive
                )
            } catch {
                guard token == requestToken else { return }
                if Task.isCancelled || error is CancellationError {
                    previews[thread.id] = nil
                } else {
                    previews[thread.id] = CodexHistoryPreview(error: error.localizedDescription, updatedAt: thread.updatedAt,
                                                               status: thread.status, isActive: thread.isActive)
                }
            }
        }
        task = requestTask
        await withTaskCancellationHandler {
            await requestTask.value
        } onCancel: { requestTask.cancel() }
    }

    func cancel() {
        token = UUID()
        task?.cancel()
        task = nil
        if let loadingID, previews[loadingID]?.isLoading == true {
            previews[loadingID] = nil
        }
        loadingID = nil
    }
}
