import AppKit
import Observation

@MainActor @Observable
final class MusicService {
    private let bridge = MediaBridge()
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
        } catch is CancellationError { return }
        catch {
            media = nil
            self.error = "Kunde inte läsa datorns uppspelning."
        }
        isLoading = false
    }

    func perform(_ command: MediaBridge.Command) async {
        guard let media, !isPerformingAction else { return }
        isPerformingAction = true
        defer { isPerformingAction = false }
        do {
            guard try await bridge.send(command, to: media.bundleIdentifier) else {
                error = "Spelaren har ändrats eller kunde inte ta emot kommandot."
                return
            }
            await refresh()
        } catch {
            self.error = "Kunde inte styra uppspelningen."
        }
    }
}
