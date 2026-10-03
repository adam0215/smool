import Foundation
import JavaScriptCore

@main
struct SpotifyChecks {
    @MainActor
    static func main() async throws {
        let id = "37i9dQZEVXcABCDEFGHIJKLMNOP".prefix(22)
        let uri = "spotify:playlist:\(id)"
        precondition(SpotifyPlaylist.uri(from: uri) == uri)
        precondition(SpotifyPlaylist.uri(from: " https://open.spotify.com/playlist/\(id)?si=abc \n") == uri)
        precondition(SpotifyPlaylist.uri(from: "https://open.spotify.com/intl-sv/playlist/\(id)") == uri)
        precondition(SpotifyPlaylist.uri(from: "https://open.spotify.com.evil.test/playlist/\(id)") == nil)
        precondition(SpotifyPlaylist.uri(from: "spotify:playlist:');spotify.playpause();//") == nil)
        precondition(SpotifyPlaylist.uri(from: "https://open.spotify.com/track/\(id)") == nil)
        precondition(SpotifyPlaylist.uri(from: "http://open.spotify.com/playlist/\(id)") == nil)
        let playlistJSON = Data(#"{"title":"Fresh music","thumbnail_url":"https://i.scdn.co/image/test"}"#.utf8)
        let playlist = try SpotifyPlaylist.decode(playlistJSON, id: String(id))
        precondition(playlist.title == "Fresh music" && playlist.uri == uri && playlist.artworkURL != nil)
        let badArtwork = try SpotifyPlaylist.decode(Data(#"{"title":"Fresh music","thumbnail_url":"https://unrelated.example/image"}"#.utf8), id: String(id))
        precondition(badArtwork.artworkURL == nil, "Playlist artwork uses the same Spotify CDN boundary as track artwork.")
        do {
            _ = try SpotifyPlaylist.decode(Data(#"{"title":""}"#.utf8), id: String(id))
            preconditionFailure("Empty playlist metadata must not become a playable tile.")
        } catch { }
        precondition(SpotifyPlaylist.uri(from: "https://user:password@open.spotify.com/playlist/\(id)") == nil)
        precondition(SpotifyPlaylist.uri(from: "https://open.spotify.com:8443/playlist/\(id)") == nil)
        let readScript = try SpotifyBridge.script()
        precondition(!readScript.contains("spotify.playpause()") && !readScript.contains("spotify.nextTrack()") && !readScript.contains("spotify.playTrack("))
        let playScript = try SpotifyBridge.script(for: .playlist(uri))
        precondition(playScript.range(of: "return JSON.stringify({status: 'success'})")!.lowerBound < playScript.range(of: "const track")!.lowerBound)
        do {
            _ = try SpotifyBridge.script(for: .playlist("spotify:playlist:');spotify.playpause();//"))
            preconditionFailure("Invalid playlist identifiers must be rejected before scripting")
        } catch { }
        let timeout = SpotifyBridge.Response(status: "error", track: nil, code: -1712, message: nil)
        precondition(timeout.errorDescription.contains("Starta om Spotify"))
        let track = SpotifyTrack(title: "Track", artist: "Artist", artwork: "", duration: 200, position: 61, playing: true)
        precondition(track.elapsed == "1:01")
        precondition(track.remaining == "−2:19")
        precondition(track.progress == 0.305)
        let ended = SpotifyTrack(title: "", artist: "", artwork: "", duration: 20, position: 30, playing: false)
        precondition(ended.progress == 1 && ended.remaining == "−0:00")
        for url in ["https://i.scdn.co/image/example", "https://image-cdn-ak.spotifycdn.com/image/example"] {
            precondition(SpotifyTrack.allowsArtworkURL(URL(string: url)!))
        }
        for url in ["https://scdn.co.evil.test/image", "https://example.com/image", "http://i.scdn.co/image", "https://user:password@i.scdn.co/image"] {
            precondition(!SpotifyTrack.allowsArtworkURL(URL(string: url)!))
        }
        let javascript = JSContext()!
        func evaluate(_ source: String, application: String) throws -> SpotifyBridge.Response {
            let value = javascript.evaluateScript("(function(Application) { \(source); return run(); })(function() { return \(application); })")
            precondition(javascript.exception == nil, "The Spotify script must execute without JavaScript errors")
            return try JSONDecoder().decode(SpotifyBridge.Response.self, from: Data(value!.toString()!.utf8))
        }
        let stopped = try evaluate(readScript, application: "{ running: () => true, playerState: () => 'stopped', currentTrack: () => { throw new Error('Must not read a stopped track'); } }")
        precondition(stopped.status == "idle")
        let missingTrack = try evaluate(readScript, application: "{ running: () => true, playerState: () => 'paused', currentTrack: () => { throw {errorNumber: -1728}; } }")
        precondition(missingTrack.status == "idle")
        let missingArtwork = try evaluate(readScript, application: "{ running: () => true, playerState: () => 'playing', playerPosition: () => 61, currentTrack: () => ({ name: () => 'Track', artist: () => 'Artist', duration: () => 200000, artworkUrl: () => { throw new Error('No artwork'); } }) }")
        precondition(missingArtwork.status == "ready" && missingArtwork.track?.artwork == "")
        precondition(missingArtwork.track?.duration == 200 && missingArtwork.track?.playing == true)

        let mediaFixture = #"{"bundleIdentifier":"com.spotify.client","appName":"Spotify","track":{"title":"Quoted \"track\"","artist":"Artist","artwork":"","duration":200,"position":61,"playing":true}}"#
        let media = try JSONDecoder().decode(SystemMedia.self, from: Data(mediaFixture.utf8))
        precondition(media.bundleIdentifier == "com.spotify.client" && media.track.progress == 0.305)
        let noMedia = try JSONDecoder().decode(SystemMedia?.self, from: Data("null".utf8))
        precondition(noMedia == nil)

        let process = SpotifyTestProcess()
        let replies = SpotifyTestReplies(response: timeout)
        let service = SpotifyService(processIdentifier: { process.id }, request: { _ in await replies.read() })
        await service.refresh()
        guard case .failed = service.state else { preconditionFailure("Timeout must be visible") }
        let ready = SpotifyBridge.Response(status: "ready", track: track, code: nil, message: nil)
        await replies.setResponse(ready)
        await service.refresh()
        let readsBeforeRestart = await replies.readCount
        precondition(readsBeforeRestart == 1, "A failing process must not be polled repeatedly")
        process.id = 2
        await service.refresh()
        guard case .ready = service.state else { preconditionFailure("Restarted Spotify must reconnect automatically") }
        let readsAfterRestart = await replies.readCount
        precondition(readsAfterRestart == 2)

        let changingProcess = SpotifyTestProcess()
        let stale = SpotifyService(processIdentifier: { changingProcess.id }, request: { _ in
            await MainActor.run { changingProcess.id = 2 }
            return timeout
        })
        await stale.refresh()
        guard case .loading = stale.state else { preconditionFailure("A stale response must not mark a new Spotify process failed") }
        print("Spotify validation, scripting, artwork, and process-recovery checks passed")
    }
}

@MainActor
private final class SpotifyTestProcess {
    var id: pid_t? = 1
}

private actor SpotifyTestReplies {
    var response: SpotifyBridge.Response
    private(set) var readCount = 0

    init(response: SpotifyBridge.Response) { self.response = response }
    func setResponse(_ response: SpotifyBridge.Response) { self.response = response }
    func read() -> SpotifyBridge.Response {
        readCount += 1
        return response
    }
}
