import SwiftUI

enum SpotifyPage: CaseIterable {
    case player, playlists
    var title: String { self == .player ? "Spelare" : "Spellistor" }
}

@MainActor @Observable
final class SpotifyAppletState {
    var page = SpotifyPage.player
    var playlist = SpotifyPlaylist.releaseRadar
}

struct SpotifyAppletView: View {
    let service: SpotifyService
    let state: SpotifyAppletState
    @State private var editingPlaylistLink = false

    init(service: SpotifyService = SpotifyService(), state: SpotifyAppletState = SpotifyAppletState()) {
        self.service = service
        self.state = state
    }

    var body: some View {
        @Bindable var state = state
        PageStack(
            pages: SpotifyPage.allCases,
            selection: $state.page,
            title: { $0.title },
            isNavigating: !editingPlaylistLink,
            autoFocus: false,
            editingHint: "↵ spara länk   ·   esc tillbaka",
            navigationHint: state.page == .player
                ? "↑↓ kort   ·   ←→ kontroll   ·   mellanslag spela/pausa"
                : "↑↓ kort   ·   ←→ spellista   ·   ↵ spela"
        ) { page in
            switch page {
            case .player: SpotifyPlayerView(service: service)
            case .playlists: SpotifyPlaylistsView(service: service, selection: $state.playlist, isEditing: $editingPlaylistLink)
            }
        }
        .task { await service.observe() }
    }
}

private struct SpotifyPlayerView: View {
    let service: SpotifyService
    @FocusState private var playerFocused: Bool
    @State private var selectedControl = 0

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
        .focusable(interactions: .edit)
        .focused($playerFocused)
        .focusEffectDisabled()
        .task { await Task.yield(); playerFocused = true }
        .onKeyPress(keys: [.leftArrow, .rightArrow]) { key in
            guard case .ready = service.state else { return .ignored }
            selectedControl = key.key == .leftArrow ? 0 : 1
            return .handled
        }
        .onKeyPress(keys: [.return, .space]) { key in
            switch service.state {
            case .ready:
                Task { await service.perform(key.key == .space || selectedControl == 0 ? .togglePlayback : .nextTrack) }
            case .notRunning, .idle:
                service.openSpotify()
            case .failed, .permissionDenied:
                Task { await service.retry() }
            case .loading: return .ignored
            }
            return .handled
        }
    }

    private func player(_ track: SpotifyTrack) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 14) {
                SpotifyArtwork(url: track.artworkURL)
                .frame(width: 78, height: 78)
                .clipShape(.rect(cornerRadius: 12))
                .accessibilityLabel("Skivomslag")

                VStack(alignment: .leading, spacing: 5) {
                    Text(track.title)
                        .font(.system(size: 16, weight: .semibold))
                        .lineLimit(1)
                    Text(track.artist)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    HStack(spacing: 8) {
                        transportButton(track.playing ? "Pausa" : "Spela", symbol: track.playing ? "pause.fill" : "play.fill", index: 0) {
                            await service.perform(.togglePlayback)
                        }
                        transportButton("Nästa låt", symbol: "forward.end.fill", index: 1) {
                            await service.perform(.nextTrack)
                        }
                        if service.isPerformingAction { ProgressView().controlSize(.mini) }
                    }
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            VStack(spacing: 4) {
                ProgressView(value: track.progress)
                    .tint(.white.opacity(0.75))
                    .accessibilityLabel("Låtens position")
                    .accessibilityValue("\(track.elapsed), \(track.remaining) kvar")
                HStack {
                    Text(track.elapsed)
                    Spacer()
                    Text(track.remaining)
                }
                .font(.system(size: 9).monospacedDigit())
                .foregroundStyle(.secondary)
            }
            if let error = service.actionError {
                Text(error).font(.system(size: 10)).foregroundStyle(.orange).lineLimit(2)
            }
        }

    }

    private func transportButton(_ title: String, symbol: String, index: Int, action: @escaping () async -> Void) -> some View {
        Button {
            selectedControl = index
            Task { await action() }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 40, height: 28)
        }
        .buttonStyle(NotchControlStyle(isSelected: selectedControl == index))
        .focusable(false)
        .disabled(service.isPerformingAction)
        .accessibilityLabel(title)
        .help(title)
    }

    private func message(_ title: String, detail: String, action: String, perform: @escaping () -> Void) -> some View {
        VStack(spacing: 8) {
            Text(title).font(.system(size: 14, weight: .semibold))
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button(action, action: perform)
                .buttonStyle(NotchControlStyle())
                .controlSize(.small)
                .focusable(false)
        }
    }
}

