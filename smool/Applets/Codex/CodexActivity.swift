import Foundation

enum CodexAttention: Equatable, Sendable {
    case idle, working, waitingForUser, approval, failed(String)

    var label: String {
        switch self {
        case .idle: "Done"
        case .working: "Working"
        case .waitingForUser: "Waiting for you"
        case .approval: "Needs approval"
        case .failed: "An error occurred"
        }
    }

    var needsAttention: Bool {
        switch self {
        case .waitingForUser, .approval, .failed: true
        case .idle, .working: false
        }
    }

    static func from(state: CodexJSON) -> Self {
        let requests = state["requests"].array.filter {
            if case .bool(true) = $0["completed"] { return false }
            return true
        }
        if requests.contains(where: { $0["method"].string?.hasSuffix("/requestApproval") == true }) { return .approval }
        let runtime = state["threadRuntimeStatus"]
        let flags = runtime["activeFlags"].array.compactMap(\.string)
        if flags.contains("waitingOnApproval") { return .approval }
        let inputMethods = ["item/tool/requestUserInput", "item/tool/requestOptionPicker", "item/plan/requestImplementation", "mcpServer/elicitation/request"]
        if requests.contains(where: { inputMethods.contains($0["method"].string ?? "") }) { return .waitingForUser }
        if flags.contains("waitingOnUserInput") { return .waitingForUser }
        let latest = CodexActivityPresentation.turns(in: state).last?.value
        if latest?["status"].string == "failed" {
            return .failed(latest?["error"]["message"].string ?? "Codex could not finish the task.")
        }
        if runtime["type"].string == "systemError" { return .failed("Codex reported a system error.") }
        if runtime["type"].string == "active" || latest?["status"].string == "inProgress" { return .working }
        return .idle
    }
}

struct CodexActivityItem: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let text: String
    // Only terminal tools expose output, limited to their two latest lines.
    let details: String
}

struct CodexActivityPresentation: Equatable, Sendable {
    static let maximumBytes = 256 * 1_024
    static let maximumRunningTools = 32

    private(set) var latestMessage: CodexActivityItem?
    private(set) var workingSummary: CodexActivityItem?
    private(set) var currentNote: CodexActivityItem?
    private(set) var runningTools: [CodexActivityItem] = []
    private(set) var isThinking = false
    var attention: CodexAttention = .idle
    var revision = 0

    // Schema verified against the installed desktop's v11 stream and transcript projector.
    // The desktop can hold disjoint history islands; dictionary order is not chronology.
    fileprivate static func turns(in state: CodexJSON) -> [(key: String, value: CodexJSON)] {
        if state["turnHistory"]["kind"].string == "canonical" {
            let history = state["turnHistory"]["history"]
            var seen: Set<String> = []
            return history["islands"].array.flatMap { island in
                island["entries"].array.compactMap { entry in
                    guard let key = entry["value"].string, seen.insert(key).inserted,
                          let turn = history["entitiesByKey"].object[key] else { return nil }
                    return (key, turn)
                }
            }
        }
        return state["turns"].array.enumerated().map { index, turn in
            (turn["turnId"].string.map { "turn:\($0)" } ?? "legacy:\(index)", turn)
        }
    }

    init() {}

    init(state: CodexJSON, revision: Int) {
        self.revision = revision
        reconcileActivity(state: state)
        let turns = Self.turns(in: state)
        if let current = turns.last, current.value["status"].string == "inProgress" {
            if let summary = current.value["items"].array.last(where: {
                $0["type"].string == "reasoning" && Self.hasJoinedText($0["summary"].array.compactMap(\.string))
            }) {
                workingSummary = Self.item(id: "\(current.key)/\(summary["id"].string ?? "summary")",
                                           title: "Working note", text: summary["summary"].array.compactMap(\.string).joined(separator: "\n"))
            }
        }
        for turn in turns.reversed() {
            for (index, entry) in turn.value["items"].array.enumerated().reversed() {
                if let message = Self.message(entry, id: "\(turn.key)/\(entry["id"].string ?? "item:\(index)")") {
                    latestMessage = message
                    break
                }
            }
            if latestMessage != nil { break }
            if Self.hasContentText(turn.value["params"]["input"]) {
                latestMessage = Self.item(id: "\(turn.key)/prompt", title: "You", text: Self.contentText(turn.value["params"]["input"]))
                break
            }
        }
        // Reserve one clipped status message, then prioritize the message and current notes.
        var remaining = Self.maximumBytes - 33_000
        func retain(_ item: CodexActivityItem?) -> CodexActivityItem? {
            guard let item else { return nil }
            let bytes = item.id.utf8.count + item.title.utf8.count + item.text.utf8.count + item.details.utf8.count
            guard bytes <= remaining else { return nil }
            remaining -= bytes
            return item
        }
        latestMessage = retain(latestMessage)
        workingSummary = retain(workingSummary)
        guard let current = turns.last, current.value["status"].string == "inProgress" else { return }
        let entries = current.value["items"].array
        for (index, entry) in entries.enumerated().reversed() {
            if let note = Self.note(entry, id: "\(current.key)/\(entry["id"].string ?? "item:\(index)")") {
                currentNote = retain(note)
                break
            }
        }
        let lastWorkIndex = Self.lastWorkIndex(in: entries)
        for (index, entry) in entries.enumerated() {
            guard runningTools.count < Self.maximumRunningTools else { break }
            let id = "\(current.key)/\(entry["id"].string ?? "item:\(index)")"
            if Self.isRunning(entry, in: current.value, isLastWork: index == lastWorkIndex),
               let tool = Self.tool(entry, id: id) {
                guard let tool = retain(tool) else { break }
                runningTools.append(tool)
            }
        }
        for hook in current.value["hookRuns"].array where hook["run"]["status"].string == "running" {
            guard runningTools.count < Self.maximumRunningTools else { break }
            let run = hook["run"]
            guard let tool = retain(Self.item(id: "\(current.key)/hook:\(hook["id"].string ?? run["id"].string ?? "unknown")",
                                             title: "Hook · \(run["eventName"].string ?? "Running")",
                                             text: run["statusMessage"].string ?? "")) else { break }
            runningTools.append(tool)
        }
    }

    private static func tool(_ entry: CodexJSON, id: String) -> CodexActivityItem? {
        let title: String
        let text: String
        var details = ""
        switch entry["type"].string {
        case "commandExecution":
            title = "Terminal"
            text = entry["command"].string ?? "Command"
            // Bound the scan as well as retained output. A tool can emit megabytes on one line.
            details = String((entry["aggregatedOutput"].string ?? "").suffix(8_192))
                .split(separator: "\n").suffix(2).joined(separator: "\n")
        case "mcpToolCall", "dynamicToolCall":
            let name = [entry["server"].string ?? entry["namespace"].string, entry["tool"].string].compactMap { $0 }.joined(separator: ".")
            title = name.isEmpty ? "Tool" : name
            let output = contentText(entry["type"].string == "mcpToolCall" ? entry["result"]["content"] : entry["contentItems"])
            text = output.isEmpty ? toolDescription(entry["arguments"]) : output
        case "collabAgentToolCall":
            title = entry["tool"].string ?? "Agent"
            text = entry["prompt"].string ?? ""
        case "fileChange":
            title = "File changes"
            text = entry["changes"].array.compactMap { $0["path"].string }.joined(separator: "\n")
        case "webSearch":
            let action = entry["action"]
            title = action["type"].string == "openPage" ? "Opening page" : action["type"].string == "findInPage" ? "Finding in page" : "Search"
            text = firstText([action["pattern"].string, action["queries"].array.compactMap(\.string).joined(separator: ", "),
                              action["query"].string, entry["query"].string, action["url"].string])
        case "imageGeneration": title = "Generating image"; text = entry["revisedPrompt"].string ?? ""
        case "imageView": title = "Viewing image"; text = entry["path"].string ?? ""
        case "sleep": title = "Waiting"; text = ""
        case "automaticApprovalReview": title = "Reviewing approval"; text = entry["rationale"].string ?? ""
        case "worktreeInit": title = "Preparing worktree"; text = entry["message"].string ?? ""
        case "contextCompaction": title = "Summarizing context"; text = ""
        default: return nil
        }
        return item(id: id, title: title, text: text, details: details)
    }

    private static func note(_ entry: CodexJSON, id: String) -> CodexActivityItem? {
        let title: String
        let text: String
        switch entry["type"].string {
        case "userInputResponse":
            title = "Question for you"
            text = entry["questions"].array.compactMap { $0["question"].string }.joined(separator: "\n")
        case "permissionRequest": title = "Permission"; text = entry["reason"].string ?? "Codex is requesting permission."
        case "subAgentActivity":
            title = "Agent"
            text = [entry["agentPath"].string, entry["kind"].string].compactMap { $0 }.joined(separator: " · ")
        case "todo-list":
            title = "Plan"
            text = firstText([entry["explanation"].string, entry["plan"].array.map {
                ($0["status"].string == "completed" ? "✓ " : "") + ($0["step"].string ?? "")
            }.joined(separator: "\n")])
        case "mcpServerElicitation": title = "Question for you"; text = entry["params"]["message"].string ?? ""
        case "hookPrompt": title = "Hook"; text = entry["fragments"].array.compactMap { $0["text"].string }.joined(separator: "\n")
        case "functionCallOutput": title = entry["name"].string ?? "Tool output"; text = entry["output"].string ?? contentText(entry["output"])
        case "planImplementation": title = "Plan"; text = entry["planContent"].string ?? ""
        case "enteredReviewMode", "exitedReviewMode": title = "Review"; text = entry["review"].string ?? ""
        case "modelChanged", "modelRerouted": title = "Model changed"; text = firstText([entry["toModel"].string, entry["model"].string])
        case "remoteTaskCreated": title = "Task created"; text = entry["taskId"].string ?? ""
        case "strictReviewNotice", "autoReviewInterruptionWarning": title = "Approval review"; text = entry["message"].string ?? "Approval review requires attention."
        case "personalityChanged": title = "Personality changed"; text = entry["personality"].string ?? ""
        case "forkedFromConversation": title = "Thread forked"; text = ""
        case "steered": title = "Follow-up received"; text = ""
        case "error": title = "Error"; text = entry["message"].string ?? "An error occurred."
        default: return nil
        }
        return item(id: id, title: title, text: text)
    }

    // This inexpensive pass also runs before publishing a worker's older projection.
    // A completion must remove activity immediately, even while text formatting is busy.
    mutating func reconcileActivity(state: CodexJSON) {
        attention = .from(state: state)
        if case .failed(let message) = attention { attention = .failed(Self.clipped(message)) }
        var activeItemIDs: Set<String> = []
        isThinking = false
        guard let current = Self.turns(in: state).last, current.value["status"].string == "inProgress" else {
            workingSummary = nil
            currentNote = nil
            runningTools.removeAll()
            return
        }
        let prefix = "\(current.key)/"
        if workingSummary?.id.hasPrefix(prefix) == false { workingSummary = nil }
        if currentNote?.id.hasPrefix(prefix) == false { currentNote = nil }
        let entries = current.value["items"].array
        let lastWorkIndex = Self.lastWorkIndex(in: entries)
        for (index, entry) in entries.enumerated() {
            if Self.isRunning(entry, in: current.value, isLastWork: index == lastWorkIndex) {
                activeItemIDs.insert("\(prefix)\(entry["id"].string ?? "item:\(index)")")
            }
        }
        for hook in current.value["hookRuns"].array where hook["run"]["status"].string == "running" {
            activeItemIDs.insert("\(prefix)hook:\(hook["id"].string ?? hook["run"]["id"].string ?? "unknown")")
        }
        runningTools.removeAll { !activeItemIDs.contains($0.id) }
        isThinking = attention == .working && (lastWorkIndex.map {
            entries[$0]["type"].string == "reasoning" && Self.isRunning(entries[$0], in: current.value, isLastWork: true)
        } ?? false)
    }

    private static func lastWorkIndex(in entries: [CodexJSON]) -> Int? {
        entries.lastIndex { !["userMessage", "hookPrompt", "steeringUserMessage", "steered"].contains($0["type"].string ?? "") }
    }

    private static func isRunning(_ entry: CodexJSON, in turn: CodexJSON, isLastWork: Bool) -> Bool {
        if isTrue(entry["completed"]) || isFalse(entry["success"]) { return false }
        if entry["error"]["message"].string != nil || isTrue(entry["result"]["isError"]) { return false }
        if entry["type"].string == "commandExecution", entry["exitCode"].number != nil { return false }
        if let id = entry["id"].string, turn["interruptedCommandExecutionItemIds"].array.contains(where: { $0.string == id }) { return false }
        if let status = entry["status"].string { return status == "inProgress" || status == "in_progress" }
        switch entry["type"].string {
        // These items carry no status in the installed protocol. Match the desktop's
        // last-work-item inference rather than claiming an unavailable completion event.
        case "webSearch", "reasoning", "imageView", "sleep": return isLastWork
        case "contextCompaction": return isFalse(entry["completed"])
        default: return false
        }
    }

    private static func firstText(_ values: [String?]) -> String {
        values.compactMap { $0 }.first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? ""
    }

    private static func toolDescription(_ arguments: CodexJSON) -> String {
        firstText([arguments["title"].string, arguments["description"].string, arguments["command"].string,
                   arguments["cmd"].string, arguments["query"].string, arguments["q"].string, arguments["url"].string,
                   arguments["path"].string])
    }

    /// Shared by live projection and newest-first history pages. No tool or reasoning payload is retained.
    static func message(_ entry: CodexJSON, id: String) -> CodexActivityItem? {
        switch entry["type"].string {
        case "userMessage": return item(id: id, title: "You", text: contentText(entry["content"]))
        case "steeringUserMessage": return item(id: id, title: "You", text: contentText(entry["input"]))
        case "agentMessage": return item(id: id, title: "Codex", text: entry["text"].string ?? "")
        case "plan": return item(id: id, title: "Plan", text: entry["text"].string ?? "")
        default: return nil
        }
    }

    private static func hasJoinedText(_ parts: [String]) -> Bool {
        parts.count > 1 || parts.first?.isEmpty == false
    }

    private static func hasContentText(_ value: CodexJSON) -> Bool {
        hasJoinedText(value.array.compactMap(contentPart))
    }

    private static func item(id: String, title: String, text: String,
                             details: String = "") -> CodexActivityItem {
        CodexActivityItem(id: id, title: prefix(title, bytes: 256), text: clipped(text), details: clipped(details))
    }

    private static func prefix(_ text: String, bytes: Int) -> String {
        guard text.utf8.count > bytes else { return text }
        var prefix = text.utf8.prefix(bytes)
        // A byte boundary may split a Unicode scalar. Never publish a broken character.
        while !prefix.isEmpty {
            if let result = String(bytes: prefix, encoding: .utf8) { return result }
            prefix = prefix.dropLast()
        }
        return ""
    }

    private static func clipped(_ text: String) -> String {
        text.utf8.count > 32_768 ? prefix(text, bytes: 32_768) + "\n… Read the rest in Codex." : text
    }

    private static func contentPart(_ part: CodexJSON) -> String? {
        switch part["type"].string {
        case "text", "inputText": part["text"].string
        case "image", "inputImage", "localImage": "[Image]"
        case "audio", "inputAudio": "[Audio]"
        case "resource": part["resource"]["text"].string ?? part["resource"]["uri"].string
        case "resource_link": part["uri"].string
        default: nil
        }
    }

    private static func contentText(_ value: CodexJSON) -> String {
        value.array.compactMap(contentPart).joined(separator: "\n")
    }

    private static func isTrue(_ value: CodexJSON) -> Bool {
        if case .bool(true) = value { true } else { false }
    }

    private static func isFalse(_ value: CodexJSON) -> Bool {
        if case .bool(false) = value { true } else { false }
    }

}

enum CodexStreamResult: Equatable {
    case applied, ignored, resync(String), unavailable(String)
}

struct CodexActivityStream: Sendable {
    private(set) var state: CodexJSON?
    private(set) var owner: String?
    private(set) var revision: Int?
    private(set) var displayRevision = 0
    private var retiredOwners: [String] = []
    let maximumBytes: Int

    init(maximumBytes: Int = 8 * 1_024 * 1_024) { self.maximumBytes = maximumBytes }

    var presentation: CodexActivityPresentation {
        state.map { CodexActivityPresentation(state: $0, revision: displayRevision) } ?? CodexActivityPresentation()
    }

    mutating func disconnect() {
        owner = nil
        revision = nil
        retiredOwners.removeAll()
    }

    mutating func apply(_ change: CodexJSON, owner incomingOwner: String) -> CodexStreamResult {
        guard !incomingOwner.isEmpty, let nextRevision = Self.integer(change["revision"]) else {
            return .resync("Codex sent an invalid revision.")
        }
        if retiredOwners.contains(incomingOwner) { return .ignored }
        switch change["type"].string {
        case "snapshot":
            if owner == incomingOwner, let revision, nextRevision <= revision { return .ignored }
            let snapshot = change["conversationState"]
            guard case .object = snapshot else { return .resync("Codex sent an invalid snapshot.") }
            guard Self.fits(snapshot, budget: maximumBytes) else {
                return .unavailable("This thread is too large for the live view. Read the full thread in Codex.")
            }
            if let owner, owner != incomingOwner {
                retiredOwners.append(owner)
                retiredOwners = Array(retiredOwners.suffix(8))
            }
            state = snapshot
        case "patches":
            guard owner == incomingOwner, let revision, var updated = state else {
                return .resync("Waiting for a current snapshot from Codex.")
            }
            if nextRevision <= revision { return .ignored }
            guard Self.integer(change["baseRevision"]) == revision else {
                return .resync("Activity is missing between updates. Reloading the thread.")
            }
            guard case .array(let patches) = change["patches"], patches.count <= 10_000 else {
                return .resync("Codex sent an invalid update.")
            }
            do {
                for patch in patches { updated = try Self.applying(patch, to: updated) }
            } catch { return .resync("The Codex update could not be applied. Reloading the thread.") }
            guard case .object = updated else { return .resync("Codex sent an invalid snapshot.") }
            guard Self.fits(updated, budget: maximumBytes) else { return .unavailable("This thread is too large for the live view. Read the full thread in Codex.") }
            state = updated
        default: return .resync("Codex sent an unknown update type.")
        }
        owner = incomingOwner
        revision = nextRevision
        displayRevision = nextRevision
        return .applied
    }

    /// Keep turn order and statuses for background attention without retaining transcript bodies.
    /// Applying the projected patches must produce the same metadata as projecting the full state.
    static func statusChange(_ change: CodexJSON) -> CodexJSON {
        var result = change.object
        if change["type"].string == "snapshot" {
            result["conversationState"] = StatusNode.state.project(change["conversationState"])
        } else if change["type"].string == "patches", case .array(let patches) = change["patches"] {
            result["patches"] = .array(patches.compactMap { patch in
                guard case .array(let path) = patch["path"] else { return patch }
                var node = StatusNode.state
                for segment in path {
                    guard let child = node.child(segment) else { return nil }
                    node = child
                }
                var projected = patch.object
                if let value = projected["value"] { projected["value"] = node.project(value) }
                return .object(projected)
            })
        }
        result["acceptedTextChanges"] = nil
        return .object(result)
    }

    private enum StatusNode {
        case state, turns, turn, turnHistory, history, entities, value

        func child(_ segment: CodexJSON) -> Self? {
            switch self {
            case .state:
                switch segment.string {
                case "turns": .turns
                case "turnHistory": .turnHistory
                case "id", "title", "cwd", "threadRuntimeStatus", "requests", "error": .value
                default: nil
                }
            case .turns: segment.number == nil ? nil : .turn
            case .turn:
                ["turnId", "status", "error"].contains(segment.string ?? "") ? .value : nil
            case .turnHistory:
                switch segment.string {
                case "kind": .value
                case "history": .history
                default: nil
                }
            case .history:
                switch segment.string {
                case "islands": .value
                case "entitiesByKey": .entities
                default: nil
                }
            case .entities: segment.string == nil ? nil : .turn
            case .value: .value
            }
        }

        func project(_ input: CodexJSON) -> CodexJSON {
            switch self {
            case .value: return input
            case .turns:
                guard case .array(let turns) = input else { return input }
                return .array(turns.map { StatusNode.turn.project($0) })
            default:
                guard case .object(let object) = input else { return input }
                return .object(object.reduce(into: [:]) { result, entry in
                    if let child = child(.string(entry.key)) { result[entry.key] = child.project(entry.value) }
                })
            }
        }
    }

    private static func integer(_ value: CodexJSON) -> Int? {
        guard let number = value.number, number.isFinite, number >= 0, number <= 9_007_199_254_740_991,
              number.rounded(.towardZero) == number else { return nil }
        return Int(number)
    }

    private enum PatchError: Error { case invalid }

    private static func applying(_ patch: CodexJSON, to value: CodexJSON) throws -> CodexJSON {
        guard let operation = patch["op"].string, ["add", "remove", "replace"].contains(operation),
              case .array(let path) = patch["path"], path.count <= 64,
              operation == "remove" || patch.object["value"] != nil else { throw PatchError.invalid }
        return try replacing(value, path: path[...], operation: operation, replacement: patch["value"])
    }

    private static func replacing(_ value: CodexJSON, path: ArraySlice<CodexJSON>, operation: String, replacement: CodexJSON) throws -> CodexJSON {
        guard let segment = path.first else {
            guard operation != "remove" else { throw PatchError.invalid }
            return replacement
        }
        let tail = path.dropFirst()
        switch value {
        case .object(var object):
            guard let key = segment.string else { throw PatchError.invalid }
            if tail.isEmpty {
                guard operation == "add" || object[key] != nil else { throw PatchError.invalid }
                if operation == "remove" { object.removeValue(forKey: key) }
                else { object[key] = replacement }
            } else {
                guard let child = object[key] else { throw PatchError.invalid }
                object[key] = try replacing(child, path: tail, operation: operation, replacement: replacement)
            }
            return .object(object)
        case .array(var array):
            guard let index = integer(segment), index <= array.count else { throw PatchError.invalid }
            if tail.isEmpty, operation == "add" { array.insert(replacement, at: index) }
            else {
                guard index < array.count else { throw PatchError.invalid }
                if tail.isEmpty, operation == "remove" { array.remove(at: index) }
                else { array[index] = try replacing(array[index], path: tail, operation: operation, replacement: replacement) }
            }
            return .array(array)
        default: throw PatchError.invalid
        }
    }

    private static func fits(_ value: CodexJSON, budget: Int) -> Bool {
        var remaining = budget
        func visit(_ value: CodexJSON, depth: Int) -> Bool {
            remaining -= 64
            guard remaining >= 0, depth <= 64 else { return false }
            switch value {
            case .string(let text): remaining -= text.utf8.count
            case .array(let values):
                for child in values where !visit(child, depth: depth + 1) { return false }
            case .object(let values):
                for (key, child) in values {
                    remaining -= key.utf8.count + 32
                    if !visit(child, depth: depth + 1) { return false }
                }
            default: break
            }
            return remaining >= 0
        }
        return visit(value, depth: 0)
    }
}
