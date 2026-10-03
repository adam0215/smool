import Foundation
import Darwin

struct SystemMedia: Decodable, Sendable {
    let bundleIdentifier: String
    let appName: String
    let track: SpotifyTrack
    let artworkData: Data?
}

/// MediaRemote is private. Keep its version-dependent calls inside one subprocess.
/// MRNowPlayingRequest also works on macOS versions that restrict the older callbacks.
actor MediaBridge {
    enum Command: Int, Sendable {
        case togglePlayback = 2, nextTrack = 4, previousTrack = 5
    }

    private let runner = JavaScriptRunner()

    static let setup = """
    ObjC.import('Foundation');
    $.NSBundle.bundleWithPath('/System/Library/PrivateFrameworks/MediaRemote.framework').load;
    const request = $.NSClassFromString('MRNowPlayingRequest');
    """

    static let readScript = setup + """

    function run() {
        const item = request.localNowPlayingItem;
        if (!item || item.isNil()) return 'null';
        const info = ObjC.deepUnwrap(item.nowPlayingInfo);
        const client = request.localNowPlayingPlayerPath.client;
        const title = info.kMRMediaRemoteNowPlayingInfoTitle;
        if (!title) return 'null';
        const playing = !!request.localIsPlaying;
        const duration = info.kMRMediaRemoteNowPlayingInfoDuration || 0;
        let position = info.kMRMediaRemoteNowPlayingInfoElapsedTime || 0;
        const timestamp = Date.parse(info.kMRMediaRemoteNowPlayingInfoTimestamp);
        if (playing && Number.isFinite(timestamp)) {
            position += Math.max(0, (Date.now() - timestamp) / 1000);
        }
        let artwork = null;
        try {
            const data = item.nowPlayingInfo.objectForKey('kMRMediaRemoteNowPlayingInfoArtworkData');
            if (data && !data.isNil()) artwork = ObjC.unwrap(data.base64EncodedStringWithOptions(0));
        } catch (_) {}
        return JSON.stringify({
            artworkData: artwork,
            bundleIdentifier: ObjC.unwrap(client.bundleIdentifier) || '',
            appName: ObjC.unwrap(client.displayName) || '',
            track: {title: title, artist: info.kMRMediaRemoteNowPlayingInfoArtist || '',
                artwork: '', duration: duration, position: Math.min(duration || position, position), playing: playing}
        });
    }
    """

    func read() async throws -> SystemMedia? {
        let data = try await runner.run(Self.readScript)
        return try JSONDecoder().decode(SystemMedia?.self, from: data)
    }

    func send(_ command: Command, to bundleIdentifier: String) async throws -> Bool {
        // Encode the identifier as a JSON string, never interpolate it as executable code.
        let target = String(decoding: try JSONEncoder().encode(bundleIdentifier), as: UTF8.self)
        let script = Self.setup + """

        function run() {
            const client = request.localNowPlayingPlayerPath.client;
            if (!client || client.isNil() || ObjC.unwrap(client.bundleIdentifier) !== \(target)) return 'false';
            ObjC.bindFunction('MRMediaRemoteSendCommand', ['bool', ['int', 'id']]);
            return JSON.stringify(!!$.MRMediaRemoteSendCommand(\(command.rawValue), $.NSDictionary.dictionary));
        }
        """
        let data = try await runner.run(script)
        return try JSONDecoder().decode(Bool.self, from: data)
    }
}

/// Executes off the main actor, with bounded lifetime and cancellation on view dismissal.
actor JavaScriptRunner {
    func run(_ script: String) async throws -> Data {
        try Task.checkCancellation()
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-l", "JavaScript", "-e", script]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let timeout = DispatchWorkItem {
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 10, execute: timeout)
        defer { timeout.cancel() }
        let data = await withTaskCancellationHandler {
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return data
        } onCancel: {
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
        try Task.checkCancellation()
        guard process.terminationStatus == 0 else {
            throw CocoaError(process.terminationReason == .uncaughtSignal ? .userCancelled : .executableRuntimeMismatch)
        }
        return data
    }
}
