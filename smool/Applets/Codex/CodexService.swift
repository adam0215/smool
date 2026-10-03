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
    var projectPath: String
    var project: CodexProject?
    var isActive: Bool { isConnected && status == "active" }

    init?(json: CodexJSON) {
        guard let id = json["id"].string else { return nil }
        self.id = id
        projectPath = json["cwd"].string ?? ""
        preview = json["preview"].string ?? ""
        let name = json["name"].string ?? json["title"].string ?? ""
        title = name.isEmpty ? String(preview.prefix(100)) : name
        if title.isEmpty { title = "Untitled thread" }
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

    var isCodexWeek: Bool {
        id.hasPrefix("codex.") && durationMinutes == 7 * 24 * 60
    }

    static func parse(_ response: CodexJSON) -> [CodexLimit] {
        let buckets = response["rateLimitsByLimitId"].object
        let values = buckets.isEmpty ? [("codex", response["rateLimits"])] : buckets.sorted { $0.key < $1.key }
        return values.flatMap { key, snapshot in
            ["primary", "secondary"].compactMap { window -> CodexLimit? in
                let data = snapshot[window]
                guard let used = data["usedPercent"].number else { return nil }
                let minutes = data["windowDurationMins"].number.map(Int.init)
                let period: String
                if let minutes, minutes >= 1_440 { period = "\(minutes / 1_440) days" }
                else if let minutes, minutes >= 60 { period = "\(minutes / 60) hours" }
                else if let minutes { period = "\(minutes) minutes" }
                else { period = window == "primary" ? "Current period" : "Longer period" }
                let name = snapshot["limitName"].string ?? key
                return CodexLimit(id: "\(key).\(window)", title: "\(name) · \(period)", usedPercent: min(100, max(0, used)),
                                  resetAt: data["resetsAt"].number.map(Date.init(timeIntervalSince1970:)), durationMinutes: minutes)
            }
        }
    }
}

@MainActor @Observable
final class CodexService {
    private(set) var threads: [CodexThread] = []
    // A display snapshot never supplies connection state for commands.
    private var cachedThreads: [CodexThread]?
    var displayedThreads: [CodexThread] { cachedThreads ?? threads }
    private(set) var projects: [CodexProject] = []
    private(set) var projectError: String?
    private(set) var limits: [CodexLimit] = []
    private(set) var isLoading = false
    private(set) var isSending = false
    private(set) var isConnectingThreadID: String?
    private(set) var error: String?
    private(set) var liveError: String?
    var drafts: [String: String] = [:]
    var includesArchived = false
    var selectedThreadID: String?
    private(set) var activities: [String: CodexActivityPresentation] = [:]
    private(set) var activityErrors: [String: String] = [:]
    private(set) var unreadThreadIDs: Set<String> = []
    private(set) var attentionByThread: [String: CodexAttention] = [:]
    private(set) var isVisible = false
    private(set) var monitorsStatus = false

    @ObservationIgnored private var unavailableActivityIDs: Set<String> = []
    @ObservationIgnored private var statusStreams: [String: CodexActivityStream] = [:]
    @ObservationIgnored private var streams: [String: CodexActivityStream] = [:]
    @ObservationIgnored private var streamAccess: [String] = []
    @ObservationIgnored private var dirtyStreams: Set<String> = []
    @ObservationIgnored private var publicationTask: Task<Void, Never>?
    @ObservationIgnored private var projectionTask: Task<[String: CodexActivityPresentation], Never>?
    @ObservationIgnored private var streamTokens: [String: UUID] = [:]
    @ObservationIgnored private var lifecycleTask: Task<Void, Never>?
    @ObservationIgnored private var retryDelay: Duration = .seconds(1)
    @ObservationIgnored private let projectActivity: @Sendable (CodexActivityStream) -> CodexActivityPresentation

    @ObservationIgnored private var projectCatalog = CodexProjects(json: .null)
    @ObservationIgnored private let catalog = CodexClient(desktop: false)
    @ObservationIgnored private let desktop = CodexClient(desktop: true)
    @ObservationIgnored private var followed: Set<String> = []
    @ObservationIgnored private var owners: [String: String] = [:]
    @ObservationIgnored private var session = UUID()
    @ObservationIgnored private var refreshing = false

    init(projectActivity: @escaping @Sendable (CodexActivityStream) -> CodexActivityPresentation = { $0.presentation }) {
        self.projectActivity = projectActivity
        desktop.onMessage = { [weak self] in self?.receive($0) }
        desktop.onDisconnect = { [weak self] in self?.lostLiveConnection() }
    }

    func setVisible(_ visible: Bool) {
        isVisible = visible
        if visible { schedulePublication(after: .zero) }
        else {
            publicationTask?.cancel()
            projectionTask?.cancel()
        }
        updateLifecycle()
    }

    /// An opt-in desktop-only subscription survives closing the notch.
    func setStatusMonitoring(_ enabled: Bool) {
        monitorsStatus = enabled
        updateLifecycle()
    }

    private func updateLifecycle() {
        guard isVisible || monitorsStatus else {
            lifecycleTask?.cancel()
            lifecycleTask = nil
            stop()
            return
        }
        guard lifecycleTask == nil else { return }
        lifecycleTask = Task { [weak self] in
            var nextRefresh = ContinuousClock.now
            while !Task.isCancelled {
                guard let self else { return }
                if ContinuousClock.now >= nextRefresh && (self.isVisible || self.threads.isEmpty) {
                    await self.refresh()
                    nextRefresh = .now.advanced(by: .seconds(30))
                } else if !self.desktop.isConnected {
                    do {
                        try await self.desktop.connect()
                        self.liveError = nil
                        for thread in self.threads { self.follow(thread.id) }
                    } catch { self.liveError = error.localizedDescription }
                }
                if !self.isVisible { self.catalog.disconnect() }
                self.retryDelay = self.desktop.isConnected ? .seconds(1) : min(self.retryDelay * 2, .seconds(30))
                do { try await Task.sleep(for: self.desktop.isConnected ? .seconds(5) : self.retryDelay) }
                catch { break }
            }
        }
    }

    func selectThread(_ id: String?) {
        selectedThreadID = id
        guard let id else { return }
        markRead(id)
        streamAccess.removeAll { $0 == id }
        streamAccess.append(id)
        if streams[id] == nil || unavailableActivityIDs.remove(id) != nil {
            streams[id] = CodexActivityStream()
            resubscribe(id)
        }
        while streamAccess.count > 4 {
            let removed = streamAccess.removeFirst()
            streams[removed] = nil
            streamTokens[removed] = nil
            activities[removed] = nil
            activityErrors[removed] = nil
            unavailableActivityIDs.remove(removed)
        }
    }

    func markRead(_ id: String) {
        if unreadThreadIDs.contains(id) { unreadThreadIDs.remove(id) }
    }

    func stop() {
        lifecycleTask?.cancel()
        lifecycleTask = nil
        publicationTask?.cancel()
        projectionTask?.cancel()
        for id in Array(streams.keys) { streams[id]?.disconnect() }
        for id in Array(statusStreams.keys) { statusStreams[id]?.disconnect() }
        if cachedThreads == nil { cachedThreads = threads }
        session = UUID()
        for id in followed { desktop.follow(id, following: false) }
        desktop.disconnect()
        catalog.disconnect()
        followed.removeAll()
        owners.removeAll()
        var disconnected = threads
        for index in disconnected.indices { disconnected[index].isConnected = false; disconnected[index].status = nil }
        if disconnected != threads { threads = disconnected }
    }

    func refresh() async {
        guard !refreshing else { return }
        let session = self.session
        refreshing = true
        isLoading = threads.isEmpty
        defer {
            refreshing = false
            isLoading = false
            if self.session == session, !Task.isCancelled { cachedThreads = nil }
        }
        do {
            let projects = try await CodexProjects.read(from: CodexClient.codexHome.appendingPathComponent(".codex-global-state.json"))
            guard self.session == session, !Task.isCancelled else { return }
            projectCatalog = projects
            var updated = threads
            for index in updated.indices { updated[index].project = projects.project(for: updated[index].id, cwd: updated[index].projectPath) }
            if updated != threads { threads = updated }
            updateProjects()
            projectError = nil
        } catch {
            guard self.session == session, !Task.isCancelled else { return }
            projectError = "Could not read projects from Codex."
        }
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
                    var updated = threads
                    var indices = Dictionary(uniqueKeysWithValues: updated.enumerated().map { ($0.element.id, $0.offset) })
                    for value in result["data"].array {
                        guard var thread = CodexThread(json: value) else { continue }
                        thread.isArchived = archived
                        thread.project = projectCatalog.project(for: thread.id, cwd: thread.projectPath)
                        catalogIDs.insert(thread.id)
                        if let index = indices[thread.id] {
                            thread.status = updated[index].status
                            thread.isConnected = updated[index].isConnected
                            updated[index] = thread
                        } else {
                            indices[thread.id] = updated.count
                            updated.append(thread)
                        }
                        follow(thread.id)
                    }
                    if updated != threads { threads = updated }
                    updateProjects()
                    cursor = result["nextCursor"].string
                    if let cursor, !seenCursors.insert(cursor).inserted { break }
                    try Task.checkCancellation()
                } while cursor != nil
            }
            let removed = Set(threads.filter { !catalogIDs.contains($0.id) && !$0.isConnected && $0.id != selectedThreadID && streams[$0.id] == nil }.map(\.id))
            for id in removed { desktop.follow(id, following: false); followed.remove(id) }
            let sorted = threads.filter { !removed.contains($0.id) }.sorted { $0.updatedAt > $1.updatedAt }
            if sorted != threads { threads = sorted }
            updateProjects()
            let response = try await catalog.request("account/rateLimits/read", params: .object([:]))
            guard self.session == session, !Task.isCancelled else { return }
            limits = CodexLimit.parse(response)
            error = nil
        } catch is CancellationError { }
        catch { if self.session == session { self.error = error.localizedDescription } }
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
        if desktop.isConnected, owners[thread.id] != nil,
           threads.contains(where: { $0.id == thread.id && $0.isConnected }) {
            error = nil
            return true
        }
        guard isConnectingThreadID == nil else { return false }
        isConnectingThreadID = thread.id
        defer { isConnectingThreadID = nil }
        do {
            try? await desktop.connect()
            try Task.checkCancellation()
            if desktop.isConnected, let owner = try? await owner(of: thread.id, timeout: .milliseconds(750)) {
                return try await awaitSnapshot(threadID: thread.id, owner: owner)
            }
            try Task.checkCancellation()
            guard let url = CodexDesktopProtocol.threadURL(thread.id),
                  let application = NSWorkspace.shared.urlForApplication(toOpen: url) else {
                throw CodexConnectionError(message: "Install or open Codex to connect this thread.")
            }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            _ = try await NSWorkspace.shared.open([url], withApplicationAt: application, configuration: configuration)

            let deadline = ContinuousClock.now.advanced(by: .seconds(20))
            repeat {
                try Task.checkCancellation()
                try? await desktop.connect()
                try Task.checkCancellation()
                if desktop.isConnected, let owner = try? await owner(of: thread.id, timeout: .milliseconds(750)) {
                    return try await awaitSnapshot(threadID: thread.id, owner: owner)
                }
                try await Task.sleep(for: .milliseconds(500))
            } while ContinuousClock.now < deadline
            throw CodexConnectionError(message: "Codex could not connect the thread in time. Your draft is saved; try connecting again.")
        } catch is CancellationError {
            return false
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    private func owner(of threadID: String, timeout: Duration = .seconds(12)) async throws -> String {
        let response = try await desktop.request("thread-owner-discovery", params: .object([
            "hostId": .string("local"), "conversationId": .string(threadID)
        ]), timeout: timeout)
        guard let owner = response["handledByClientId"].string else {
            throw CodexConnectionError(message: "This thread has not connected in Codex yet.")
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
        throw CodexConnectionError(message: "The thread is open in Codex, but its status could not be confirmed. Try connecting again.")
    }

    func send(_ text: String, to thread: CodexThread) async -> Bool {
        guard !isSending, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard text.utf8.count <= 65_536 else { error = "This message is too long. Keep it under 64 KB."; return false }
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
                self.error = "Delivery could not be confirmed. Check the thread in Codex before trying again. \(error.localizedDescription)"
            } else if error.localizedDescription == "no-client-found" {
                self.error = "Open the thread in Codex once to connect it."
            } else { self.error = error.localizedDescription }
            return false
        }
    }

    private func updateProjects() {
        var available = projectCatalog.projects
        if threads.contains(where: { $0.project == nil }) { available.append(.unassigned) }
        if projects != available { projects = available }
    }

    private func follow(_ id: String) {
        guard !followed.contains(id), followed.count < 512 || id == selectedThreadID,
              desktop.follow(id) else { return }
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
        if method == "thread-stream-following-status-requested" {
            if followed.contains(id) { desktop.follow(id) }
            return
        }
        guard method == "thread-stream-state-changed" else { return }
        guard message["version"].number == Double(CodexDesktopProtocol.snapshotVersion) else {
            liveError = "The local Codex interface has changed. Live status is unavailable with this version."
            invalidate(id)
            return
        }
        let change = params["change"]
        guard let source = message["sourceClientId"].string else { return }
        let hadStatus = statusStreams[id]?.revision != nil
        if statusStreams[id] == nil, statusStreams.count >= 512,
           let removed = statusStreams.keys.first(where: { $0 != selectedThreadID }) {
            statusStreams[removed] = nil
            attentionByThread[removed] = nil
            unreadThreadIDs.remove(removed)
            invalidate(removed)
            desktop.follow(removed, following: false)
            followed.remove(removed)
        }
        var statusStream = statusStreams[id] ?? CodexActivityStream(maximumBytes: 512 * 1_024)
        switch statusStream.apply(CodexActivityStream.statusChange(change), owner: source) {
        case .ignored: return
        case .unavailable(let reason):
            activityErrors[id] = reason
            invalidate(id)
            return
        case .resync:
            resubscribe(id)
            return
        case .applied: statusStreams[id] = statusStream
        }
        if streams[id] != nil, !unavailableActivityIDs.contains(id) {
            switch streams[id]!.apply(change, owner: source) {
            case .applied:
                if activityErrors[id] != nil { activityErrors[id] = nil }
                dirtyStreams.insert(id)
                schedulePublication()
            case .ignored: break
            case .unavailable(let reason):
                activityErrors[id] = reason
                unavailableActivityIDs.insert(id)
                dirtyStreams.remove(id)
                streams[id] = CodexActivityStream()
                streamTokens[id] = UUID()
            case .resync(let reason):
                activityErrors[id] = reason
                resubscribe(id)
                return
            }
        }
        guard let state = statusStream.state else { return }
        if threads.firstIndex(where: { $0.id == id }) == nil, let thread = CodexThread(json: state) {
            threads.append(thread)
        }
        guard let index = threads.firstIndex(where: { $0.id == id }) else { return }
        var thread = threads[index]
        thread.status = state["threadRuntimeStatus"]["type"].string
        thread.isConnected = true
        if let cwd = state["cwd"].string { thread.projectPath = cwd }
        thread.project = projectCatalog.project(for: thread.id, cwd: thread.projectPath)
        if let title = state["title"].string, !title.isEmpty { thread.title = title }
        if thread != threads[index] {
            threads[index] = thread
            updateProjects()
        }
        let attention = CodexAttention.from(state: state)
        if attentionByThread[id] != attention { attentionByThread[id] = attention }
        owners[id] = source
        if hadStatus, (!isVisible || selectedThreadID != id), !unreadThreadIDs.contains(id) {
            unreadThreadIDs.insert(id)
        }
    }

    private func schedulePublication(after delay: Duration = .milliseconds(100)) {
        guard isVisible, publicationTask == nil else { return }
        publicationTask = Task { [weak self] in
            guard let self else { return }
            defer {
                self.publicationTask = nil
                if !self.dirtyStreams.isEmpty { self.schedulePublication() }
            }
            do { try await Task.sleep(for: delay) } catch { return }
            guard self.isVisible, !Task.isCancelled else { return }
            await self.publishActivities()
        }
    }

    /// Snapshot on the UI actor, format on a worker, then publish only to the same stream lifetime.
    func publishActivities() async {
        guard projectionTask == nil, !dirtyStreams.isEmpty else { return }
        let snapshots = streams.filter { dirtyStreams.contains($0.key) }
        dirtyStreams.removeAll()
        let tokens = streamTokens
        let session = session
        guard !snapshots.isEmpty else { return }
        let projectActivity = projectActivity
        let worker = Task.detached(priority: .utility) {
            var result: [String: CodexActivityPresentation] = [:]
            for (id, stream) in snapshots {
                guard !Task.isCancelled else { break }
                result[id] = projectActivity(stream)
            }
            return result
        }
        projectionTask = worker
        let presentations = await withTaskCancellationHandler {
            await worker.value
        } onCancel: { worker.cancel() }
        projectionTask = nil
        guard !Task.isCancelled, !worker.isCancelled, self.session == session else {
            dirtyStreams.formUnion(snapshots.keys.filter { streams[$0] != nil })
            return
        }
        for (id, presentation) in presentations {
            guard streams[id] != nil, streamTokens[id] == tokens[id],
                  streams[id]?.owner == snapshots[id]?.owner else { continue }
            if activities[id] != presentation { activities[id] = presentation }
        }
    }

    private func resubscribe(_ id: String) {
        invalidate(id)
        desktop.follow(id, following: false)
        desktop.follow(id)
    }

    private func invalidate(_ id: String) {
        if streams[id] != nil { streamTokens[id] = UUID() }
        owners[id] = nil
        streams[id]?.disconnect()
        statusStreams[id]?.disconnect()
        if let index = threads.firstIndex(where: { $0.id == id }) {
            threads[index].isConnected = false
            threads[index].status = nil
        }
    }

    private func lostLiveConnection() {
        followed.removeAll()
        unavailableActivityIDs.removeAll()
        for id in streams.keys { streamTokens[id] = UUID() }
        for id in Array(streams.keys) { streams[id]?.disconnect() }
        for id in Array(statusStreams.keys) { statusStreams[id]?.disconnect() }
        owners.removeAll()
        var disconnected = threads
        for index in disconnected.indices { disconnected[index].isConnected = false; disconnected[index].status = nil }
        if disconnected != threads { threads = disconnected }
        liveError = "Disconnected from Codex. Reconnecting…"
    }
}
