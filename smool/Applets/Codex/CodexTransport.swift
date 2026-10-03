import Darwin
import Foundation

/// Owns only a reader connection or a read-only app-server process, never the desktop server.
/// All file descriptors, framing and process work stay on this serial queue.
final class CodexTransport: @unchecked Sendable {
    enum Endpoint: Sendable { case desktop(String), appServer(String) }
    private let queue = DispatchQueue(label: "smool.codex.transport", qos: .utility)
    private let endpoint: Endpoint
    private let receive: @Sendable (CodexJSON, @escaping @Sendable () -> Void) -> Void
    private let deliverySlots = DispatchSemaphore(value: 1)
    private let disconnected: @Sendable () -> Void
    private var reader: FileHandle?
    private var writer: FileHandle?
    private var process: Process?
    private var buffer = Data()
    private var closed = false

    init(endpoint: Endpoint, receive: @escaping @Sendable (CodexJSON, @escaping @Sendable () -> Void) -> Void, disconnected: @escaping @Sendable () -> Void) {
        self.endpoint = endpoint
        self.receive = receive
        self.disconnected = disconnected
    }

    func start() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            queue.async { [self] in
                do {
                    switch self.endpoint {
                    case .desktop(let path): try self.connectSocket(path)
                    case .appServer(let path): try self.launchServer(path)
                    }
                    self.reader?.readabilityHandler = { [weak self] handle in
                        let data = handle.availableData
                        guard let self else { return }
                        self.queue.async { self.read(data) }
                    }
                    continuation.resume()
                } catch {
                    self.closeOnQueue()
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func send(_ message: CodexJSON) throws {
        let data = try JSONEncoder().encode(message)
        queue.async {
            guard !self.closed, let writer = self.writer else { return }
            var frame = Data()
            switch self.endpoint {
            case .desktop:
                var size = UInt32(data.count).littleEndian
                withUnsafeBytes(of: &size) { frame.append(contentsOf: $0) }
                frame.append(data)
            case .appServer:
                frame = data
                frame.append(10)
            }
            do { try writer.write(contentsOf: frame) }
            catch { self.closeOnQueue() }
        }
    }

    func close() { queue.async { self.closeOnQueue() } }

    private func connectSocket(_ path: String) throws {
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw CodexConnectionError(message: "Kunde inte ansluta till Codex.") }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8CString)
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
            Darwin.close(descriptor)
            throw CodexConnectionError(message: "Sökvägen till Codex är för lång.")
        }
        withUnsafeMutableBytes(of: &address.sun_path) { destination in
            destination.copyBytes(from: bytes.map { UInt8(bitPattern: $0) })
        }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else {
            Darwin.close(descriptor)
            throw CodexConnectionError(message: "Öppna Codex för att ansluta till dina aktiva trådar.")
        }
        var noSignal: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
        var timeout = timeval(tv_sec: 8, tv_usec: 0)
        setsockopt(descriptor, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        reader = handle
        writer = handle
    }

    private func launchServer(_ path: String) throws {
        let process = Process()
        let input = Pipe(), output = Pipe()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["app-server", "--listen", "stdio://"]
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self] _ in
            guard let self else { return }
            self.queue.async { self.closeOnQueue() }
        }
        try process.run()
        self.process = process
        reader = output.fileHandleForReading
        writer = input.fileHandleForWriting
    }

    private func read(_ data: Data) {
        guard !closed else { return }
        guard !data.isEmpty else { closeOnQueue(); return }
        buffer.append(data)
        // Bound memory even if a newer desktop emits an incompatible frame.
        guard buffer.count <= 64 * 1_024 * 1_024 else { closeOnQueue(); return }
        while true {
            let payload: Data
            switch endpoint {
            case .desktop:
                guard buffer.count >= 4 else { return }
                let count = Int(buffer.prefix(4).enumerated().reduce(UInt32(0)) { $0 | UInt32($1.element) << (8 * $1.offset) })
                guard count > 0, count <= 64 * 1_024 * 1_024 else { closeOnQueue(); return }
                guard buffer.count >= count + 4 else { return }
                payload = Data(buffer.dropFirst(4).prefix(count))
                buffer.removeFirst(count + 4)
            case .appServer:
                guard let newline = buffer.firstIndex(of: 10) else { return }
                payload = Data(buffer[..<newline])
                buffer.removeSubrange(...newline)
            }
            guard let value = try? JSONDecoder().decode(CodexJSON.self, from: payload) else { closeOnQueue(); return }
            // Bound queued actor work without dropping patches or changing their order.
            deliverySlots.wait()
            receive(value) { [deliverySlots] in deliverySlots.signal() }
        }
    }

    private func closeOnQueue() {
        guard !closed else { return }
        closed = true
        reader?.readabilityHandler = nil
        try? reader?.close()
        if writer !== reader { try? writer?.close() }
        reader = nil
        writer = nil
        buffer.removeAll()
        if let process, process.isRunning { process.terminate() }
        process = nil
        disconnected()
    }
}
