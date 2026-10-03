import SwiftUI

struct MusicAppletView: View {
    let service: MusicService
    var artwork: NSImage? = nil
    @State private var selectedControl = 1
    @FocusState private var focused: Bool
    private let commands: [MediaBridge.Command] = [.previousTrack, .togglePlayback, .nextTrack]

    var body: some View {
        VStack(spacing: 6) {
            if let media = service.media {
                CompactPlayerView(track: media.track, artwork: artwork, selectedControl: selectedControl,
                                  hasPrevious: true, isBusy: service.isPerformingAction) { index in
                    selectedControl = index
                    Task { await service.perform(commands[index]) }
                }
            } else if service.isLoading {
                ProgressView().controlSize(.small)
            } else {
                HStack(spacing: 16) {
                    Image(systemName: "music.note").font(.system(size: 32, weight: .light))
                    Text("Inget spelas just nu").font(.system(size: 16, weight: .medium))
                }
                .foregroundStyle(.secondary)
            }
            if let error = service.error { Text(error).font(.caption2).foregroundStyle(.secondary).lineLimit(2) }
        }
        .modifier(NotchCard(elevated: false))
        .padding(.horizontal, NotchLayout.contentInset)
        .padding(.bottom, NotchLayout.contentInset)
        .focusable(interactions: .edit)
        .focused($focused)
        .focusEffectDisabled()
        .task { await Task.yield(); focused = true }
        .onKeyPress(keys: [.leftArrow, .rightArrow, .return, .space]) { key in
            guard key.modifiers.intersection([.command, .control, .option, .shift]).isEmpty else { return .ignored }
            switch key.key {
            case .leftArrow: selectedControl = (selectedControl + 2) % 3
            case .rightArrow: selectedControl = (selectedControl + 1) % 3
            case .return: Task { await service.perform(commands[selectedControl]) }
            default: Task { await service.perform(.togglePlayback) }
            }
            return .handled
        }
        .notchHelp("←→ Välj kontroll\n↵ Utför · Mellanslag Spela/pausa\n? Stäng hjälpen")
        .task { await service.observe() }
    }
}
