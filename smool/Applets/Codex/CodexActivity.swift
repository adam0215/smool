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

struct CodexActivityLink: Identifiable, Equatable, Sendable {
    var id: String { url.absoluteString }
    let title: String
    let url: URL
}

struct CodexActivityItem: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable { case user, assistant, tool, info }

    let id: String
    let kind: Kind
    let title: String
    let text: String
    let details: String
    let links: [CodexActivityLink]
    let isRunning: Bool
    let isError: Bool

    var presentationBytes: Int {
        id.utf8.count + title.utf8.count + text.utf8.count + details.utf8.count
            + links.reduce(0) { $0 + $1.title.utf8.count + $1.url.absoluteString.utf8.count }
    }
}

struct CodexActivityPresentation: Equatable, Sendable {
    var items: [CodexActivityItem] = []
    private(set) var latestMessage: CodexActivityItem?
    private(set) var workingSummary: CodexActivityItem?
    private var currentTurnPrefix: String?
    var runningTools: [CodexActivityItem] {
        guard let currentTurnPrefix else { return [] }
        return items.filter { $0.kind == .tool && $0.isRunning && $0.id.hasPrefix(currentTurnPrefix) }
    }
    var attention: CodexAttention = .idle
    var revision = 0
    var omittedItemCount = 0

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
        attention = .from(state: state)
        let turns = Self.turns(in: state)
        if let current = turns.last, current.value["status"].string == "inProgress" {
            currentTurnPrefix = "\(current.key)/"
            if let summary = current.value["items"].array.last(where: {
                $0["type"].string == "reasoning" && Self.hasJoinedText($0["summary"].array.compactMap(\.string))
            }) {
                workingSummary = Self.item(id: "\(current.key)/\(summary["id"].string ?? "summary")", kind: .info,
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
                latestMessage = Self.item(id: "\(turn.key)/prompt", kind: .user, title: "You", text: Self.contentText(turn.value["params"]["input"]))
                break
            }
        }
        var kept: [CodexActivityItem] = []
        var bytes = 0
        var omitted = 0
        var full = false

        func retain(_ item: @autoclosure () -> CodexActivityItem) {
            guard !full else { omitted += 1; return }
            let next = item()
            let size = next.presentationBytes
            guard bytes + size <= 512 * 1_024 else {
                full = true
                omitted += 1
                return
            }
            kept.append(next)
            bytes += size
            full = kept.count == 400
        }

        // Visit newest items first. Once full, only count older visible entries, without
        // formatting tool arguments, joining output or extracting links from that history.
        for turn in turns.reversed() {
            let entries = turn.value["items"].array
            let active = turn.value["status"].string == "inProgress"
            if turn.value["status"].string == "failed", let message = turn.value["error"]["message"].string,
               !entries.contains(where: { $0["type"].string == "error" }) {
                retain(Self.item(id: "\(turn.key)/error", kind: .info, title: "Error", text: message, failed: true))
            }
            for (index, entry) in entries.enumerated().reversed() {
                guard let type = EntryType(rawValue: entry["type"].string ?? "") else { continue }
                if type == .reasoning, !Self.hasJoinedText(entry["summary"].array.compactMap(\.string)) { continue }
                if full { omitted += 1; continue }
                let id = "\(turn.key)/\(entry["id"].string ?? "item:\(index)")"
                let running = active && entry["status"].string == "inProgress"
                let failed = entry["status"].string == "failed" || entry["status"].string == "declined"
                switch type {
                case .userMessage:
                    retain(Self.item(id: id, kind: .user, title: "You", text: Self.contentText(entry["content"])))
                case .steeringUserMessage:
                    retain(Self.item(id: id, kind: .user, title: "You", text: Self.contentText(entry["input"])))
                case .agentMessage, .plan:
                    let completedAt = entry["id"].string.flatMap { turn.value["agentMessageCompletedAtMsById"][$0].number }
                    retain(Self.item(id: id, kind: .assistant, title: entry["type"].string == "plan" ? "Plan" : "Codex",
                                     text: entry["text"].string ?? "", running: active && index == entries.count - 1 && completedAt == nil))
                case .commandExecution:
                    let command = entry["command"].string ?? "Command"
                    let exitCode = entry["exitCode"].number.flatMap(Int.init(exactly:)).map { "Exit code: \($0)" }
                    let output = [entry["aggregatedOutput"].string, exitCode].compactMap { $0 }.joined(separator: "\n")
                    retain(Self.item(id: id, kind: .tool, title: "Terminal", text: command, details: output,
                                     running: running, failed: failed || (entry["exitCode"].number ?? 0) != 0))
                case .mcpToolCall, .dynamicToolCall:
                    let name = [entry["server"].string ?? entry["namespace"].string, entry["tool"].string].compactMap { $0 }.joined(separator: ".")
                    let result = entry["type"].string == "mcpToolCall" ? entry["result"]["content"] : entry["contentItems"]
                    let textOutput = Self.contentText(result)
                    let output = textOutput.isEmpty ? Self.jsonText(entry["result"]["structuredContent"]) ?? "" : textOutput
                    let error = entry["error"]["message"].string
                    let details = [Self.jsonText(entry["arguments"]), output, error].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n\n")
                    retain(Self.item(id: id, kind: .tool, title: name.isEmpty ? "Tool" : name, text: output,
                                     details: details, running: running, failed: failed || error != nil || Self.isFalse(entry["success"]), linkSource: output))
                case .collabAgentToolCall:
                    retain(Self.item(id: id, kind: .tool, title: entry["tool"].string ?? "Agent", text: entry["prompt"].string ?? "",
                                     details: Self.jsonText(entry["agentsStates"]) ?? "", running: running, failed: failed))
                case .userInputResponse:
                    let questions = entry["questions"].array.compactMap { $0["question"].string }.joined(separator: "\n")
                    retain(Self.item(id: id, kind: .info, title: "Question for you", text: questions, details: Self.jsonText(entry["answers"]) ?? ""))
                case .permissionRequest:
                    retain(Self.item(id: id, kind: .info, title: "Permission", text: entry["reason"].string ?? "Codex is requesting permission.",
                                     details: Self.jsonText(entry["permissions"]) ?? ""))
                case .fileChange:
                    let changes = entry["changes"].array
                    let paths = changes.compactMap { $0["path"].string }.joined(separator: "\n")
                    let diffs = changes.compactMap { $0["diff"].string }.joined(separator: "\n\n")
                    retain(Self.item(id: id, kind: .tool, title: "File changes", text: paths, details: diffs, running: running, failed: failed))
                case .webSearch:
                    retain(Self.item(id: id, kind: .tool, title: "Search", text: entry["query"].string ?? entry["action"]["query"].string ?? "",
                                     details: Self.jsonText(entry["action"]) ?? "", running: running))
                case .error:
                    retain(Self.item(id: id, kind: .info, title: "Error", text: entry["message"].string ?? "An error occurred.",
                                     details: entry["additionalDetails"].string ?? "", failed: true))
                case .contextCompaction:
                    retain(Self.item(id: id, kind: .info, title: "Summarizing context", text: "", running: active && !Self.isTrue(entry["completed"])))
                case .reasoning:
                    // Only the public summary is rendered. The internal content field is not part of this view.
                    let summary = entry["summary"].array.compactMap(\.string).joined(separator: "\n")
                    retain(Self.item(id: id, kind: .info, title: "Working note", text: summary))
                }
            }
            let input = turn.value["params"]["input"]
            if !entries.contains(where: { $0["type"].string == "userMessage" }), Self.hasContentText(input) {
                retain(Self.item(id: "\(turn.key)/prompt", kind: .user, title: "You", text: Self.contentText(input)))
            }
        }
        // The reducer keeps raw array indices intact for subsequent patches.
        items = kept.reversed()
        if let message = items.last(where: { $0.id == latestMessage?.id }) { latestMessage = message }
        omittedItemCount = omitted
    }

    private enum EntryType: String {
        case userMessage, steeringUserMessage, agentMessage, plan, commandExecution
        case mcpToolCall, dynamicToolCall, collabAgentToolCall, userInputResponse
        case permissionRequest, fileChange, webSearch, error, contextCompaction, reasoning
    }

    /// Shared by live projection and newest-first history pages. No tool or reasoning payload is retained.
    static func message(_ entry: CodexJSON, id: String) -> CodexActivityItem? {
        switch entry["type"].string {
        case "userMessage": return item(id: id, kind: .user, title: "You", text: contentText(entry["content"]))
        case "steeringUserMessage": return item(id: id, kind: .user, title: "You", text: contentText(entry["input"]))
        case "agentMessage": return item(id: id, kind: .assistant, title: "Codex", text: entry["text"].string ?? "")
        default: return nil
        }
    }

    private static func hasJoinedText(_ parts: [String]) -> Bool {
        parts.count > 1 || parts.first?.isEmpty == false
    }

    private static func hasContentText(_ value: CodexJSON) -> Bool {
        hasJoinedText(value.array.compactMap(contentPart))
    }

    private static func item(id: String, kind: CodexActivityItem.Kind, title: String, text: String,
                             details: String = "", running: Bool = false, failed: Bool = false, linkSource: String? = nil) -> CodexActivityItem {
        let text = clipped(text)
        let details = clipped(details)
        return CodexActivityItem(id: id, kind: kind, title: prefix(title, bytes: 256), text: text, details: details,
                                 links: links(in: linkSource ?? text + "\n" + details), isRunning: running, isError: failed)
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

    private static func jsonText(_ value: CodexJSON) -> String? {
        if case .null = value { return nil }
        if let text = value.string { return text }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(value)).flatMap { String(data: $0, encoding: .utf8) }
    }

    private static let linkPattern = try? NSRegularExpression(pattern: #"\[([^\]\n]+)\]\(([^\s)]+)\)|(?:https?://|codex://)[^\s<>\)\]]+"#)

    private static func links(in text: String) -> [CodexActivityLink] {
        // Links are extracted from actual message/output text. Never infer a file URL from a tool argument.
        guard let regex = linkPattern else { return [] }
        let wasClipped = text.utf8.count > 32_768
        let text = prefix(text, bytes: 32_768)
        let source = text as NSString
        var seen: Set<String> = []
        var links: [CodexActivityLink] = []
        regex.enumerateMatches(in: text, range: NSRange(location: 0, length: source.length)) { match, _, stop in
            guard let match else { return }
            // The clipping boundary can bisect a bare URL. Do not expose a changed target.
            if wasClipped, NSMaxRange(match.range) == source.length { return }
            let markdown = match.range(at: 2).location != NSNotFound
            let target = source.substring(with: markdown ? match.range(at: 2) : match.range)
            // Reject oversized targets instead of turning a truncated path into a different link.
            guard target.utf8.count <= 2_048 else { return }
            let title = markdown ? source.substring(with: match.range(at: 1)) : target
            let url: URL?
            if target.hasPrefix("/") { url = URL(fileURLWithPath: target) }
            else { url = URL(string: target) }
            guard let url, url.absoluteString.utf8.count <= 2_048,
                  ["http", "https", "codex", "file"].contains(url.scheme?.lowercased() ?? ""),
                  seen.insert(url.absoluteString).inserted else { return }
            links.append(CodexActivityLink(title: prefix(title, bytes: 256), url: url))
            if links.count == 32 { stop.pointee = true }
        }
        return links
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
