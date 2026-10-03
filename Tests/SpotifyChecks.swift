import Foundation

@main
struct SpotifyChecks {
    static func main() throws {
        let id = "37i9dQZEVXcABCDEFGHIJKLMNOP".prefix(22)
        let uri = "spotify:playlist:\(id)"
        precondition(SpotifyPlaylist.uri(from: uri) == uri)
        precondition(SpotifyPlaylist.uri(from: " https://open.spotify.com/playlist/\(id)?si=abc \n") == uri)
        precondition(SpotifyPlaylist.uri(from: "https://open.spotify.com/intl-sv/playlist/\(id)") == uri)
        precondition(SpotifyPlaylist.uri(from: "https://open.spotify.com.evil.test/playlist/\(id)") == nil)
        precondition(SpotifyPlaylist.uri(from: "spotify:playlist:');spotify.playpause();//") == nil)
        precondition(SpotifyPlaylist.uri(from: "https://open.spotify.com/track/\(id)") == nil)
        precondition(SpotifyPlaylist.uri(from: "http://open.spotify.com/playlist/\(id)") == nil)
        precondition(SpotifyPlaylist.newMusicFriday.defaultURI == "spotify:playlist:37i9dQZF1DXcecv7ESbOPu")
        precondition(SpotifyPlaylist.releaseRadar.defaultURI.isEmpty && SpotifyPlaylist.daylist.defaultURI.isEmpty)
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
        print("Spotify URI validation and playback formatting checks passed")
    }
}
