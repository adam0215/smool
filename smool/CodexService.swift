import AppKit
import Foundation
import Observation

struct CodexThread: Identifiable, Equatable {
    let id: String
    var title: String
    var preview: String
    var updatedAt: Date
    var status: String?
    var isConnected = false
    var isArchived = false
    var isActive: Bool { isConnected && status == "active" }

    init?(json: CodexJSON) {
        guard let id = json["id"].string else { return nil }
        self.id = id
        preview = json["preview"].string ?? ""
        let name = json["name"].string ?? json["title"].string ?? ""
        title = name.isEmpty ? String(preview.prefix(100)) : name
        if title.isEmpty { title = "Namnlös tråd" }
        let timestamp = json["updatedAt"].number ?? 0
        updatedAt = Date(timeIntervalSince1970: timestamp > 100_000_000_000 ? timestamp / 1_000 : timestamp)
    }
}

struct CodexLimit: Identifiable {
    let id: String
    let title: String
    let usedPercent: Double
    let resetAt: Date?
    let durationMinutes: Int?

    static func parse(_ response: CodexJSON) -> [CodexLimit] {
        let buckets = response["rateLimitsByLimitId"].object
        let values = buckets.isEmpty ? [("codex", response["rateLimits"])] : buckets.sorted { $0.key < $1.key }
        return values.flatMap { key, snapshot in
            ["primary", "secondary"].compactMap { window -> CodexLimit? in
                let data = snapshot[window]
                guard let used = data["usedPercent"].number else { return nil }
                let minutes = data["windowDurationMins"].number.map(Int.init)
                let period: String
                if let minutes, minutes >= 1_440 { period = "\(minutes / 1_440) dagar" }
                else if let minutes, minutes >= 60 { period = "\(minutes / 60) timmar" }
                else if let minutes { period = "\(minutes) minuter" }
                else { period = window == "primary" ? "Aktuell period" : "Längre period" }
                let name = snapshot["limitName"].string ?? key
                return CodexLimit(id: "\(key).\(window)", title: "\(name) · \(period)", usedPercent: min(100, max(0, used)),
                                  resetAt: data["resetsAt"].number.map(Date.init(timeIntervalSince1970:)), durationMinutes: minutes)
            }
        }
    }
}

@MainActor @Observable
final class CodexService {
    static let shared = CodexService()
    private(set) var threads: [CodexThread] = []
    private(set) var limits: [CodexLimit] = []
    private(set) var isLoading = false
    private(set) var isSending = false
    private(set) var isConnectingThreadID: String?
    private(set) var error: String?
    private(set) var liveError: String?
    var drafts: [String: String] = [:]
    var includesArchived = false
    var selectedThreadID: String?

    @ObservationIgnored private let catalog = CodexClient(desktop: false)
    @ObservationIgnored private let desktop = CodexClient(desktop: true)
    @ObservationIgnored private var followed: Set<String> = []
    @ObservationIgnored private var revisions: [String: Int] = [:]
    @ObservationIgnored private var owners: [String: String] = [:]
    @ObservationIgnored private var session = UUID()
    @ObservationIgnored private var refreshing = false

    init() {
        desktop.onMessage = { [weak self] in self?.receive($0) }
        desktop.onDisconnect = { [weak self] in self?.lostLiveConnection() }
    }

    func start() async {
        let session = UUID()
        self.session = session
        while refreshing {
            do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
        }
        repeat {
            await refresh()
            do { try await Task.sleep(for: .seconds(30)) }
            catch { break }
        } while !Task.isCancelled && self.session == session
        if self.session == session { stop() }
    }

    func stop() {
        session = UUID()
        for id in followed { desktop.follow(id, following: false) }
        desktop.disconnect()
        catalog.disconnect()
        followed.removeAll()
        revisions.removeAll()
        owners.removeAll()
        for index in threads.indices { threads[index].isConnected = false; threads[index].status = nil }
    }

    func refresh() async {
        guard !refreshing else { return }
        let session = self.session
        refreshing = true
        isLoading = threads.isEmpty
        defer { refreshing = false; isLoading = false }
        do {
            let reconnecting = !desktop.isConnected
            try await desktop.connect()
            guard self.session == session else { return }
            if reconnecting { liveError = nil }
        } catch { if self.session == session { liveError = error.localizedDescription } }
        guard self.session == session, !Task.isCancelled else { return }
        do {
            try await catalog.connect()
            guard self.session == session, !Task.isCancelled else { return }
            var catalogIDs: Set<String> = []
            let archiveFilters = includesArchived ? [false, true] : [false]
            for archived in archiveFilters {
                var cursor: String?
                var seenCursors: Set<String> = []
                repeat {
                    var params: [String: CodexJSON] = [
                        "limit": .number(100), "sortKey": .string("updated_at"),
                        "useStateDbOnly": .bool(true), "archived": .bool(archived)
                    ]
                    if let cursor { params["cursor"] = .string(cursor) }
                    let result = try await catalog.request("thread/list", params: .object(params))
                    guard self.session == session, !Task.isCancelled else { return }
                    for value in result["data"].array {
                        guard var thread = CodexThread(json: value) else { continue }
                        thread.isArchived = archived
                        catalogIDs.insert(thread.id)
                        if let index = threads.firstIndex(where: { $0.id == thread.id }) {
                            thread.status = threads[index].status
                            thread.isConnected = threads[index].isConnected
                            threads[index] = thread
                        } else { threads.append(thread) }
                        follow(thread.id)
                    }
                    cursor = result["nextCursor"].string
                    if let cursor, !seenCursors.insert(cursor).inserted { break }
                    try Task.checkCancellation()
                } while cursor != nil
            }
            let removed = threads.filter { !catalogIDs.contains($0.id) && !$0.isConnected }.map(\.id)
            for id in removed { desktop.follow(id, following: false); followed.remove(id) }
            threads.removeAll { removed.contains($0.id) }
            threads.sort { $0.updatedAt > $1.updatedAt }
            let response = try await catalog.request("account/rateLimits/read", params: .object([:]))
            guard self.session == session, !Task.isCancelled else { return }
            limits = CodexLimit.parse(response)
            error = nil
        } catch is CancellationError { }
        catch { if self.session == session { self.error = error.localizedDescription; limits = [] } }
    }

    func setIncludesArchived(_ include: Bool) async {
        guard includesArchived != include else { return }
        includesArchived = include
        let session = self.session
        while refreshing {
            do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
        }
        guard self.session == session, !Task.isCancelled else { return }
        await refresh()
    }

    /// Opening a thread lets the desktop keep ownership, settings and approval handling.
    /// This explicit action only connects; sending always remains a separate user action.
    func ensureConnected(to thread: CodexThread) async -> Bool {
        guard isConnectingThreadID == nil else { return false }
        isConnectingThreadID = thread.id
        defer { isConnectingThreadID = nil }
        do {
            try? await desktop.connect()
            try Task.checkCancellation()
            if desktop.isConnected, let owner = try? await owner(of: thread.id) {
                return try await awaitSnapshot(threadID: thread.id, owner: owner)
            }
            guard let url = CodexDesktopProtocol.threadURL(thread.id),
                  let application = NSWorkspace.shared.urlForApplication(toOpen: url) else {
                throw CodexConnectionError(message: "Installera eller öppna Codex för att ansluta tråden.")
            }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            _ = try await NSWorkspace.shared.open([url], withApplicationAt: application, configuration: configuration)

            let deadline = ContinuousClock.now.advanced(by: .seconds(20))
            repeat {
                try Task.checkCancellation()
                try? await desktop.connect()
                try Task.checkCancellation()
                if desktop.isConnected, let owner = try? await owner(of: thread.id) {
                    return try await awaitSnapshot(threadID: thread.id, owner: owner)
                }
                try await Task.sleep(for: .milliseconds(500))
            } while ContinuousClock.now < deadline
            throw CodexConnectionError(message: "Codex hann inte ansluta tråden. Ditt utkast är kvar; försök ansluta igen.")
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    private func owner(of threadID: String) async throws -> String {
        let response = try await desktop.request("thread-owner-discovery", params: .object([
            "hostId": .string("local"), "conversationId": .string(threadID)
        ]))
        guard let owner = response["handledByClientId"].string else {
            throw CodexConnectionError(message: "Tråden har ännu inte anslutits i Codex.")
        }
        return owner
    }

    private func awaitSnapshot(threadID: String, owner: String) async throws -> Bool {
        try Task.checkCancellation()
        if owners[threadID] == owner, threads.contains(where: { $0.id == threadID && $0.isConnected }) {
            error = nil
            return true
        }
        resubscribe(threadID)
        followed.insert(threadID)
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        repeat {
            try Task.checkCancellation()
            if owners[threadID] == owner, threads.contains(where: { $0.id == threadID && $0.isConnected }) {
                error = nil
                return true
            }
            try await Task.sleep(for: .milliseconds(50))
        } while ContinuousClock.now < deadline
        throw CodexConnectionError(message: "Tråden är öppen i Codex, men dess status kunde inte bekräftas. Försök ansluta igen.")
    }

    func send(_ text: String, to thread: CodexThread) async -> Bool {
        guard !isSending, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard text.utf8.count <= 65_536 else { error = "Meddelandet är för långt. Skriv högst 64 kB text."; return false }
        isSending = true
        var submitted = false
        defer { isSending = false }
        do {
            try await desktop.connect()
            let owner = try await owner(of: thread.id)
            // Never resume independently: the existing owner retains settings, tools and approvals.
            submitted = true
            try await CodexDesktopProtocol.deliver(text: text, threadID: thread.id, messageID: UUID().uuidString, owner: owner) {
                try await desktop.request($0, params: $1, owner: $2)
            }
            error = nil
            follow(thread.id)
            return true
        } catch {
            // A timeout is ambiguous. Never retry a turn automatically: it may already have started.
            if submitted {
                self.error = "Kunde inte bekräfta skickandet. Kontrollera tråden i Codex innan du försöker igen. \(error.localizedDescription)"
            } else if error.localizedDescription == "no-client-found" {
                self.error = "Öppna tråden i Codex en gång för att ansluta den."
            } else { self.error = error.localizedDescription }
            return false
        }
    }

    private func follow(_ id: String) {
        guard !followed.contains(id), desktop.follow(id) else { return }
        followed.insert(id)
    }

    func receive(_ message: CodexJSON) {
        guard message["type"].string == "broadcast" else { return }
        let params = message["params"]
        let method = message["method"].string
        if method == "client-status-changed", params["status"].string == "disconnected", let client = params["clientId"].string {
            for id in owners.keys.filter({ owners[$0] == client }) { invalidate(id) }
            return
        }
        guard params["hostId"].string == "local", let id = params["conversationId"].string else { return }
        if method == "thread-stream-following-changed" { follow(id); return }
        guard method == "thread-stream-state-changed" else { return }
        guard message["version"].number == Double(CodexDesktopProtocol.snapshotVersion) else {
            liveError = "Codex har ändrat sitt lokala gränssnitt. Live-status är inte tillgänglig med den här versionen."
            invalidate(id)
            return
        }
        let change = params["change"]
        if change["type"].string == "snapshot" {
            let state = change["conversationState"]
            if threads.firstIndex(where: { $0.id == id }) == nil, let thread = CodexThread(json: state) { threads.append(thread) }
            guard let index = threads.firstIndex(where: { $0.id == id }) else { return }
            threads[index].status = state["threadRuntimeStatus"]["type"].string
            threads[index].isConnected = true
            if let title = state["title"].string, !title.isEmpty { threads[index].title = title }
            revisions[id] = change["revision"].number.map(Int.init)
            owners[id] = message["sourceClientId"].string
        } else if change["type"].string == "patches" {
            guard let index = threads.firstIndex(where: { $0.id == id }),
                  owners[id] == message["sourceClientId"].string,
                  revisions[id] == change["baseRevision"].number.map(Int.init) else {
                resubscribe(id)
                return
            }
            for patch in change["patches"].array {
                let path = patch["path"].array.compactMap(\.string)
                if path == ["threadRuntimeStatus"] { threads[index].status = patch["value"]["type"].string }
                else if path == ["threadRuntimeStatus", "type"] { threads[index].status = patch["value"].string }
                else if path == ["title"], let title = patch["value"].string { threads[index].title = title }
                else if path.isEmpty { resubscribe(id); return }
            }
            revisions[id] = change["revision"].number.map(Int.init)
        }
    }

    private func resubscribe(_ id: String) {
        invalidate(id)
        desktop.follow(id, following: false)
        desktop.follow(id)
    }

    private func invalidate(_ id: String) {
        owners[id] = nil
        revisions[id] = nil
        if let index = threads.firstIndex(where: { $0.id == id }) {
            threads[index].isConnected = false
            threads[index].status = nil
        }
    }

    private func lostLiveConnection() {
        followed.removeAll()
        revisions.removeAll()
        owners.removeAll()
        for index in threads.indices { threads[index].isConnected = false; threads[index].status = nil }
        liveError = "Anslutningen till Codex bröts. Försöker igen när vyn uppdateras."
    }
}
