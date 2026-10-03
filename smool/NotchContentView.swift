import SwiftUI

struct NotchContentView: View {
    let presentation: NotchPresentation
    let selectApplet: (AppletID) -> Void
    var restoreFocus: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var artwork: AlbumArtwork?
    @State private var loadedArtworkSource: AlbumArtwork.Source?

    private var background: AppletBackground? { presentation.activeApplet.background }
    private var artworkSource: AlbumArtwork.Source? { background?.artworkSource }

    private var displayedArtwork: AlbumArtwork? {
        if loadedArtworkSource == artworkSource, let artwork { return artwork }
        return AlbumArtworkCache.shared.cached(artworkSource)
    }

    var body: some View {
        VStack(spacing: 8) {
            NotchTabBar(presentation: presentation, select: selectApplet)

            presentation.activeApplet.makeView(
                context: AppletContext(
                    layout: presentation.layout,
                    restoreFocus: restoreFocus,
                    frontApplets: presentation.frontApplets,
                    openApplet: selectApplet,
                    composeInCodex: presentation.composeInCodex,
                    openSettings: presentation.openSettings,
                    openShortcut: { shortcut in
                        if let applet = presentation.registry.applet(for: shortcut) { selectApplet(applet.id) }
                    },
                    canOpenShortcut: { presentation.registry.applet(for: $0) != nil },
                    shortcutNumber: { presentation.registry.shortcutNumber(for: $0) }
                ),
                artwork: displayedArtwork?.image
            )
            .id(presentation.selection)
            .transition(.opacity)
        }
        .background {
            if let background {
                AppletGlow(
                    background: background,
                    artwork: displayedArtwork ?? artwork,
                    artworkSource: displayedArtwork == nil ? loadedArtworkSource : artworkSource,
                    darkHeight: max(presentation.layout.navigationHeight + 8, presentation.layout.expandedSize.height - 144),
                    isExpanded: presentation.isExpanded,
                    audio: presentation.audio
                )
            }
        }
        .task(id: artworkSource) {
            let source = artworkSource
            let loaded = if let source { await AlbumArtworkCache.shared.load(source) } else { nil as AlbumArtwork? }
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.9)) {
                artwork = loaded
                loadedArtworkSource = source
            }
        }
    }
}

private struct AppletGlow: View {
    let background: AppletBackground
    let artwork: AlbumArtwork?
    let artworkSource: AlbumArtwork.Source?
    let darkHeight: CGFloat
    let isExpanded: Bool
    let audio: SystemAudioLevel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var usesAudioGlow: Bool { background.isPlaying && !reduceMotion }
    private var capturesAudio: Bool { isExpanded && usesAudioGlow }

    var body: some View {
        ZStack {
            if usesAudioGlow {
                MusicGlow(colors: artwork?.colors, fallback: background.color,
                          darkHeight: darkHeight, audio: audio.spectrum)
                    .id(artworkSource)
                    .transition(.opacity)
            } else {
                BottomGlow(color: background.color, horizontalPosition: background.horizontalPosition, darkHeight: darkHeight)
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
