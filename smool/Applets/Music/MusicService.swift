import AppKit
import Observation

@MainActor @Observable
final class MusicService {
    private let bridge = MediaBridge()
    private let spotify = SpotifyBridge()
    private var artworkTrack: [String]?
    private(set) var artworkURL: URL?
    private(set) var media: SystemMedia?
    private(set) var error: String?
    private(set) var isLoading = true
    private(set) var isPerformingAction = false

    func observe() async {
        while !Task.isCancelled {
            await refresh()
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
        }
    }

    private func refresh() async {
        do {
            let result = try await bridge.read()
            try Task.checkCancellation()
            media = result
            error = nil
            isLoading = false
            let identity = result.map { [$0.bundleIdentifier, $0.track.title, $0.track.artist] }
            if identity != artworkTrack {
                artworkURL = nil
                if let result, result.artworkData == nil, result.bundleIdentifier == "com.spotify.client",
                   let response = try? await spotify.run(), let track = response.track,
                   track.title == result.track.title, track.artist == result.track.artist {
                    try Task.checkCancellation()
                    guard identity == media.map({ [$0.bundleIdentifier, $0.track.title, $0.track.artist] }) else { return }
                    artworkURL = track.artworkURL
                }
                try Task.checkCancellation()
                artworkTrack = identity
            }
        } catch is CancellationError { return }
        catch {
            self.error = "Could not read the current playback."
        }
        isLoading = false
    }

    func perform(_ command: MediaBridge.Command) async {
        guard let media, !isPerformingAction else { return }
        isPerformingAction = true
        defer { isPerformingAction = false }
        do {
            guard try await bridge.send(command, to: media.bundleIdentifier) else {
                error = "The player changed or could not receive the command."
                return
            }
            await refresh()
        } catch {
            self.error = "Could not control playback."
        }
    }
}
