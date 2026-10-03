import Foundation

@MainActor
final class CodexClient {
    private let desktop: Bool
    private var transport: CodexTransport?
    private var clientID = "initializing-client"
    private var pending: [String: CheckedContinuation<CodexJSON, any Error>] = [:]
    private var timeouts: [String: Task<Void, Never>] = [:]
    private var generation = UUID()
    private var connecting: Task<Void, any Error>?
    private var connectionAttempt: UUID?
    var onMessage: ((CodexJSON) -> Void)?
    var onDisconnect: (() -> Void)?
    private(set) var isConnected = false

    init(desktop: Bool) { self.desktop = desktop }

    func connect() async throws {
        guard !isConnected else { return }
        if let connecting { return try await connecting.value }
        let attempt = UUID()
        let task = Task { try await establishConnection() }
        connecting = task
        connectionAttempt = attempt
        defer { if connectionAttempt == attempt { connecting = nil; connectionAttempt = nil } }
        try await withTaskCancellationHandler {
            try await task.value
        } onCancel: { task.cancel() }
    }

    private func establishConnection() async throws {
        let endpoint: CodexTransport.Endpoint
        if desktop {
            endpoint = .desktop(Self.codexHome.appendingPathComponent("ipc/ipc.sock").path)
        } else {
            guard let executable = Self.executable else {
                throw CodexConnectionError(message: "Install Codex to view threads and usage.")
            }
            endpoint = .appServer(executable)
        }
        let generation = UUID()
        self.generation = generation
        let transport = CodexTransport(endpoint: endpoint) { [weak self] value, delivered in
            Task { @MainActor in
                defer { delivered() }
                guard let self, self.generation == generation else { return }
                self.receive(value)
            }
        } disconnected: { [weak self] in
            Task { @MainActor in
                guard let self, self.generation == generation else { return }
                self.disconnect()
                self.onDisconnect?()
            }
        }
        self.transport = transport
        try await transport.start()
        guard self.generation == generation, !Task.isCancelled else {
            transport.close()
            throw CancellationError()
        }
        do {
            if desktop {
                let response = try await request("initialize", params: .object(["clientType": .string("smool")]))
                guard let id = response["result"]["clientId"].string else {
                    throw CodexConnectionError(message: "Codex uses an unsupported connection format.")
                }
                try Task.checkCancellation()
                guard self.generation == generation else { throw CancellationError() }
                clientID = id
            } else {
                _ = try await request("initialize", params: .object([
                    "clientInfo": .object(["name": .string("smool"), "title": .string("smool"), "version": .string("0.1")]),
                    "capabilities": .object(["experimentalApi": .bool(true)])
                ]))
                try transport.send(.object(["method": .string("initialized")]))
            }
            try Task.checkCancellation()
            guard self.generation == generation else { throw CancellationError() }
            isConnected = true
        } catch {
            if self.generation == generation { disconnect() }
            throw error
        }
    }

    func request(_ method: String, params: CodexJSON, owner: String? = nil, timeout: Duration = .seconds(12)) async throws -> CodexJSON {
        guard (isConnected || method == "initialize"), let transport else { throw CodexConnectionError(message: "The connection to Codex is closed.") }
        try Task.checkCancellation()
        let id = UUID().uuidString
        let milliseconds = Int(timeout.components.seconds * 1_000 + timeout.components.attoseconds / 1_000_000_000_000_000)
        let message = desktop
            ? CodexDesktopProtocol.request(id: id, clientID: clientID, method: method, params: params, owner: owner,
                                           timeoutMilliseconds: min(8_000, milliseconds))
            : .object(["id": .string(id), "method": .string(method), "params": params])
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pending[id] = continuation
                timeouts[id] = Task { [weak self] in
                    try? await Task.sleep(for: timeout)
                    guard !Task.isCancelled else { return }
                    self?.finish(id, result: .failure(CodexConnectionError(message: "Codex did not respond. Try connecting again.")))
                }
                do { try transport.send(message) }
                catch { finish(id, result: .failure(error)) }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.finish(id, result: .failure(CancellationError())) }
        }
    }

    @discardableResult
    func follow(_ id: String, following: Bool = true) -> Bool {
        guard isConnected, clientID != "initializing-client" else { return false }
        do { try transport?.send(CodexDesktopProtocol.follow(id, clientID: clientID, following: following)); return true }
        catch { return false }
    }

    func disconnect() {
        generation = UUID()
        connecting?.cancel()
        connecting = nil
        connectionAttempt = nil
        isConnected = false
        transport?.close()
        transport = nil
        clientID = "initializing-client"
        for id in Array(pending.keys) {
            finish(id, result: .failure(CodexConnectionError(message: "Disconnected from Codex.")))
        }
    }

    private func receive(_ message: CodexJSON) {
        let id = desktop ? message["requestId"].string : message["id"].string
        if let id, pending[id] != nil, !desktop || message["type"].string == "response" {
            if desktop, message["resultType"].string == "error" {
                finish(id, result: .failure(CodexConnectionError(message: message["error"].string ?? "Codex could not complete the action.")))
            } else if let error = message["error"]["message"].string {
                finish(id, result: .failure(CodexConnectionError(message: error)))
            } else {
                finish(id, result: .success(desktop ? message : message["result"]))
            }
        } else if desktop, message["type"].string == "client-discovery-request", let id {
            // This client observes threads; it never claims ownership or approval requests.
            try? transport?.send(.object([
                "type": .string("client-discovery-response"), "requestId": .string(id),
                "response": .object(["canHandle": .bool(false)])
            ]))
        } else { onMessage?(message) }
    }

    private func finish(_ id: String, result: Result<CodexJSON, any Error>) {
        timeouts.removeValue(forKey: id)?.cancel()
        pending.removeValue(forKey: id)?.resume(with: result)
    }

    static var codexHome: URL {
        if let path = ProcessInfo.processInfo.environment["CODEX_HOME"], !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
    }

    private static var executable: String? {
        let candidates = [
            "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex", "/usr/local/bin/codex",
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/codex").path
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}
