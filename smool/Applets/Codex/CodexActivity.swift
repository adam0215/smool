import Foundation

struct CodexReadingPosition: Equatable {
    var anchorID: String?
    var contentOffset: CGFloat = 0
    var followsLatest = true
    var hasNewActivity = false
    var expandedGroups: Set<String> = []
    var revision: Int?
    var omittedItemCount = 0

    mutating func receive(revision next: Int) {
        if let revision, next > revision, !followsLatest { hasNewActivity = true }
        revision = next
    }

    mutating func userScrolled(to offset: CGFloat, atBottom: Bool) {
        contentOffset = max(0, offset)
        followsLatest = atBottom
        if atBottom { hasNewActivity = false }
    }
}


enum CodexAttention: Equatable, Sendable {
    case idle, working, waitingForUser, approval, failed(String)

    var label: String {
        switch self {
        case .idle: "Klar"
        case .working: "Arbetar"
        case .waitingForUser: "Väntar på dig"
        case .approval: "Behöver godkännande"
        case .failed: "Ett fel uppstod"
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
            return .failed(latest?["error"]["message"].string ?? "Codex kunde inte slutföra arbetet.")
        }
        if runtime["type"].string == "systemError" { return .failed("Codex rapporterade ett systemfel.") }
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
}

struct CodexActivityPresentation: Equatable, Sendable {
    var items: [CodexActivityItem] = []
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
        var projected: [CodexActivityItem] = []
        for turn in Self.turns(in: state) {
            let entries = turn.value["items"].array
            let active = turn.value["status"].string == "inProgress"
            let input = Self.contentText(turn.value["params"]["input"])
            if !input.isEmpty, !entries.contains(where: { $0["type"].string == "userMessage" }) {
                projected.append(Self.item(id: "\(turn.key)/prompt", kind: .user, title: "Du", text: input))
            }
            for (index, entry) in entries.enumerated() {
                let id = "\(turn.key)/\(entry["id"].string ?? "item:\(index)")"
                let running = active && entry["status"].string == "inProgress"
                let failed = entry["status"].string == "failed" || entry["status"].string == "declined"
                switch entry["type"].string {
                case "userMessage":
                    projected.append(Self.item(id: id, kind: .user, title: "Du", text: Self.contentText(entry["content"])))
                case "steeringUserMessage":
                    projected.append(Self.item(id: id, kind: .user, title: "Du", text: Self.contentText(entry["input"])))
                case "agentMessage", "plan":
                    let completedAt = entry["id"].string.flatMap { turn.value["agentMessageCompletedAtMsById"][$0].number }
                    projected.append(Self.item(id: id, kind: .assistant, title: entry["type"].string == "plan" ? "Plan" : "Codex",
                                               text: entry["text"].string ?? "", running: active && index == entries.count - 1 && completedAt == nil))
                case "commandExecution":
                    let command = entry["command"].string ?? "Kommando"
                    let exitCode = entry["exitCode"].number.flatMap(Int.init(exactly:)).map { "Avslutningskod: \($0)" }
                    let output = [entry["aggregatedOutput"].string, exitCode].compactMap { $0 }.joined(separator: "\n")
                    projected.append(Self.item(id: id, kind: .tool, title: "Terminal", text: command, details: output,
                                               running: running, failed: failed || (entry["exitCode"].number ?? 0) != 0))
                case "mcpToolCall", "dynamicToolCall":
                    let name = [entry["server"].string ?? entry["namespace"].string, entry["tool"].string].compactMap { $0 }.joined(separator: ".")
                    let result = entry["type"].string == "mcpToolCall" ? entry["result"]["content"] : entry["contentItems"]
                    let textOutput = Self.contentText(result)
                    let output = textOutput.isEmpty ? Self.jsonText(entry["result"]["structuredContent"]) ?? "" : textOutput
                    let error = entry["error"]["message"].string
                    let details = [Self.jsonText(entry["arguments"]), output, error].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n\n")
                    projected.append(Self.item(id: id, kind: .tool, title: name.isEmpty ? "Verktyg" : name, text: output,
                                               details: details, running: running, failed: failed || error != nil || Self.isFalse(entry["success"]), linkSource: output))
                case "collabAgentToolCall":
                    projected.append(Self.item(id: id, kind: .tool, title: entry["tool"].string ?? "Agent", text: entry["prompt"].string ?? "",
                                               details: Self.jsonText(entry["agentsStates"]) ?? "", running: running, failed: failed))
                case "userInputResponse":
                    let questions = entry["questions"].array.compactMap { $0["question"].string }.joined(separator: "\n")
                    projected.append(Self.item(id: id, kind: .info, title: "Fråga till dig", text: questions, details: Self.jsonText(entry["answers"]) ?? ""))
                case "permissionRequest":
                    projected.append(Self.item(id: id, kind: .info, title: "Behörighet", text: entry["reason"].string ?? "Codex begär behörighet.",
                                               details: Self.jsonText(entry["permissions"]) ?? ""))
                case "fileChange":
                    let changes = entry["changes"].array
                    let paths = changes.compactMap { $0["path"].string }.joined(separator: "\n")
                    let diffs = changes.compactMap { $0["diff"].string }.joined(separator: "\n\n")
                    projected.append(Self.item(id: id, kind: .tool, title: "Filändringar", text: paths, details: diffs, running: running, failed: failed))
                case "webSearch":
                    projected.append(Self.item(id: id, kind: .tool, title: "Sökning", text: entry["query"].string ?? entry["action"]["query"].string ?? "",
                                               details: Self.jsonText(entry["action"]) ?? "", running: running))
                case "error":
                    projected.append(Self.item(id: id, kind: .info, title: "Fel", text: entry["message"].string ?? "Ett fel uppstod.",
                                               details: entry["additionalDetails"].string ?? "", failed: true))
                case "contextCompaction":
                    projected.append(Self.item(id: id, kind: .info, title: "Sammanfattar kontext", text: "", running: active && !Self.isTrue(entry["completed"])))
                case "reasoning":
                    // Only the public summary is rendered. The internal content field is not part of this view.
                    let summary = entry["summary"].array.compactMap(\.string).joined(separator: "\n")
                    if !summary.isEmpty { projected.append(Self.item(id: id, kind: .info, title: "Arbetsnotering", text: summary)) }
                default: break
                }
            }
            if turn.value["status"].string == "failed", let message = turn.value["error"]["message"].string,
               !entries.contains(where: { $0["type"].string == "error" }) {
                projected.append(Self.item(id: "\(turn.key)/error", kind: .info, title: "Fel", text: message, failed: true))
            }
        }
        // Only the presentation is windowed. The reducer must retain raw array indices for future patches.
        var bytes = 0
        var kept: [CodexActivityItem] = []
        for item in projected.reversed() {
            let size = item.text.utf8.count + item.details.utf8.count + item.title.utf8.count
            guard kept.count < 400, bytes + size <= 512 * 1_024 else { break }
            kept.append(item)
            bytes += size
        }
        items = kept.reversed()
        omittedItemCount = projected.count - kept.count
    }

    private static func item(id: String, kind: CodexActivityItem.Kind, title: String, text: String,
                             details: String = "", running: Bool = false, failed: Bool = false, linkSource: String? = nil) -> CodexActivityItem {
        let text = clipped(text)
        let details = clipped(details)
        return CodexActivityItem(id: id, kind: kind, title: String(title.prefix(256)), text: text, details: details,
                                 links: links(in: linkSource ?? text + "\n" + details), isRunning: running, isError: failed)
    }

    private static func clipped(_ text: String) -> String {
        text.count > 32_768 ? String(text.prefix(32_768)) + "\n… Resten finns i Codex." : text
    }

    private static func contentText(_ value: CodexJSON) -> String {
        value.array.compactMap { part in
            switch part["type"].string {
            case "text", "inputText": return part["text"].string
            case "image", "inputImage", "localImage": return "[Bild]"
            case "resource_link": return part["uri"].string
            default: return nil
            }
        }.joined(separator: "\n")
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
        let source = text as NSString
        var seen: Set<String> = []
        return regex.matches(in: text, range: NSRange(location: 0, length: source.length)).compactMap { match in
            let markdown = match.range(at: 2).location != NSNotFound
            let target = source.substring(with: markdown ? match.range(at: 2) : match.range)
            let title = markdown ? source.substring(with: match.range(at: 1)) : target
            let url: URL?
            if target.hasPrefix("/") { url = URL(fileURLWithPath: target) }
            else { url = URL(string: target) }
            guard let url, ["http", "https", "codex", "file"].contains(url.scheme?.lowercased() ?? ""),
                  seen.insert(url.absoluteString).inserted else { return nil }
            return CodexActivityLink(title: title, url: url)
        }
    }
}

enum CodexStreamResult: Equatable {
    case applied, ignored, resync(String), unavailable(String)
}

struct CodexActivityStream {
    private(set) var state: CodexJSON?
    private(set) var owner: String?
    private(set) var revision: Int?
    private var displayRevision = 0
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
            return .resync("Codex skickade en ogiltig revision.")
        }
        if retiredOwners.contains(incomingOwner) { return .ignored }
        switch change["type"].string {
        case "snapshot":
            if owner == incomingOwner, let revision, nextRevision <= revision { return .ignored }
            let snapshot = change["conversationState"]
            guard case .object = snapshot else { return .resync("Codex skickade en ogiltig snapshot.") }
            guard Self.fits(snapshot, budget: maximumBytes) else {
                return .unavailable("Tråden är för stor för livevyn. Läs hela tråden i Codex.")
            }
            if let owner, owner != incomingOwner {
                retiredOwners.append(owner)
                retiredOwners = Array(retiredOwners.suffix(8))
            }
            state = snapshot
        case "patches":
            guard owner == incomingOwner, let revision, var updated = state else {
                return .resync("Väntar på en aktuell snapshot från Codex.")
            }
            if nextRevision <= revision { return .ignored }
            guard Self.integer(change["baseRevision"]) == revision else {
                return .resync("Aktivitet saknas mellan två uppdateringar. Hämtar om tråden.")
            }
            guard case .array(let patches) = change["patches"], patches.count <= 10_000 else {
                return .resync("Codex skickade en ogiltig uppdatering.")
            }
            do {
                for patch in patches { updated = try Self.applying(patch, to: updated) }
            } catch { return .resync("Codex uppdatering kunde inte tillämpas. Hämtar om tråden.") }
            guard case .object = updated else { return .resync("Codex skickade en ogiltig snapshot.") }
            guard Self.fits(updated, budget: maximumBytes) else { return .unavailable("Tråden är för stor för livevyn. Läs hela tråden i Codex.") }
            state = updated
        default: return .resync("Codex skickade en okänd typ av uppdatering.")
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
