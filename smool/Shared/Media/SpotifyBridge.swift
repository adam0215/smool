import AppKit
import Darwin

/// Spotify's scripting dictionary exposes playback, but no playlist library.
/// A separate process keeps Apple Events and their timeout off the main thread.
actor SpotifyBridge {
    enum Command: Sendable {
        case togglePlayback, nextTrack, playlist(String)
    }

    struct Response: Decodable, Sendable {
        let status: String
        let track: MediaTrack?
        let code: Int?
        let message: String?

        var errorDescription: String {
            switch code {
            case -1712:
                "Spotify verkar ha hängt sig. Starta om Spotify och försök igen."
            case -1743:
                "Tillåt smool att styra Spotify under Integritet och säkerhet → Automation."
            default:
                "Kunde inte läsa svaret från Spotify. Försök igen."
            }
        }
    }

    static func script(for command: Command? = nil) throws -> String {
        var action = ""
        switch command {
        case .togglePlayback: action = "spotify.playpause();"
        case .nextTrack: action = "spotify.nextTrack();"
        case .playlist(let uri):
            guard let validated = SpotifyPlaylist.uri(from: uri) else { throw CocoaError(.validationMissingMandatoryProperty) }
            action = "spotify.playTrack('\(validated)');"
        case nil: break
        }
        if command != nil { action += " return JSON.stringify({status: 'success'});" }
        return """
        function run() {
            try {
                const spotify = Application('com.spotify.client');
                if (!spotify.running()) return JSON.stringify({status: 'notRunning'});
                \(action)
                const playerState = spotify.playerState();
                if (playerState === 'stopped') return JSON.stringify({status: 'idle'});
                const track = spotify.currentTrack();
                if (!track || !track.name()) return JSON.stringify({status: 'idle'});
                let artwork = '';
                try { artwork = track.artworkUrl() || ''; } catch (_) {}
                return JSON.stringify({status: 'ready', track: {
                    title: track.name(), artist: track.artist(), artwork: artwork,
                    duration: track.duration() / 1000, position: spotify.playerPosition(),
                    playing: playerState === 'playing'
                }});
            } catch (error) {
                if (error.errorNumber === -1728) return JSON.stringify({status: 'idle'});
                return JSON.stringify({status: 'error', code: error.errorNumber || 0, message: String(error.message || error)});
            }
        }
        """
    }

    private let media = MediaBridge()
    private let runner = JavaScriptRunner()
    private var systemOnlyProcess: pid_t?

    func run(_ command: Command? = nil) async throws -> Response {
        try Task.checkCancellation()
        // Spotify's Apple Events can stop responding while macOS still has current playback.
        // Prefer the system player only when its identity is actually Spotify.
        if let current = try? await media.read(), current.bundleIdentifier == "com.spotify.client" {
            switch command {
            case nil:
                // Preserve Spotify's artwork when scripting works. Once a process times out,
                // use the system snapshot until Spotify restarts instead of waiting every poll.
                let process = await MainActor.run {
                    NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").first?.processIdentifier
                }
                if let process, systemOnlyProcess != process {
                    if let response = try? await spotifyResponse(nil) {
                        if response.status == "ready" { return response }
                        if response.status == "error" { systemOnlyProcess = process }
                    }
                }
                try Task.checkCancellation()
                return Response(status: "ready", track: current.track, code: nil, message: nil)
            case .togglePlayback, .nextTrack:
                let action: MediaBridge.Command = if case .nextTrack = command { .nextTrack } else { .togglePlayback }
                let sent = try await media.send(action, to: "com.spotify.client")
                return Response(status: sent ? "success" : "error", track: nil, code: nil, message: nil)
            case .playlist: break
            }
        }
        return try await spotifyResponse(command)
    }

    private func spotifyResponse(_ command: Command?) async throws -> Response {
        try Task.checkCancellation()
        do {
            let data = try await runner.run(Self.script(for: command))
            return try JSONDecoder().decode(Response.self, from: data)
        } catch let error as CocoaError where error.code == .userCancelled && !Task.isCancelled {
            return Response(status: "error", track: nil, code: -1712, message: nil)
        }
    }
}
