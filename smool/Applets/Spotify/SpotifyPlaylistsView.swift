import SwiftUI

struct SpotifyPlaylistsView: View {
    let service: SpotifyService
    let state: SpotifyAppletState

    var body: some View {
        VStack(spacing: 10) {
            if state.catalog.playlists.isEmpty {
                if state.catalog.isLoading { ProgressView().controlSize(.small) }
                else { Text(state.catalog.error ?? "Inga spellistor tillgängliga").font(.caption).foregroundStyle(.secondary) }
            } else {
                HStack(spacing: 16) {
                    ForEach(state.catalog.playlists) { playlist in
                        Button {
                            state.playlistID = playlist.id
                            play()
                        } label: {
                            PlaylistCover(playlist: playlist, selected: state.playlist?.id == playlist.id)
                        }
                        .buttonStyle(.plain).focusable(false)
                        .disabled(service.isPerformingAction)
                        .accessibilityLabel("Spela \(playlist.title)")
                        .accessibilityAddTraits(state.playlist?.id == playlist.id ? .isSelected : [])
                    }
                }
                if let error = service.actionError ?? state.catalog.error {
                    Text(error).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                }
            }
        }
        .background {
            Button("Spela spellista", action: play).keyboardShortcut(.return, modifiers: []).hidden()
                .disabled(state.playlist == nil || service.isPerformingAction)
        }
        .task { await state.catalog.load() }
    }

    private func play() {
        guard let playlist = state.playlist else { return }
        Task { await service.perform(.playlist(playlist.uri)) }
    }
}

private struct PlaylistCover: View {
    let playlist: SpotifyPlaylist
    let selected: Bool
    @State private var image: NSImage?
    @State private var loadedURL: URL?

    private var cover: NSImage? {
        if loadedURL == playlist.artworkURL, let image { return image }
        return AlbumArtworkCache.shared.cached(playlist.artworkURL.map(AlbumArtwork.Source.spotify))?.image
    }

    var body: some View {
        VStack(spacing: 7) {
            PlayerArtwork(image: cover)
                .frame(width: 64, height: 64)
                .clipShape(.rect(cornerRadius: 9))
            Text(playlist.title).font(.system(size: 10, weight: .medium)).lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.center).frame(maxWidth: .infinity)
        }
        .padding(8)
        .modifier(CardGlass(shape: RoundedRectangle(cornerRadius: 14), isSelected: selected))
        .task(id: playlist.artworkURL) {
            let url = playlist.artworkURL
            let loaded = if let url { await AlbumArtworkCache.shared.load(.spotify(url)) } else { nil as AlbumArtwork? }
            guard !Task.isCancelled else { return }
            image = loaded?.image
            loadedURL = url
        }
    }
}
