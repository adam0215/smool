import Darwin
import Foundation

/// Owns only a reader connection or a read-only app-server process, never the desktop server.
/// All file descriptors, framing and process work stay on this serial queue.
final class CodexTransport: @unchecked Sendable {
    enum Endpoint: Sendable { case desktop(String), appServer(String) }
    private let queue = DispatchQueue(label: "smool.codex.transport", qos: .utility)
    private let endpoint: Endpoint
    private let receive: @Sendable (CodexJSON, @escaping @Sendable () -> Void) -> Void
    private let disconnected: @Sendable () -> Void
    private static let maximumFrameSize = 64 * 1_024 * 1_024
    private var reader: FileHandle?
    private var writer: FileHandle?
    private var readSource: (any DispatchSourceRead)?
    private var readingPaused = false
    private var pendingDelivery: UUID?
    private var process: Process?
    private var buffer = Data()
    private var newlineSearchOffset = 0
    private var closed = false

    init(endpoint: Endpoint, receive: @escaping @Sendable (CodexJSON, @escaping @Sendable () -> Void) -> Void, disconnected: @escaping @Sendable () -> Void) {
        self.endpoint = endpoint
        self.receive = receive
        self.disconnected = disconnected
    }

    deinit {
        readSource?.cancel()
        if readingPaused { readSource?.resume() }
        if let process, process.isRunning { process.terminate() }
    }

    func start() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            queue.async { [self] in
                do {
                    guard !self.closed, self.reader == nil else {
                        throw CodexConnectionError(message: "The Codex connection is closed.")
                    }
                    switch self.endpoint {
                    case .desktop(let path): try self.connectSocket(path)
                    case .appServer(let path): try self.launchServer(path)
                    }
                    self.startReading()
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
        guard descriptor >= 0 else { throw CodexConnectionError(message: "Could not connect to Codex.") }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8CString)
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
            Darwin.close(descriptor)
            throw CodexConnectionError(message: "The path to Codex is too long.")
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
            throw CodexConnectionError(message: "Open Codex to connect to your active threads.")
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
        try process.run()
        self.process = process
        reader = output.fileHandleForReading
        writer = input.fileHandleForWriting
    }

    private func startReading() {
        guard let reader else { return }
        let source = DispatchSource.makeReadSource(fileDescriptor: reader.fileDescriptor, queue: queue)
        source.setEventHandler { [weak self] in self?.readAvailable() }
        // Dispatch must stop monitoring the descriptor before it can be closed and reused.
        source.setCancelHandler { try? reader.close() }
        readSource = source
        source.resume()
    }

    private func readAvailable() {
        guard !closed, pendingDelivery == nil, let reader else { return }
        let capacity = min(64 * 1_024, Self.maximumFrameSize + 4 - buffer.count)
        guard capacity > 0 else { closeOnQueue(); return }
        var data = Data(count: capacity)
        let count = data.withUnsafeMutableBytes { bytes in
            Darwin.read(reader.fileDescriptor, bytes.baseAddress, capacity)
        }
        guard count > 0 else {
            if count < 0, errno == EINTR || errno == EAGAIN { return }
            closeOnQueue()
            return
        }
        data.count = count
        buffer.append(data)
        deliverBufferedMessage()
    }

    private func deliverBufferedMessage() {
        guard !closed, pendingDelivery == nil else { return }
        let payload: Data
        switch endpoint {
        case .desktop:
            guard buffer.count >= 4 else { return }
            let count = Int(buffer.prefix(4).enumerated().reduce(UInt32(0)) { $0 | UInt32($1.element) << (8 * $1.offset) })
            guard count > 0, count <= Self.maximumFrameSize else { closeOnQueue(); return }
            guard buffer.count >= count + 4 else { return }
            payload = Data(buffer.dropFirst(4).prefix(count))
            buffer.removeFirst(count + 4)
        case .appServer:
            let start = buffer.index(buffer.startIndex, offsetBy: newlineSearchOffset)
            guard let newline = buffer[start...].firstIndex(of: 10) else {
                newlineSearchOffset = buffer.count
                return
            }
            payload = Data(buffer[..<newline])
            guard payload.count <= Self.maximumFrameSize else { closeOnQueue(); return }
            buffer.removeSubrange(...newline)
            newlineSearchOffset = 0
        }
        guard let value = try? JSONDecoder().decode(CodexJSON.self, from: payload) else { closeOnQueue(); return }

        // Pause the descriptor itself, so an unacknowledged delivery cannot queue more bytes.
        if !readingPaused {
            readSource?.suspend()
            readingPaused = true
        }
        let delivery = UUID()
        pendingDelivery = delivery
        receive(value) { [weak self] in
            guard let self else { return }
            self.queue.async { self.acknowledge(delivery) }
        }
    }

    private func acknowledge(_ delivery: UUID) {
        guard !closed, pendingDelivery == delivery else { return }
        pendingDelivery = nil
        deliverBufferedMessage()
        if !closed, pendingDelivery == nil, readingPaused {
            readingPaused = false
            readSource?.resume()
        }
    }

    private func closeOnQueue() {
        guard !closed else { return }
        closed = true
        if let readSource {
            readSource.cancel()
            if readingPaused { readSource.resume() }
        } else {
            try? reader?.close()
        }
        readSource = nil
        readingPaused = false
        pendingDelivery = nil
        if writer !== reader { try? writer?.close() }
        reader = nil
        writer = nil
        buffer.removeAll()
        newlineSearchOffset = 0
        if let process, process.isRunning { process.terminate() }
        process = nil
        disconnected()
    }
}
