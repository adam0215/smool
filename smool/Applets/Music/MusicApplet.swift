import SwiftUI

@MainActor
final class MusicApplet: Applet {
    let id = AppletID(rawValue: "music")
    let title = "Musik"
    let icon = AppletIcon.symbol("music.note")
    let tint = Color.pink
    let contentHeight: CGFloat = 144
    let service = MusicService()

    var background: AppletBackground? {
        let source: AlbumArtwork.Source?
        if let data = service.media?.artworkData { source = .embedded(data) }
        else { source = service.artworkURL.map(AlbumArtwork.Source.spotify) }
        return AppletBackground(color: HomeGlow.color(for: nil), artworkSource: source,
                                isPlaying: service.media?.track.playing == true)
    }

    var actions: [AppletAction] {
        let service = service
        return [
            AppletAction(id: "Spela eller pausa", symbol: "playpause", shortcut: "␣") { Task { await service.perform(.togglePlayback) } },
            AppletAction(id: "Föregående låt", symbol: "backward.end") { Task { await service.perform(.previousTrack) } },
            AppletAction(id: "Nästa låt", symbol: "forward.end") { Task { await service.perform(.nextTrack) } }
        ]
    }

    func makeView(context: AppletContext, artwork: NSImage?) -> AnyView {
        AnyView(MusicAppletView(service: service, artwork: artwork))
    }
}
