import AppKit
import ImageIO

/// One decoded cover supplies both the player image and a tiny color map for its glow.
struct AlbumArtwork {
    enum Source: Hashable {
        case spotify(URL)
        case embedded(Data)
    }

    let image: NSImage
    let colors: NSImage

    static func decode(_ data: Data) -> AlbumArtwork? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        func thumbnail(size: Int) -> NSImage? {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: size
            ]
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
            return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        }
        guard let image = thumbnail(size: 256), let colors = thumbnail(size: 8) else { return nil }
        return AlbumArtwork(image: image, colors: colors)
    }

    static func load(_ source: Source) async -> AlbumArtwork? {
        switch source {
        case .embedded(let data):
            return decode(data)
        case .spotify(let url):
            guard SpotifyTrack.allowsArtworkURL(url) else { return nil }
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
                      response.statusCode == 200 else { return nil }
                return decode(data)
            } catch { return nil }
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
