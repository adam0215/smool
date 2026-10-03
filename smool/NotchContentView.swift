import SwiftUI

struct NotchContentView: View {
    let presentation: NotchPresentation
    let selectApplet: (AppletID) -> Void
    var restoreFocus: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var capturedNoteID: UUID?
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
                            Button("Try saving again") {
                                guard let notes = presentation.registeredApplets.applet(for: AppletID(rawValue: "notes")) as? NotesApplet else { return }
                                notes.store.flush()
                                if !notes.store.hasUnsavedChanges { presentation.terminationError = nil }
                            }
                            .buttonStyle(NotchControlStyle(isSelected: true))
                            .keyboardShortcut("s", modifiers: .command)

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
        .environment(\.appletFocusGeneration, presentation.focusGeneration)
        .onChange(of: presentation.capturedSelection?.selection) { _, _ in capturedNoteID = nil }
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
                hostActions: presentation.showsActions ? presentation.hostActions : [],
                openApplet: selectApplet,
                composeInCodex: presentation.settings.isEnabled(AppletID(rawValue: "codex")) ? presentation.composeInCodex : nil,
                openSettings: presentation.openSettings
            ),
            artwork: displayedArtwork?.image
        )
        .id(presentation.displayedApplet.id)
        .transition(.opacity)
    }

    private var notes: NotesApplet? {
        presentation.registeredApplets.applet(for: AppletID(rawValue: "notes")) as? NotesApplet
    }

    private var notesAreReadOnly: Bool { notes?.store.isReadOnly == true }

    private func saveSelectionAsNote(_ text: String) {
        guard let notes else { return }
        if let capturedNoteID, notes.store.notes.contains(where: { $0.id == capturedNoteID }) {
            notes.store.flush()
        } else {
            guard presentation.saveCapturedNote(text) != nil else { return }
            capturedNoteID = notes.store.selectedID
        }
        guard !notes.store.hasUnsavedChanges else { return }
        presentation.capturedSelection = nil
        selectApplet(notes.id)
    }

    private func selectionPreview(_ preview: SelectionPreview) -> some View {
        VStack(spacing: 0) {
            SelectionActionsView(
                selection: preview.selection,
                error: preview.error,
                canSaveNote: presentation.settings.isEnabled(AppletID(rawValue: "notes")) && !notesAreReadOnly,
                saveNoteUnavailableReason: notesAreReadOnly ? "Notes could not be loaded. Your selection is still here." : nil,
                canComposeInCodex: presentation.settings.isEnabled(AppletID(rawValue: "codex")),
                saveNote: saveSelectionAsNote,
                composeInCodex: { text in
                    presentation.capturedSelection = nil
                    presentation.composeInCodex?(text)
                },
                dismiss: { presentation.capturedSelection = nil; restoreFocus() }
            )
            if capturedNoteID != nil, let error = notes?.store.errorMessage {
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
