import Foundation
import Observation

@MainActor @Observable
final class SpotifyPlaylistCatalog {
    private(set) var playlists: [SpotifyPlaylist] = []
    private(set) var isLoading = false
    private(set) var error: String?
    private var loadedAt: Date?

    // Public editorial selections. Names and covers come from Spotify's supported oEmbed API.
    // These are not personalized recommendations or the user's private library.
    static let playlistIDs = ["37i9dQZF1DXcecv7ESbOPu", "37i9dQZF1DXcBWIGoYBM5M", "37i9dQZF1DX4WYpdgoIcn6"]

    func load(force: Bool = false) async {
        guard !isLoading else { return }
        if !force, let loadedAt, Date.now.timeIntervalSince(loadedAt) < 3_600 { return }
        isLoading = true
        defer { isLoading = false }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 12
        let session = URLSession(configuration: configuration, delegate: PlaylistRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let loaded = await withTaskGroup(of: SpotifyPlaylist?.self) { group in
            for id in Self.playlistIDs {
                group.addTask {
                    var url = URLComponents(string: "https://open.spotify.com/oembed")!
                    url.queryItems = [URLQueryItem(name: "url", value: "https://open.spotify.com/playlist/\(id)")]
                    guard let url = url.url,
                          let (data, response) = try? await session.data(from: url),
                          (response as? HTTPURLResponse)?.statusCode == 200, data.count < 100_000 else { return nil }
                    return try? SpotifyPlaylist.decode(data, id: id)
                }
            }
            var result: [SpotifyPlaylist] = []
            for await playlist in group { if let playlist { result.append(playlist) } }
            return result.sorted { Self.playlistIDs.firstIndex(of: $0.id)! < Self.playlistIDs.firstIndex(of: $1.id)! }
        }
        guard !Task.isCancelled else { return }
        if !loaded.isEmpty { playlists = loaded; loadedAt = .now }
        error = loaded.isEmpty ? "Could not load playlists from Spotify. Try again from Actions." : nil
    }
}

private final class PlaylistRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        let url = request.url
        completionHandler(url?.scheme == "https" && url?.host == "open.spotify.com" ? request : nil)
    }
}
