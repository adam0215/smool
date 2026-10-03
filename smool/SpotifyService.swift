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
    private let bridge = SpotifyBridge()
    private var refreshing = false

    init(state: State = .loading) {
        self.state = state
    }

    func observe() async {
        while !Task.isCancelled {
            await refresh()
            let delay: Duration = if case .ready(let track) = state, track.playing { .seconds(2) } else { .seconds(5) }
            do { try await Task.sleep(for: delay) } catch { return }
        }
    }

    func refresh(retry: Bool = false) async {
        guard !refreshing, !isPerformingAction else { return }
        guard NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").isEmpty == false else {
            state = .notRunning
            return
        }
        // A denied permission needs an explicit retry, not another request on every poll.
        if !retry {
            if case .permissionDenied = state { return }
            if case .failed = state { return }
        }
        refreshing = true
        defer { refreshing = false }
        do {
            let response = try await bridge.run()
            guard !Task.isCancelled else { return }
            switch response.status {
            case "notRunning": state = .notRunning
            case "idle": state = .idle
            case "ready":
                if let track = response.track { state = .ready(track) }
                else { state = .failed("Spotify skickade ingen låtinformation.") }
            default: state = response.code == -1743 ? .permissionDenied : .failed(response.errorDescription)
            }
        } catch {
            if !Task.isCancelled { state = .failed("Kunde inte läsa Spotify. Försök igen.") }
        }
    }

    func retry() async {
        state = .loading
        await refresh(retry: true)
    }

    func perform(_ command: SpotifyBridge.Command) async {
        guard !isPerformingAction else { return }
        isPerformingAction = true
        actionError = nil
        var succeeded = false
        do {
            let response = try await bridge.run(command)
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
                const track = spotify.currentTrack();
                if (!track || !track.name()) return JSON.stringify({status: 'idle'});
                return JSON.stringify({status: 'ready', track: {
                    title: track.name(), artist: track.artist(), artwork: track.artworkUrl() || '',
                    duration: track.duration() / 1000, position: spotify.playerPosition(),
                    playing: spotify.playerState() === 'playing'
                }});
            } catch (error) {
                return JSON.stringify({status: 'error', code: error.errorNumber || 0, message: String(error.message || error)});
            }
        }
        """
    }

    func run(_ command: Command? = nil) async throws -> Response {
        try Task.checkCancellation()
        let script = try Self.script(for: command)
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
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        try Task.checkCancellation()
        if process.terminationReason == .uncaughtSignal, process.terminationStatus == SIGKILL {
            return Response(status: "error", track: nil, code: -1712, message: nil)
        }
        guard process.terminationStatus == 0 else { throw CocoaError(.executableRuntimeMismatch) }
        return try JSONDecoder().decode(Response.self, from: data)
    }
}
