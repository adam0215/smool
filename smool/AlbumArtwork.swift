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

/// Decoded covers survive view removal. Concurrent tiles share the same request.
@MainActor
final class AlbumArtworkCache {
    static let shared = AlbumArtworkCache()

    private let capacity: Int
    private let loader: (AlbumArtwork.Source) async -> AlbumArtwork?
    private var entries: [AlbumArtwork.Source: AlbumArtwork] = [:]
    private var recent: [AlbumArtwork.Source] = []
    private var loading: [AlbumArtwork.Source: Task<AlbumArtwork?, Never>] = [:]

    init(capacity: Int = 24, loader: @escaping (AlbumArtwork.Source) async -> AlbumArtwork? = AlbumArtwork.load) {
        self.capacity = max(1, capacity)
        self.loader = loader
    }

    func cached(_ source: AlbumArtwork.Source?) -> AlbumArtwork? {
        guard let source, let artwork = entries[source] else { return nil }
        recent.removeAll { $0 == source }
        recent.append(source)
        return artwork
    }

    func load(_ source: AlbumArtwork.Source) async -> AlbumArtwork? {
        if let artwork = cached(source) { return artwork }
        if let task = loading[source] { return await task.value }

        // Finish a requested cover even if its first view closes before it arrives.
        let task = Task { await loader(source) }
        loading[source] = task
        let artwork = await task.value
        loading[source] = nil
        if let artwork {
            entries[source] = artwork
            recent.append(source)
            while recent.count > capacity {
                entries[recent.removeFirst()] = nil
            }
        }
        return artwork
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
