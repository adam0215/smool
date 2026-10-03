import AppKit
import Darwin
import Observation

struct SpotifyTrack: Decodable, Sendable {
    let title: String
    let artist: String
    let artwork: String
    let duration: Double
    let position: Double
    let playing: Bool

    var artworkURL: URL? {
        guard let url = URL(string: artwork), Self.allowsArtworkURL(url) else { return nil }
        return url
    }

    static func allowsArtworkURL(_ url: URL) -> Bool {
        guard url.scheme == "https",
              url.user == nil, url.password == nil, let host = url.host?.lowercased(),
              host == "scdn.co" || host.hasSuffix(".scdn.co") ||
              host == "spotifycdn.com" || host.hasSuffix(".spotifycdn.com") else { return false }
        return true
    }

    var elapsed: String { Self.time(position) }
    var remaining: String { "−" + Self.time(max(0, duration - position)) }
    var progress: Double { duration > 0 ? min(1, max(0, position / duration)) : 0 }

    private static func time(_ seconds: Double) -> String {
        let value = Int(max(0, seconds.isFinite ? seconds : 0))
        return "\(value / 60):\(String(format: "%02d", value % 60))"
    }
}

enum SpotifyPlaylist: String, CaseIterable, Identifiable {
    case releaseRadar, newMusicFriday, daylist

    var id: Self { self }

    var title: String {
        switch self {
        case .releaseRadar: "Release Radar"
        case .newMusicFriday: "New Music Friday"
        case .daylist: "daylist"
        }
    }

    // Spotify's public Swedish editorial playlist. Personalized playlists have no shared ID.
    // https://open.spotify.com/playlist/37i9dQZF1DXcecv7ESbOPu
    var defaultURI: String {
        self == .newMusicFriday ? "spotify:playlist:37i9dQZF1DXcecv7ESbOPu" : ""
    }

    var subtitle: String {
        switch self {
        case .releaseRadar: "Nytt från artister du följer"
        case .newMusicFriday: "Veckans nya musik från Sverige"
        case .daylist: "Musik för just den här stunden"
        }
    }

    var symbol: String {
        switch self {
        case .releaseRadar: "dot.radiowaves.left.and.right"
        case .newMusicFriday: "sparkles"
        case .daylist: "sun.horizon.fill"
        }
    }

    static func uri(from input: String) -> String? {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let id: String
        if value.hasPrefix("spotify:playlist:") {
            id = String(value.dropFirst("spotify:playlist:".count))
        } else if let url = URL(string: value), url.scheme == "https", url.host == "open.spotify.com",
                  url.user == nil, url.password == nil, url.port == nil || url.port == 443 {
            let parts = url.pathComponents.filter { $0 != "/" }
            guard let index = parts.firstIndex(of: "playlist"), index + 2 == parts.count else { return nil }
            id = parts[index + 1]
        } else {
            return nil
        }
        guard id.count == 22, id.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) }) else {
            return nil
        }
        return "spotify:playlist:\(id)"
    }
}

@MainActor
@Observable
final class SpotifyService {
    enum State {
        case loading, notRunning, permissionDenied, idle
        case ready(SpotifyTrack)
        case failed(String)
    }

    private(set) var state: State = .loading
    private(set) var isPerformingAction = false
    private(set) var actionError: String?
    private let request: @Sendable (SpotifyBridge.Command?) async throws -> SpotifyBridge.Response
    private let processIdentifier: @MainActor () -> pid_t?
    private var connectedProcess: pid_t?
    private var refreshing = false

    init(
        state: State = .loading,
        processIdentifier: @escaping @MainActor () -> pid_t? = {
            NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").first?.processIdentifier
        },
        request: (@Sendable (SpotifyBridge.Command?) async throws -> SpotifyBridge.Response)? = nil
    ) {
        self.state = state
        self.processIdentifier = processIdentifier
        let bridge = SpotifyBridge()
        self.request = request ?? { try await bridge.run($0) }
    }

    func observe() async {
        while !Task.isCancelled {
            await refresh()
            let delay: Duration = if case .ready(let track) = state, track.playing { .seconds(2) } else { .seconds(5) }
            do { try await Task.sleep(for: delay) } catch { return }
        }
    }

    func refresh(retry: Bool = false) async {
        guard !refreshing, !isPerformingAction, !Task.isCancelled else { return }
        guard let process = processIdentifier() else {
            connectedProcess = nil
            state = .notRunning
            return
        }
        // A restarted Spotify gets a fresh connection even if its old process timed out.
        if connectedProcess != process {
            connectedProcess = process
            state = .loading
            actionError = nil
        }
        // A denied permission needs an explicit retry, not another request on every poll.
        if !retry {
            if case .permissionDenied = state { return }
            if case .failed = state { return }
        }
        refreshing = true
        defer { refreshing = false }
        do {
            let response = try await request(nil)
            guard !Task.isCancelled else { return }
            guard processIdentifier() == process else {
                state = processIdentifier() == nil ? .notRunning : .loading
                return
            }
            switch response.status {
            case "notRunning": state = .notRunning
            case "idle": state = .idle
            case "ready":
                if let track = response.track { state = .ready(track) }
                else { state = .failed("Spotify skickade ingen låtinformation.") }
            default: state = response.code == -1743 ? .permissionDenied : .failed(response.errorDescription)
            }
        } catch {
            guard !Task.isCancelled else { return }
            if processIdentifier() != process {
                state = processIdentifier() == nil ? .notRunning : .loading
            } else {
                state = .failed("Kunde inte läsa Spotify. Försök igen.")
            }
        }
    }

    func retry() async {
        state = .loading
        await refresh(retry: true)
    }

    func perform(_ command: SpotifyBridge.Command) async {
        guard !isPerformingAction, !Task.isCancelled else { return }
        guard let process = processIdentifier() else { state = .notRunning; return }
        isPerformingAction = true
        actionError = nil
        var succeeded = false
        do {
            let response = try await request(command)
            guard !Task.isCancelled else { isPerformingAction = false; return }
            guard processIdentifier() == process else {
                isPerformingAction = false
                state = processIdentifier() == nil ? .notRunning : .loading
                return
            }
            switch response.status {
            case "success": succeeded = true
            case "notRunning": state = .notRunning
            default:
                if response.code == -1743 { state = .permissionDenied }
                else { actionError = response.errorDescription }
            }
        } catch {
            actionError = "Kunde inte bekräfta ändringen i Spotify. Kontrollera spelaren innan du försöker igen."
        }
        isPerformingAction = false
        if succeeded { await refresh(retry: true) }
    }

    func openSpotify() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.spotify.client") else {
            state = .failed("Installera Spotify på din Mac för att använda spelaren.")
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }

    func search(_ playlist: SpotifyPlaylist) {
        guard let query = playlist.title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "spotify:search:\(query)") else { return }
        if !NSWorkspace.shared.open(url) {
            actionError = "Kunde inte öppna sökningen. Kontrollera att Spotify är installerat."
        }
    }
}

/// Spotify's scripting dictionary exposes playback, but no playlist library.
/// A separate process keeps Apple Events and their timeout off the main thread.
actor SpotifyBridge {
    enum Command: Sendable {
        case togglePlayback, nextTrack, playlist(String)
    }

    struct Response: Decodable, Sendable {
        let status: String
        let track: SpotifyTrack?
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
