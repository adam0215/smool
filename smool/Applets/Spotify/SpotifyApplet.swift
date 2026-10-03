import SwiftUI

@MainActor
final class SpotifyApplet: Applet {
    let id = AppletID(rawValue: "spotify")
    let title = "Spotify"
    let icon = AppletIcon.asset("Spotify")
    let tint = Color.green
    let homeShortcut: HomeApp? = .spotify
    let contentHeight: CGFloat = 156
    let service = SpotifyService()
    let state = SpotifyAppletState()

    var background: AppletBackground? {
        var background = AppletBackground(color: HomeGlow.color(for: .spotify), horizontalPosition: 0.25)
        if case .ready(let track) = service.state {
            background.isPlaying = track.playing
            background.artworkSource = track.artworkURL.map(AlbumArtwork.Source.spotify)
        }
        if state.page == .playlists {
            background.artworkSource = state.playlist?.artworkURL.map(AlbumArtwork.Source.spotify)
        }
        return background
    }

    var pages: [AppletPage] {
        SpotifyPage.allCases.map { page in
            AppletPage(id: page.title, isSelected: state.page == page) { self.state.page = page }
        }
    }

    var actions: [AppletAction] {
        let state = state
        let service = service
        return [
            AppletAction(id: "Spelare", symbol: "play.circle", selected: state.page == .player) { state.page = .player },
            AppletAction(id: "Spellistor", symbol: "music.note.list", selected: state.page == .playlists) { state.page = .playlists },
            AppletAction(id: "Öppna Spotify", symbol: "arrow.up.right") { service.openSpotify() },
            AppletAction(id: "Uppdatera", symbol: "arrow.clockwise", shortcut: "⌘R") { Task { await service.retry(); await state.catalog.load(force: true) } }
        ]
    }

    func makeView(context: AppletContext, artwork: NSImage?) -> AnyView {
        AnyView(SpotifyAppletView(service: service, state: state, artwork: artwork))
    }

    func handleArrow(_ arrow: AppletArrow, command: Bool) -> Bool {
        guard !command else { return false }
        if arrow.isVertical {
            state.page = cyclingPage(in: SpotifyPage.allCases, to: state.page, offset: arrow.offset)
        } else if state.page == .playlists {
            state.movePlaylist(arrow.offset)
        } else {
            state.selectedControl = (state.selectedControl + arrow.offset + 2) % 2
        }
        return true
    }
}
