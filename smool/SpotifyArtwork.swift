import SwiftUI

struct SpotifyArtwork: View {
    let url: URL?
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.white.opacity(0.06))
                    .overlay { Image(systemName: "music.note").foregroundStyle(.secondary) }
            }
        }
        .task(id: url) {
            image = nil
            guard let url, SpotifyTrack.allowsArtworkURL(url) else { return }
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpCookieStorage = nil
            configuration.urlCredentialStorage = nil
            configuration.httpShouldSetCookies = false
            configuration.timeoutIntervalForRequest = 10
            let session = URLSession(configuration: configuration, delegate: SpotifyArtworkRedirects(), delegateQueue: nil)
            defer { session.invalidateAndCancel() }
            do {
                let (data, response) = try await session.data(from: url)
                guard !Task.isCancelled, let response = response as? HTTPURLResponse,
                      response.statusCode == 200 else { return }
                image = NSImage(data: data)
            } catch { }
        }
    }
}

/// Artwork never uses stored credentials or follows redirects outside Spotify's CDNs.
private final class SpotifyArtworkRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(request.url.map(SpotifyTrack.allowsArtworkURL) == true ? request : nil)
    }
}
