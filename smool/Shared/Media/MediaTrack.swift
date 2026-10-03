import Foundation

struct MediaTrack: Decodable, Sendable {
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
