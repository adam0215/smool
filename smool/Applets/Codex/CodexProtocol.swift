import Foundation

/// A sendable JSON value keeps untyped protocol data at the transport boundary.
indirect enum CodexJSON: Codable, Sendable {
    case object([String: CodexJSON]), array([CodexJSON]), string(String), number(Double), bool(Bool), null

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([CodexJSON].self) { self = .array(value) }
        else { self = .object(try container.decode([String: CodexJSON].self)) }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    subscript(_ key: String) -> CodexJSON {
        guard case .object(let values) = self else { return .null }
        return values[key] ?? .null
    }

    var string: String? { if case .string(let value) = self { value } else { nil } }
    var number: Double? { if case .number(let value) = self { value } else { nil } }
    var array: [CodexJSON] { if case .array(let values) = self { values } else { [] } }
    var object: [String: CodexJSON] { if case .object(let values) = self { values } else { [:] } }
}

struct CodexConnectionError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// The desktop IPC is versioned separately from the public app-server API.
/// Keep its small, verified surface here so incompatibilities fail explicitly.
enum CodexDesktopProtocol {
    static let snapshotVersion = 11

    static func threadURL(_ threadID: String) -> URL? {
        guard UUID(uuidString: threadID) != nil else { return nil }
        return URL(string: "codex://threads/\(threadID)")
    }

    static func request(id: String, clientID: String, method: String, params: CodexJSON, owner: String? = nil, timeoutMilliseconds: Int = 8_000) -> CodexJSON {
        let version: Int
        switch method {
        case "thread-owner-discovery", "thread-follower-steer-turn": version = 1
        case "thread-follower-start-turn": version = 2
        default: version = 0
        }
        var request: [String: CodexJSON] = [
            "type": .string("request"), "requestId": .string(id),
            "sourceClientId": .string(clientID), "version": .number(Double(version)),
            "method": .string(method), "params": params, "timeoutMs": .number(Double(timeoutMilliseconds))
        ]
        if let owner { request["targetClientId"] = .string(owner) }
        return .object(request)
    }

    static func follow(_ threadID: String, clientID: String, following: Bool = true) -> CodexJSON {
        .object([
            "type": .string("broadcast"), "method": .string("thread-stream-following-changed"),
            "sourceClientId": .string(clientID), "version": .number(1),
            "params": .object(["conversationId": .string(threadID), "hostId": .string("local"), "following": .bool(following)])
        ])
    }

    static func steer(text: String, threadID: String, messageID: String) -> CodexJSON {
        .object([
            "conversationId": .string(threadID), "clientUserMessageId": .string(messageID),
            "input": .array([.object(["type": .string("text"), "text": .string(text), "text_elements": .array([])])]),
            "restoreMessage": .object([
                "id": .string(messageID), "text": .string(text),
                "createdAt": .number(Date.now.timeIntervalSince1970 * 1_000),
                "context": .object([
                    "prompt": .string(text), "addedFiles": .array([]), "fileAttachments": .array([]),
                    "ideContext": .null, "imageAttachments": .array([]), "workspaceRoots": .array([])
                ])
            ])
        ])
    }

    static func isInactiveTurnError(_ message: String, threadID: String) -> Bool {
        message == "Cannot steer conversation \(threadID) because its active turn already ended"
    }

    /// Let the owner resolve the active turn. Only an explicit rejection permits starting a new one.
    @MainActor
    static func deliver(
        text: String, threadID: String, messageID: String, owner: String,
        request: (String, CodexJSON, String) async throws -> CodexJSON
    ) async throws {
        let response: CodexJSON
        let turnID: String?
        do {
            response = try await request("thread-follower-steer-turn", steer(text: text, threadID: threadID, messageID: messageID), owner)
            turnID = response["result"]["result"]["turnId"].string
        } catch {
            guard isInactiveTurnError(error.localizedDescription, threadID: threadID) else { throw error }
            response = try await request("thread-follower-start-turn", turn(text: text, threadID: threadID, messageID: messageID), owner)
            turnID = response["result"]["result"]["turn"]["id"].string
        }
        guard response["resultType"].string == "success", response["handledByClientId"].string == owner, turnID != nil else {
            throw CodexConnectionError(message: "Codex did not confirm the message.")
        }
    }

    static func turn(text: String, threadID: String, messageID: String) -> CodexJSON {
        .object([
            "conversationId": .string(threadID),
            "turnStart": .object([
                "request": .object([
                    "threadId": .string(threadID), "clientUserMessageId": .string(messageID),
                    "input": .array([.object(["type": .string("text"), "text": .string(text), "text_elements": .array([])])])
                ]),
                "context": .object(["inheritThreadSettings": .bool(true)])
            ])
        ])
    }
}
