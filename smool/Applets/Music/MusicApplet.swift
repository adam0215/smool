import SwiftUI

@MainActor
final class MusicApplet: Applet {
    let id = AppletID(rawValue: "music")
    let title = "Music"
    let icon = AppletIcon.symbol("music.note")
    let tint = Color.pink
    let contentHeight: CGFloat = 144
    let service = MusicService()

    var background: AppletBackground? {
        let source: AlbumArtwork.Source?
        if let data = service.media?.artworkData { source = .embedded(data) }
        else { source = service.artworkURL.map(AlbumArtwork.Source.spotify) }
        return AppletBackground(color: HomePalette.clock, artworkSource: source,
                                isPlaying: service.media?.track.playing == true)
    }

    var actions: [AppletAction] {
        let service = service
        return [
            AppletAction(id: "play-or-pause", title: "Play or pause", symbol: "playpause", shortcut: AppletShortcut(key: .space, modifiers: [])) { Task { await service.perform(.togglePlayback) } },
            AppletAction(id: "previous-track", title: "Previous track", symbol: "backward.end") { Task { await service.perform(.previousTrack) } },
            AppletAction(id: "next-track", title: "Next track", symbol: "forward.end") { Task { await service.perform(.nextTrack) } }
        ]
    }

    func makeView(context: AppletContext, artwork: NSImage?) -> AnyView {
        AnyView(MusicAppletView(service: service, artwork: artwork))
    }
}
