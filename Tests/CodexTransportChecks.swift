@testable import SmoolChecksSupport
import Darwin
import Foundation

private struct CheckFailure: Error, CustomStringConvertible {
    let description: String
}

private final class Deliveries: @unchecked Sendable {
    private let lock = NSLock()
    private var messages: [CodexJSON] = []
    private var acknowledgments: [@Sendable () -> Void] = []
    private var disconnects = 0
    private var disconnectTime: ContinuousClock.Instant?

    var count: Int { lock.withLock { messages.count } }
    var disconnectCount: Int { lock.withLock { disconnects } }
    var disconnectedAt: ContinuousClock.Instant? { lock.withLock { disconnectTime } }
    var sequences: [Int] { lock.withLock { messages.compactMap { $0["sequence"].number.map(Int.init) } } }
    var firstText: String? { lock.withLock { messages.first?["text"].string } }

    func receive(_ message: CodexJSON, acknowledge: @escaping @Sendable () -> Void) {
        lock.withLock {
            messages.append(message)
            acknowledgments.append(acknowledge)
        }
    }

    func disconnect() {
        lock.withLock {
            disconnects += 1
            disconnectTime = .now
        }
    }

    func acknowledge(_ index: Int) {
        let acknowledgment = lock.withLock { acknowledgments[index] }
        acknowledgment()
    }
}

@main
struct CodexTransportChecks {
    private static let text = "Förklara ändringen.\nKeep \"quotes\", åäö and 🦋 intact."

    static func main() async throws {
        if CommandLine.arguments.dropFirst().first == "fixture" {
            try runFixture(Array(CommandLine.arguments.dropFirst(2)))
            return
        }

        for socket in [false, true] {
            try await checkFraming(socket: socket)
            try await checkBackpressure(socket: socket)
            try await checkReleaseWithoutACK(socket: socket)
            try await checkInvalidFrame(socket: socket, mode: "invalid-json")
            try await checkInvalidFrame(socket: socket, mode: "oversize")
        }
        try await checkInvalidFrame(socket: true, mode: "zero-header")
        print("Codex transport checks passed: stdio/socket framing, ACK order, bounded reads, cancellation and frame limits.")
    }

    private static func checkFraming(socket: Bool) async throws {
        let fixture = try await Fixture(socket: socket, mode: "framing")
        defer { fixture.close() }
        let deliveries = Deliveries()
        let transport = fixture.transport(deliveries)
        defer { transport.close() }
        try await transport.start()

        try await wait("partial frame") { fixture.progress == "partial" }
        try require(deliveries.count == 0, "A partial header or line must not be delivered.")
        try await wait("first complete frame") { deliveries.count == 1 }
        try await Task.sleep(for: .milliseconds(80))
        try require(deliveries.count == 1, "Coalesced frames must wait for the previous ACK.")
        try require(deliveries.disconnectCount == 0, "An exited fixture must not discard its unacknowledged output.")
        try require(deliveries.firstText == text, "Partial reads must preserve multiline Unicode content.")

        deliveries.acknowledge(0)
        try await wait("second frame") { deliveries.count == 2 }
        deliveries.acknowledge(0)
        deliveries.acknowledge(0)
        try await Task.sleep(for: .milliseconds(80))
        try require(deliveries.count == 2, "Repeated or stale ACKs must not release another delivery.")
        deliveries.acknowledge(1)
        try await wait("third frame") { deliveries.count == 3 }
        try require(deliveries.sequences == [1, 2, 3], "Frames must preserve their wire order.")
        deliveries.acknowledge(2)
        try await wait("EOF after all buffered frames") { deliveries.disconnectCount == 1 }
    }

    private static func checkBackpressure(socket: Bool) async throws {
        let fixture = try await Fixture(socket: socket, mode: "flood")
        defer { fixture.close() }
        let deliveries = Deliveries()
        let transport = fixture.transport(deliveries)
        defer { transport.close() }
        try await transport.start()
        try await wait("first flood frame") { deliveries.count == 1 }
        try await Task.sleep(for: .milliseconds(300))

        let completedFrames = Int(fixture.progress) ?? 0
        try require(completedFrames <= 2, "Reading must stop without ACK; the fixture wrote \(completedFrames) MiB.")
        try require(deliveries.count == 1, "Only one decoded delivery may be outstanding.")
        let start = ContinuousClock.now
        transport.close()
        try await wait("close without ACK", timeout: .seconds(1)) { deliveries.disconnectCount == 1 }
        let latency = start.duration(to: deliveries.disconnectedAt!)
        try require(latency < .seconds(1), "Closing must not wait for consumer ACK.")
        deliveries.acknowledge(0)
        transport.close()
        try await Task.sleep(for: .milliseconds(80))
        try require(deliveries.count == 1 && deliveries.disconnectCount == 1, "A late ACK cannot restart a closed transport.")
        let milliseconds = Double(latency.components.seconds) * 1_000 + Double(latency.components.attoseconds) / 1e15
        print("\(socket ? "Socket" : "Stdio") flood: \(completedFrames) of 96 MiB completed before ACK; close callback in \(String(format: "%.3f", milliseconds)) ms.")
    }

    private static func checkReleaseWithoutACK(socket: Bool) async throws {
        let fixture = try await Fixture(socket: socket, mode: "flood")
        defer { fixture.close() }
        let deliveries = Deliveries()
        var transport: CodexTransport? = fixture.transport(deliveries)
        try await transport?.start()
        try await wait("delivery before release") { deliveries.count == 1 }
        transport = nil
        // Releasing a suspended DispatchSource without balancing suspension crashes the process.
        try await Task.sleep(for: .milliseconds(80))
        deliveries.acknowledge(0)
        try require(deliveries.count == 1, "Release must discard buffered data and late ACKs.")
    }

    private static func checkInvalidFrame(socket: Bool, mode: String) async throws {
        let fixture = try await Fixture(socket: socket, mode: mode)
        defer { fixture.close() }
        let deliveries = Deliveries()
        let transport = fixture.transport(deliveries)
        defer { transport.close() }
        try await transport.start()
        try await wait("reject \(mode)", timeout: .seconds(10)) { deliveries.disconnectCount == 1 }
        try require(deliveries.count == 0, "Invalid or oversized frames must close without delivery.")
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw CheckFailure(description: message) }
    }

    private static func wait(_ description: String, timeout: Duration = .seconds(5), until condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while !condition() {
            try require(ContinuousClock.now < deadline, "Timed out waiting for \(description).")
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    /// Each peer runs in this test executable. No installed Codex or real thread is contacted.
    private final class Fixture {
        let directory: URL
        let socket: Bool
        let process: Process?
        var progress: String { (try? String(contentsOf: directory.appendingPathComponent("progress"), encoding: .utf8)) ?? "" }

        init(socket: Bool, mode: String) async throws {
            self.socket = socket
            directory = URL(fileURLWithPath: "/tmp/smool-transport-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let executable = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.path
            if socket {
                let peer = Process()
                process = peer
                peer.executableURL = URL(fileURLWithPath: executable)
                peer.arguments = ["fixture", "socket", mode, directory.path]
                peer.standardOutput = FileHandle.nullDevice
                try peer.run()
                try await CodexTransportChecks.wait("fixture socket") { self.progress == "ready" }
            } else {
                process = nil
                func quote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
                let script = "#!/bin/sh\nexec \(quote(executable)) fixture stdio \(quote(mode)) \(quote(directory.path))\n"
                let url = directory.appendingPathComponent("fixture")
                try script.write(to: url, atomically: true, encoding: .utf8)
                try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
            }
        }

        func transport(_ deliveries: Deliveries) -> CodexTransport {
            let endpoint: CodexTransport.Endpoint = socket
                ? .desktop(directory.appendingPathComponent("ipc.sock").path)
                : .appServer(directory.appendingPathComponent("fixture").path)
            return CodexTransport(endpoint: endpoint, receive: { deliveries.receive($0, acknowledge: $1) }, disconnected: { deliveries.disconnect() })
        }

        func close() {
            if let process, process.isRunning { process.terminate() }
            try? FileManager.default.removeItem(at: directory)
        }
    }

    private static func runFixture(_ arguments: [String]) throws {
        let socket = arguments[0] == "socket"
        let mode = arguments[1]
        let directory = URL(fileURLWithPath: arguments[2])
        let progress = directory.appendingPathComponent("progress")
        signal(SIGPIPE, SIG_IGN)
        let descriptor: Int32
        if socket {
            let listener = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
            try require(listener >= 0, "Could not create fixture socket.")
            defer { Darwin.close(listener) }
            var address = sockaddr_un()
            address.sun_family = sa_family_t(AF_UNIX)
            address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
            let bytes = Array(directory.appendingPathComponent("ipc.sock").path.utf8CString)
            withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes.map { UInt8(bitPattern: $0) }) }
            let bound = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(listener, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
            }
            try require(bound == 0 && listen(listener, 1) == 0, "Could not bind fixture socket: \(String(cString: strerror(errno))).")
            try "ready".write(to: progress, atomically: true, encoding: .utf8)
            descriptor = accept(listener, nil, nil)
            try require(descriptor >= 0, "Could not accept fixture connection.")
        } else {
            descriptor = STDOUT_FILENO
        }
        defer { Darwin.close(descriptor) }

        func write(_ data: Data) -> Bool {
            data.withUnsafeBytes { bytes in
                var offset = 0
                while offset < bytes.count {
                    let written = Darwin.write(descriptor, bytes.baseAddress! + offset, bytes.count - offset)
                    if written < 0, errno == EINTR { continue }
                    guard written > 0 else { return false }
                    offset += written
                }
                return true
            }
        }

        func frame(_ payload: Data) -> Data {
            guard socket else { return payload + Data([10]) }
            var size = UInt32(payload.count).littleEndian
            return withUnsafeBytes(of: &size) { Data($0) } + payload
        }

        switch mode {
        case "framing":
            let messages = try (1...3).map { sequence in
                frame(try JSONEncoder().encode(CodexJSON.object(["sequence": .number(Double(sequence)), "text": .string(text)])))
            }
            guard write(Data(messages[0].prefix(2))) else { return }
            try "partial".write(to: progress, atomically: true, encoding: .utf8)
            Thread.sleep(forTimeInterval: 0.2)
            _ = write(Data(messages[0].dropFirst(2)) + messages[1] + messages[2])
        case "flood":
            let payload = frame(try JSONEncoder().encode(CodexJSON.object(["text": .string(String(repeating: "x", count: 1_024 * 1_024))])))
            for count in 1...96 {
                guard write(payload) else { return }
                try String(count).write(to: progress, atomically: true, encoding: .utf8)
            }
        case "invalid-json":
            _ = write(frame(Data("not-json".utf8)))
        case "zero-header":
            _ = write(Data([0, 0, 0, 0]))
        case "oversize":
            if socket {
                var size = UInt32(64 * 1_024 * 1_024 + 1).littleEndian
                _ = withUnsafeBytes(of: &size) { write(Data($0)) }
            } else {
                let chunk = Data(repeating: 32, count: 64 * 1_024)
                for _ in 0..<1_025 {
                    guard write(chunk) else { return }
                }
                // Keep the writer open: rejection must come from the frame limit, not EOF.
                Thread.sleep(forTimeInterval: 15)
            }
        default:
            throw CheckFailure(description: "Unknown fixture mode.")
        }
    }
}
