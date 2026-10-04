import SwiftUI

struct NotchContentView: View {
    let presentation: NotchPresentation
    let selectApplet: (AppletID) -> Void
    var restoreFocus: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var artwork: AlbumArtwork?
    @State private var loadedArtworkSource: AlbumArtwork.Source?

    private var background: AppletBackground? { presentation.showsSettings ? nil : presentation.displayedApplet.background }
    private var artworkSource: AlbumArtwork.Source? { background?.artworkSource }

    private var displayedArtwork: AlbumArtwork? {
        if loadedArtworkSource == artworkSource, let artwork { return artwork }
        return AlbumArtworkCache.shared.cached(artworkSource)
    }

    var body: some View {
        VStack(spacing: 8) {
            NotchTabBar(presentation: presentation, select: selectApplet, restoreFocus: restoreFocus)

            ZStack {
                if presentation.showsSettings {
                    SettingsView(presentation: presentation)
                } else {
                    appletView
                        .disabled(presentation.capturedSelection != nil)
                        .opacity(presentation.capturedSelection == nil ? 1 : 0.2)
                }

                if let preview = presentation.capturedSelection {
                    selectionPreview(preview)
                }
            }
            .overlay(alignment: .top) {
                if let error = presentation.terminationError {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(error).font(.system(size: 12))
                        HStack {
                            if presentation.canRetryPendingChanges {
                                Button("Try saving again") {
                                    Task { await presentation.retryPendingChanges() }
                                }
                                .buttonStyle(NotchControlStyle(isSelected: true))
                                .keyboardShortcut("s", modifiers: .command)
                            }

                            Button("Keep editing") { presentation.terminationError = nil }
                                .buttonStyle(NotchControlStyle())
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.black, in: RoundedRectangle(cornerRadius: 16))
                    .padding(12)
                }
            }
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
        .environment(\.notchHelp, presentation.help)
        .environment(\.appletFocusGeneration, presentation.focusGeneration)
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

    private var appletView: some View {
        presentation.displayedApplet.makeView(
            context: AppletContext(
                layout: presentation.layout,
                restoreFocus: restoreFocus,
                frontApplets: presentation.frontApplets,
                openApplet: selectApplet,
                openSettings: presentation.openSettings
            ),
            artwork: displayedArtwork?.image
        )
        .id(presentation.displayedApplet.id)
        .transition(.opacity)
    }

    private func selectionPreview(_ preview: SelectionPreview) -> some View {
        VStack(spacing: 0) {
            SelectionActionsView(
                selection: preview.selection,
                error: preview.error,
                canSaveNote: presentation.canSaveCapturedNote,
                saveNoteUnavailableReason: presentation.capturedNoteUnavailableReason,
                canComposeInCodex: presentation.settings.isEnabled(AppletID(rawValue: "codex")),
                saveNote: { _ in
                    Task {
                        if let id = await presentation.saveCapturedNote() { selectApplet(id) }
                    }
                },
                composeInCodex: { text in
                    presentation.dismissPresentation()
                    presentation.composeInCodex?(text)
                },
                dismiss: { presentation.dismissPresentation(); restoreFocus() }
            )
            if let error = presentation.capture?.saveError {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)
            }
        }
        .modifier(FloatingGlass())
        .padding(12)
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
