import AppKit
import Darwin
import Observation

@MainActor
@Observable
final class SpotifyService {
    enum State {
        case loading, notRunning, permissionDenied, idle
        case ready(MediaTrack)
        case failed(String)
    }

    private(set) var state: State = .loading
    private(set) var isPerformingAction = false
    private(set) var actionError: String?
    private let request: @Sendable (SpotifyBridge.Command?) async throws -> SpotifyBridge.Response
    private let processIdentifier: @MainActor () -> pid_t?
    private var connectedProcess: pid_t?
    private var refreshing = false

    init(
        state: State = .loading,
        processIdentifier: @escaping @MainActor () -> pid_t? = {
            NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").first?.processIdentifier
        },
        request: (@Sendable (SpotifyBridge.Command?) async throws -> SpotifyBridge.Response)? = nil
    ) {
        self.state = state
        self.processIdentifier = processIdentifier
        let bridge = SpotifyBridge()
        self.request = request ?? { try await bridge.run($0) }
    }

    func observe() async {
        while !Task.isCancelled {
            await refresh()
            let delay: Duration = if case .ready(let track) = state, track.playing { .seconds(2) } else { .seconds(5) }
            do { try await Task.sleep(for: delay) } catch { return }
        }
    }

    func refresh(retry: Bool = false) async {
        guard !refreshing, !isPerformingAction, !Task.isCancelled else { return }
        guard let process = processIdentifier() else {
            connectedProcess = nil
            state = .notRunning
            return
        }
        // A restarted Spotify gets a fresh connection even if its old process timed out.
        if connectedProcess != process {
            connectedProcess = process
            switch state {
            case .ready: break
            default: state = .loading
            }
            actionError = nil
        }
        // A denied permission needs an explicit retry, not another request on every poll.
        if !retry {
            if case .permissionDenied = state { return }
            if case .failed = state { return }
        }
        refreshing = true
        defer { refreshing = false }
        do {
            let response = try await request(nil)
            guard !Task.isCancelled else { return }
            guard processIdentifier() == process else {
                state = processIdentifier() == nil ? .notRunning : .loading
                return
            }
            switch response.status {
            case "notRunning": state = .notRunning
            case "idle": state = .idle
            case "ready":
                if let track = response.track { state = .ready(track) }
                else { state = .failed("Spotify did not provide any track information.") }
            default: state = response.code == -1743 ? .permissionDenied : .failed(response.errorDescription)
            }
        } catch {
            guard !Task.isCancelled else { return }
            if processIdentifier() != process {
                state = processIdentifier() == nil ? .notRunning : .loading
            } else {
                state = .failed("Could not read Spotify. Try again.")
            }
        }
    }

    func retry() async {
        switch state {
        case .ready: break
        default: state = .loading
        }
        await refresh(retry: true)
    }

    func perform(_ command: SpotifyBridge.Command) async {
        guard !isPerformingAction, !Task.isCancelled else { return }
        guard let process = processIdentifier() else { state = .notRunning; return }
        isPerformingAction = true
        actionError = nil
        var succeeded = false
        do {
            let response = try await request(command)
            guard !Task.isCancelled else { isPerformingAction = false; return }
            guard processIdentifier() == process else {
                isPerformingAction = false
                state = processIdentifier() == nil ? .notRunning : .loading
                return
            }
            switch response.status {
            case "success": succeeded = true
            case "notRunning": state = .notRunning
            default:
                if response.code == -1743 { state = .permissionDenied }
                else { actionError = response.errorDescription }
            }
        } catch {
            actionError = "Could not confirm the change in Spotify. Check the player before trying again."
        }
        isPerformingAction = false
        if succeeded { await refresh(retry: true) }
    }

    func openSpotify() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.spotify.client") else {
            state = .failed("Install Spotify on your Mac to use the player.")
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }


}
