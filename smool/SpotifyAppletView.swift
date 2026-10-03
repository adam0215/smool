import SwiftUI

enum SpotifyPage: CaseIterable {
    case player, playlists
    var title: String { self == .player ? "Spelare" : "Spellistor" }
}

@MainActor @Observable
final class SpotifyAppletState {
    var page = SpotifyPage.player
    var playlist = SpotifyPlaylist.releaseRadar
    var selectedControl = 0
    var editingPlaylistLink = false
    var playlistLinkDraft = ""
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
        PageStack(
            pages: SpotifyPage.allCases,
            selection: $state.page,
            title: { $0.title },
            isNavigating: !state.editingPlaylistLink,
            editingHint: "↵ spara länk   ·   esc tillbaka",
            navigationHint: state.page == .player
                ? "↑↓ kort   ·   ←→ kontroll   ·   mellanslag spela/pausa"
                : "↑↓ kort   ·   ←→ spellista   ·   ↵ spela"
        ) { page in
            switch page {
            case .player: SpotifyPlayerView(service: service, artwork: artwork, selectedControl: $state.selectedControl)
            case .playlists: SpotifyPlaylistsView(service: service, selection: $state.playlist, isEditing: $state.editingPlaylistLink, link: $state.playlistLinkDraft)
            }
        }
        .onKeyPress(keys: [.leftArrow, .rightArrow], phases: [.down, .repeat]) { key in
            guard !state.editingPlaylistLink,
                  key.modifiers.intersection([.command, .control, .option, .shift]).isEmpty else { return .ignored }
            let offset = key.key == .leftArrow ? -1 : 1
            if state.page == .playlists {
                state.playlist = cyclingPage(in: SpotifyPlaylist.allCases, to: state.playlist, offset: offset)
            } else {
                state.selectedControl = (state.selectedControl + offset + 2) % 2
            }
            return .handled
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
        VStack(spacing: 10) {
            HStack(spacing: 14) {
                SpotifyArtwork(image: artwork)
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
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                Text(index == 0 ? "␣" : "⌘N")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .frame(height: 22)
        }
        .keyboardShortcut(index == 0 ? .space : "n", modifiers: index == 0 ? [] : .command)
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
            Button(action: perform) { ShortcutLabel(action, keys: "↵") }
                .keyboardShortcut(.return, modifiers: [])
                .buttonStyle(NotchControlStyle())
                .controlSize(.small)
                .focusable(false)
        }
    }
}

