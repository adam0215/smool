import SwiftUI

struct NotchContentView: View {
    let presentation: NotchPresentation
    let selectTab: (NotchTab) -> Void
    var restoreFocus: () -> Void = {}
    var openCalendar: () -> Void = {}
    var closeCalendar: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var artwork: AlbumArtwork?
    @State private var loadedArtworkSource: AlbumArtwork.Source?

    private var artworkSource: AlbumArtwork.Source? {
        switch presentation.tab {
        case .spotify:
            if presentation.spotifyState.page == .playlists {
                return presentation.spotifyState.playlist?.artworkURL.map(AlbumArtwork.Source.spotify)
            }
            guard case .ready(let track) = presentation.spotify.state else { return nil }
            return track.artworkURL.map(AlbumArtwork.Source.spotify)
        case .music:
            if let data = presentation.music.media?.artworkData {
                return .embedded(data)
            }
            return presentation.music.artworkURL.map(AlbumArtwork.Source.spotify)
        default: return nil
        }
    }

    private var cover: NSImage? {
        loadedArtworkSource == artworkSource ? artwork?.image : nil
    }

    private var isPlaying: Bool {
        switch presentation.tab {
        case .spotify:
            guard case .ready(let track) = presentation.spotify.state else { return false }
            return track.playing
        case .music:
            return presentation.music.media?.track.playing == true
        default:
            return false
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            NotchTabBar(presentation: presentation, select: selectTab)

            Group {
                switch presentation.tab {
                case .home:
                    if presentation.showCalendar {
                        CalendarAppletView(service: presentation.calendar, close: closeCalendar)
                    } else {
                        TimelineView(.everyMinute) { context in
                            NotchHomeView(layout: presentation.layout, date: context.date, openTab: selectTab, openCalendar: openCalendar)
                        }
                    }
                case .spotify:
                    SpotifyAppletView(service: presentation.spotify, state: presentation.spotifyState, artwork: cover)
                case .codex:
                    CodexAppletView(state: presentation.codexState, restoreFocus: restoreFocus)
                case .music:
                    MusicAppletView(service: presentation.music, artwork: cover)
                }
            }
            .id(presentation.tab)
            .transition(.opacity)
        }
        .background {
            if presentation.tab != .home {
                AppletGlow(
                    tab: presentation.tab,
                    artwork: artwork,
                    artworkSource: loadedArtworkSource,
                    darkHeight: max(presentation.layout.navigationHeight + 8, presentation.layout.expandedSize.height - 144),
                    isExpanded: presentation.isExpanded,
                    isPlaying: isPlaying
                )
            }
        }
        .task(id: artworkSource) {
            let source = artworkSource
            let loaded = if let source { await AlbumArtwork.load(source) } else { nil as AlbumArtwork? }
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.9)) {
                artwork = loaded
                loadedArtworkSource = source
            }
        }
    }
}

private struct AppletGlow: View {
    let tab: NotchTab
    let artwork: AlbumArtwork?
    let artworkSource: AlbumArtwork.Source?
    let darkHeight: CGFloat
    let isExpanded: Bool
    let isPlaying: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var audio = SystemAudioLevel()

    private var usesAudioGlow: Bool { isPlaying && !reduceMotion && (tab == .music || tab == .spotify) }
    private var capturesAudio: Bool { isExpanded && usesAudioGlow }

    var body: some View {
        ZStack {
            if usesAudioGlow {
                MusicGlow(colors: artwork?.colors, fallback: HomeGlow.color(for: tab == .spotify ? .spotify : nil),
                          darkHeight: darkHeight, audio: audio.spectrum)
                    .id(artworkSource)
                    .transition(.opacity)
            } else {
                HomeGlow(
                    spotify: tab == .spotify ? 1 : 0,
                    codex: tab == .codex ? 1 : 0,
                    darkHeight: darkHeight
                )
                .opacity(artwork == nil ? 1 : 0)

                if let artwork {
                    ArtworkGlow(colors: artwork.colors, darkHeight: darkHeight)
                        .id(artworkSource)
                        .transition(.opacity)
                }
            }
        }
        .opacity(0.65)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.9), value: usesAudioGlow)
        .task(id: capturesAudio) { await audio.observe(enabled: capturesAudio) }
    }
}
