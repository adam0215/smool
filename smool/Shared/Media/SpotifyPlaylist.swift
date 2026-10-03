import Foundation

struct SpotifyPlaylist: Identifiable, Sendable {
    let id: String
    let title: String
    let artworkURL: URL?
    var uri: String { "spotify:playlist:\(id)" }

    static func decode(_ data: Data, id: String) throws -> SpotifyPlaylist {
        struct Embed: Decodable {
            let title: String
            let thumbnail_url: String?
        }
        guard uri(from: "spotify:playlist:\(id)") != nil else { throw CocoaError(.coderInvalidValue) }
        let embed = try JSONDecoder().decode(Embed.self, from: data)
        guard !embed.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw CocoaError(.coderInvalidValue) }
        let artwork = embed.thumbnail_url.flatMap(URL.init(string:)).flatMap { MediaTrack.allowsArtworkURL($0) ? $0 : nil }
        return SpotifyPlaylist(id: id, title: embed.title, artworkURL: artwork)
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
