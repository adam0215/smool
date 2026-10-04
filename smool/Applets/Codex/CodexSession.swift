import Foundation

struct CodexSessionOption: Equatable {
    let label: String
    let description: String
}

struct CodexSessionQuestion: Identifiable, Equatable {
    let id: String
    let header: String
    let question: String
    let isSecret: Bool
    let options: [CodexSessionOption]
}

enum CodexSessionDecision {
    case allowOnce, decline, cancel
    case answers([String: [String]])
}

struct CodexSessionRequest: Identifiable {
    enum Kind { case approval, questions, unsupported }
    let id: String
    let threadID: String
    let kind: Kind
    let title: String
    let message: String
    let questions: [CodexSessionQuestion]
    let allowsApproval: Bool
    let requestID: CodexJSON
    let method: String
    let params: CodexJSON

    init?(message: CodexJSON, threadID: String, item: CodexJSON = .null) {
        let requestID = message["id"]
        guard let id = requestID.string ?? requestID.number.map({ String($0) }),
              let method = message["method"].string else { return nil }
        self.id = id
        self.requestID = requestID
        self.method = method
        self.threadID = threadID
        let params = message["params"]
        self.params = params
        questions = params["questions"].array.compactMap { question in
            guard let id = question["id"].string, !id.isEmpty, let text = question["question"].string else { return nil }
            return CodexSessionQuestion(id: id, header: question["header"].string ?? "Question", question: text,
                                        isSecret: question["isSecret"].isTrue,
                                        options: question["options"].array.compactMap {
                                            guard let label = $0["label"].string else { return nil }
                                            return CodexSessionOption(label: label, description: $0["description"].string ?? "")
                                        })
        }
        let decisions = params["availableDecisions"].array
        allowsApproval = (decisions.isEmpty || decisions.contains { $0.string == "accept" })
            && (method != "item/fileChange/requestApproval" || !item["changes"].array.isEmpty)
        switch method {
        case "item/commandExecution/requestApproval":
            kind = .approval
            if params["networkApprovalContext"]["host"].string != nil { title = "Allow network access?" }
            else { title = params["kind"].string == "writeStdin" ? "Allow terminal input?" : "Allow command?" }
            self.message = [params["reason"].string, params["command"].string,
                            params["cwd"].string.map { "Folder: \($0)" },
                            Self.permissionsDescription(params["additionalPermissions"]),
                            params["networkApprovalContext"]["host"].string.map {
                                "Network: \(params["networkApprovalContext"]["protocol"].string ?? "") \($0)"
                            }]
                .compactMap { $0 }.joined(separator: "\n\n")
        case "item/fileChange/requestApproval":
            kind = .approval
            title = "Allow file changes?"
            self.message = [params["reason"].string, params["grantRoot"].string.map { "Requested folder: \($0)" },
                            Self.fileChangesDescription(item["changes"])].compactMap { $0 }.joined(separator: "\n\n")
        case "item/permissions/requestApproval":
            kind = .approval
            title = "Allow permissions for this turn?"
            self.message = [params["reason"].string, params["cwd"].string.map { "Folder: \($0)" },
                            Self.permissionsDescription(params["permissions"])].compactMap { $0 }.joined(separator: "\n\n")
        case "item/tool/requestUserInput" where !questions.isEmpty && Set(questions.map(\.id)).count == questions.count:
            kind = .questions
            title = "Codex has a question"
            self.message = ""
        default:
            kind = .unsupported
            title = "This request needs Codex"
            self.message = "smool cannot complete this request (\(method)). Cancel the turn, then open the thread in Codex to continue."
        }
    }

    func response(for decision: CodexSessionDecision) -> CodexJSON? {
        switch decision {
        case .answers(let answers):
            guard kind == .questions, questions.allSatisfy({ question in
                let values = answers[question.id] ?? []
                return !values.isEmpty && values.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            }) else { return nil }
            return .object(["answers": .object(Dictionary(uniqueKeysWithValues: questions.map {
                ($0.id, .object(["answers": .array((answers[$0.id] ?? []).map(CodexJSON.string))]))
            }))])
        case .allowOnce, .decline, .cancel:
            guard kind == .approval else { return nil }
            if case .allowOnce = decision, !allowsApproval { return nil }
            if method == "item/permissions/requestApproval" {
                let permissions: CodexJSON
                if case .allowOnce = decision { permissions = params["permissions"] }
                else { permissions = .object([:]) }
                return .object(["permissions": permissions, "scope": .string("turn")])
            }
            let value: String
            switch decision {
            case .allowOnce: value = "accept"
            case .decline: value = "decline"
            default: value = "cancel"
            }
            return .object(["decision": .string(value)])
        }
    }

    private static func describe(_ json: CodexJSON) -> String? {
        if case .null = json { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(json)).flatMap { String(data: $0, encoding: .utf8) }
    }

    private static func fileChangesDescription(_ changes: CodexJSON) -> String? {
        let descriptions = changes.array.compactMap { change -> String? in
            guard let path = change["path"].string else { return describe(change) }
            let kind = change["kind"]["type"].string ?? "Change"
            return ["\(kind.capitalized): \(path)", change["diff"].string].compactMap { $0 }.joined(separator: "\n")
        }
        return descriptions.isEmpty ? nil : descriptions.joined(separator: "\n\n")
    }

    private static func permissionsDescription(_ permissions: CodexJSON) -> String? {
        if case .null = permissions { return nil }
        var lines: [String] = []
        if permissions["network"]["enabled"].isTrue { lines.append("Network access") }
        let files = permissions["fileSystem"]
        for access in ["read", "write"] {
            lines += files[access].array.compactMap(\.string).map { "\(access.capitalized): \($0)" }
        }
        for entry in files["entries"].array {
            let path = entry["path"]
            let target = path["path"].string ?? path["pattern"].string
                ?? path["value"]["kind"].string.map { kind in
                    let name = ["root": "Entire filesystem", "project_roots": "Project folders",
                                "tmpdir": "Temporary directory", "slash_tmp": "/tmp"][kind] ?? kind
                    return name + (path["value"]["subpath"].string.map { "/\($0)" } ?? "")
                }
            lines.append("\((entry["access"].string ?? "Access").capitalized): \(target ?? describe(path) ?? "Unknown path")")
        }
        return lines.isEmpty ? describe(permissions) : lines.joined(separator: "\n")
    }
}

extension CodexJSON {
    fileprivate var isTrue: Bool { if case .bool(true) = self { true } else { false } }
}

/// Own the first turn until it ends. An empty thread cannot be resumed by another app-server.
@MainActor
final class CodexSession {
    let client: CodexClient
    let threadID: String
    private(set) var requests: [CodexSessionRequest] = []
    private(set) var turnID: String?
    private(set) var isRunning = false
    private(set) var hasStarted = false
    private(set) var isSubmitting = false
    private(set) var error: String?
    private var items: [CodexJSON] = []
    private var hooks: [CodexJSON] = []
    private var turnStatus = "completed"
    private var revision = 0
    var onChange: (() -> Void)?
    var onFinish: (() -> Void)?

    init(threadID: String, client: CodexClient) {
        self.threadID = threadID
        self.client = client
        client.onMessage = { [weak self] in self?.receive($0) }
        client.onDisconnect = { [weak self] in
            guard let self else { return }
            self.error = "Codex disconnected. The draft and last activity are saved. Open the thread in Codex to check its status."
            self.isRunning = false
            self.turnStatus = "failed"
            self.requests.removeAll()
            self.onChange?()
            self.onFinish?()
        }
    }

    var state: CodexJSON {
        .object([
            "threadRuntimeStatus": .object(["type": .string(isRunning ? "active" : "idle")]),
            "requests": .array(requests.map { .object(["id": .string($0.id), "method": .string($0.method)]) }),
            "turns": .array([.object([
                "turnId": .string(turnID ?? "starting"), "status": .string(turnStatus),
                "items": .array(items), "hookRuns": .array(hooks),
                "error": error.map { .object(["message": .string($0)]) } ?? .null
            ])])
        ])
    }

    var presentation: CodexActivityPresentation { CodexActivityPresentation(state: state, revision: revision) }

    func send(_ text: String) async throws {
        guard !isSubmitting else { throw CodexConnectionError(message: "Codex is still submitting this message.") }
        isSubmitting = true
        defer {
            isSubmitting = false
            if hasStarted, !isRunning { onFinish?() }
        }
        let input: CodexJSON = .array([.object(["type": .string("text"), "text": .string(text), "text_elements": .array([])])])
        if isRunning, let turnID {
            _ = try await client.request("turn/steer", params: .object([
                "threadId": .string(threadID), "expectedTurnId": .string(turnID), "input": input
            ]))
        } else {
            let response = try await client.request("turn/start", params: .object([
                "threadId": .string(threadID), "input": input
            ]))
            guard let id = response["turn"]["id"].string else {
                throw CodexConnectionError(message: "Codex did not confirm the first turn. Check the thread before retrying.")
            }
            // Notifications can finish a very short turn before the response arrives.
            if !hasStarted { beginTurn(response["turn"], id: id) }
        }
    }

    func cancel() async throws {
        guard let turnID, isRunning else { return }
        _ = try await client.request("turn/interrupt", params: .object([
            "threadId": .string(threadID), "turnId": .string(turnID)
        ]))
    }

    func respond(to request: CodexSessionRequest, decision: CodexSessionDecision) throws {
        guard requests.contains(where: { $0.id == request.id }) else { return }
        if let response = request.response(for: decision) {
            try client.respond(to: request.requestID, result: response)
            requests.removeAll { $0.id == request.id }
            changed()
        }
    }

    func receive(_ message: CodexJSON) {
        let params = message["params"]
        if let id = params["threadId"].string, id != threadID { return }
        guard let method = message["method"].string else { return }
        if message.object["id"] != nil {
            let item = items.first { $0["id"].string == params["itemId"].string } ?? .null
            if let request = CodexSessionRequest(message: message, threadID: threadID, item: item),
               !requests.contains(where: { $0.id == request.id }) {
                requests.append(request)
                changed()
            }
            return
        }
        switch method {
        case "turn/started":
            guard let id = params["turn"]["id"].string else { return }
            beginTurn(params["turn"], id: id)
        case "turn/completed":
            guard params["turn"]["id"].string == turnID else { return }
            turnStatus = params["turn"]["status"].string ?? "completed"
            error = params["turn"]["error"]["message"].string
            isRunning = false
            requests.removeAll()
            changed()
            if !isSubmitting { onFinish?() }
        case "item/started", "item/completed":
            var item = params["item"].object
            guard let id = item["id"]?.string else { return }
            item["completed"] = .bool(method == "item/completed")
            if method == "item/started", item["status"] == nil { item["status"] = .string("inProgress") }
            if item["type"]?.string == "reasoning" { item["content"] = nil }
            store(.object(item), id: id)
            changed()
        case "item/agentMessage/delta", "item/plan/delta", "item/commandExecution/outputDelta", "item/reasoning/summaryTextDelta":
            guard let id = params["itemId"].string, let index = items.firstIndex(where: { $0["id"].string == id }) else { return }
            var item = items[index].object
            let delta = params["delta"].string ?? ""
            if method == "item/reasoning/summaryTextDelta" {
                let part = Int(params["summaryIndex"].number ?? 0)
                guard (0..<32).contains(part) else { return }
                var summary = item["summary"]?.array ?? []
                while summary.count <= part { summary.append(.string("")) }
                summary[part] = .string(String(((summary[part].string ?? "") + delta).suffix(8_192)))
                item["summary"] = .array(summary)
            } else {
                let key = method == "item/commandExecution/outputDelta" ? "aggregatedOutput" : "text"
                item[key] = .string(String(((item[key]?.string ?? "") + delta).suffix(8_192)))
            }
            items[index] = .object(item)
            changed()
        case "item/mcpToolCall/progress":
            guard let id = params["itemId"].string, let index = items.firstIndex(where: { $0["id"].string == id }) else { return }
            var item = items[index].object
            item["result"] = .object(["content": .array([.object(["type": .string("text"), "text": params["message"]])])])
            items[index] = .object(item)
            changed()
        case "turn/plan/updated":
            store(.object(["id": .string("plan"), "type": .string("todo-list"),
                           "explanation": params["explanation"], "plan": params["plan"]]), id: "plan")
            changed()
        case "hook/started", "hook/completed":
            var values = params["run"].object
            values["entries"] = .array((values["entries"]?.array ?? []).suffix(32).map { entry in
                .object(["kind": entry["kind"], "text": .string(String((entry["text"].string ?? "").suffix(8_192)))])
            })
            let run = CodexJSON.object(values)
            guard let id = run["id"].string else { return }
            let hook: CodexJSON = .object(["id": .string(id), "run": run])
            if let index = hooks.firstIndex(where: { $0["id"].string == id }) { hooks[index] = hook }
            else { hooks.append(hook); hooks = Array(hooks.suffix(32)) }
            changed()
        case "serverRequest/resolved":
            let id = params["requestId"].string ?? params["requestId"].number.map { String($0) }
            requests.removeAll { $0.id == id }
            changed()
        case "error":
            guard !params["willRetry"].isTrue else { return }
            error = params["error"]["message"].string ?? "Codex reported an error."
            changed()
        default: break // Private reasoning content is deliberately never retained.
        }
    }

    private func beginTurn(_ turn: CodexJSON, id: String) {
        if turnID != id { items.removeAll(); hooks.removeAll() }
        turnID = id
        isRunning = true
        hasStarted = true
        turnStatus = "inProgress"
        error = nil
        for item in turn["items"].array {
            if let id = item["id"].string { store(item, id: id) }
        }
        changed()
    }

    private func store(_ item: CodexJSON, id: String) {
        var value = item.object
        if value["type"]?.string == "reasoning" { value["content"] = nil }
        for key in ["text", "aggregatedOutput", "revisedPrompt", "command", "path", "tool", "server"] {
            if let text = value[key]?.string { value[key] = .string(String(text.suffix(8_192))) }
        }
        if let bytes = try? JSONEncoder().encode(CodexJSON.object(value)), bytes.count > 65_536 {
            value = value.filter { ["id", "type", "status", "completed", "text", "command", "tool", "server", "path"].contains($0.key) }
        }
        if let index = items.firstIndex(where: { $0["id"].string == id }) { items[index] = .object(value) }
        else { items.append(.object(value)); items = Array(items.suffix(128)) }
    }

    private func changed() {
        revision += 1
        onChange?()
    }
}
