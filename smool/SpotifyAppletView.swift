import SwiftUI

enum SpotifyPage: CaseIterable {
    case player, playlists
    var title: String { self == .player ? "Spelare" : "Spellistor" }
}

@MainActor @Observable
final class SpotifyAppletState {
    var page = SpotifyPage.player
    let catalog = SpotifyPlaylistCatalog()
    var playlistID: String?
    var playlist: SpotifyPlaylist? { catalog.playlists.first { $0.id == playlistID } ?? catalog.playlists.first }

    func movePlaylist(_ offset: Int) {
        guard let playlist else { return }
        playlistID = cyclingPage(in: catalog.playlists.map(\.id), to: playlist.id, offset: offset)
    }
    var selectedControl = 0
}

struct SpotifyAppletView: View {
    let service: SpotifyService
    let state: SpotifyAppletState
    let artwork: NSImage?

    init(service: SpotifyService = SpotifyService(), state: SpotifyAppletState = SpotifyAppletState(), artwork: NSImage? = nil) {
        self.service = service
        self.state = state
        self.artwork = artwork
    }

    var body: some View {
        @Bindable var state = state
        AppletPages(
            pages: SpotifyPage.allCases,
            selection: $state.page,
            title: { $0.title },
            navigationHint: state.page == .player
                ? "↑↓ Byt sida · ←→ Välj kontroll\nMellanslag Spela/pausa · ↵ Utför\n? Stäng hjälpen"
                : "↑↓ Byt sida · ←→ Välj spellista\n↵ Spela · ⌘K Åtgärder\n? Stäng hjälpen"
        ) { page in
            switch page {
            case .player: SpotifyPlayerView(service: service, artwork: artwork, selectedControl: $state.selectedControl)
            case .playlists: SpotifyPlaylistsView(service: service, state: state)
            }
        }
        .onKeyPress(keys: [.leftArrow, .rightArrow], phases: [.down, .repeat]) { key in
            guard key.modifiers.intersection([.command, .control, .option, .shift]).isEmpty else { return .ignored }
            let offset = key.key == .leftArrow ? -1 : 1
            if state.page == .playlists {
                state.movePlaylist(offset)
            } else {
                state.selectedControl = (state.selectedControl + offset + 2) % 2
            }
            return .handled
        }
        .background {
            Button("Uppdatera") { Task { await service.retry(); await state.catalog.load(force: true) } }
                .keyboardShortcut("r", modifiers: .command).hidden()
        }
        .task { await service.observe() }
    }
}

private struct SpotifyPlayerView: View {
    let service: SpotifyService
    let artwork: NSImage?
    @Binding var selectedControl: Int

    var body: some View {
        Group {
            switch service.state {
            case .ready(let track): player(track)
            case .loading:
                ProgressView("Ansluter till Spotify…")
                    .font(.system(size: 12))
            case .notRunning:
                message("Spotify är inte igång", detail: "Starta Spotify för att visa din musik här.", action: "Starta Spotify") {
                    service.openSpotify()
                }
            case .permissionDenied:
                message("Tillåt åtkomst till Spotify", detail: "Aktivera smool → Spotify i Systeminställningar → Integritet och säkerhet → Automation.", action: "Försök igen") {
                    Task { await service.retry() }
                }
            case .idle:
                message("Ingen låt vald", detail: "Välj musik i Spotify, eller öppna Spellistor med ↓.", action: "Öppna Spotify") {
                    service.openSpotify()
                }
            case .failed(let error):
                message("Kunde inte ansluta", detail: error, action: "Försök igen") {
                    Task { await service.retry() }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            if case .ready = service.state {
                Button("Vald kontroll") {
                    Task { await service.perform(selectedControl == 0 ? .togglePlayback : .nextTrack) }
                }
                .keyboardShortcut(.return, modifiers: [])
                .disabled(service.isPerformingAction)
                .hidden()
            }
        }
    }

    private func player(_ track: SpotifyTrack) -> some View {
        VStack(spacing: 6) {
            CompactPlayerView(track: track, artwork: artwork, selectedControl: selectedControl,
                              isBusy: service.isPerformingAction) { index in
                selectedControl = index
                Task { await service.perform(index == 0 ? .togglePlayback : .nextTrack) }
            }
            if let error = service.actionError {
                Text(error).font(.system(size: 10)).foregroundStyle(.orange).lineLimit(2)
            }
        }
        .background {
            Button("Spela eller pausa") { Task { await service.perform(.togglePlayback) } }
                .keyboardShortcut(.space, modifiers: []).hidden()
            Button("Nästa låt") { Task { await service.perform(.nextTrack) } }
                .keyboardShortcut("n", modifiers: .command).hidden()
        }
    }

    private func message(_ title: String, detail: String, action: String, perform: @escaping () -> Void) -> some View {
        HStack(spacing: 16) {
            Image(systemName: "music.note").font(.system(size: 32, weight: .light)).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 16, weight: .medium))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: perform) { Image(systemName: "arrow.up.right").font(.title3).frame(width: 36, height: 44) }
                .keyboardShortcut(.return, modifiers: [])
                .buttonStyle(.plain)
                .focusable(false)
                .accessibilityLabel(action)
        }
    }
}
