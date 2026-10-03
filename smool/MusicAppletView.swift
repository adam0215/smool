import SwiftUI

struct MusicAppletView: View {
    let service: MusicService
    var artwork: NSImage? = nil
    @State private var selectedControl = 1
    @FocusState private var focused: Bool
    private let commands: [MediaBridge.Command] = [.previousTrack, .togglePlayback, .nextTrack]

    var body: some View {
        VStack(spacing: 16) {
            if let media = service.media {
                HStack(spacing: 16) {
                    SpotifyArtwork(image: artwork)
                        .frame(width: 86, height: 86)
                        .clipShape(.rect(cornerRadius: 12))
                        .accessibilityLabel("Skivomslag")
                    VStack(alignment: .leading, spacing: 5) {
                        Text(media.track.title).font(.system(size: 22, weight: .medium)).lineLimit(1)
                        Text(media.track.artist).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                        Text(media.appName).font(.caption2).foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack(spacing: 20) {
                    control("Föregående låt", symbol: "backward.end.fill", index: 0)
                    control(media.track.playing ? "Pausa" : "Spela", symbol: media.track.playing ? "pause.fill" : "play.fill", index: 1)
                    control("Nästa låt", symbol: "forward.end.fill", index: 2)
                }
                if media.track.duration > 0 {
                    VStack(spacing: 4) {
                        ProgressView(value: media.track.progress).tint(.white.opacity(0.7))
                        HStack {
                            Text(media.track.elapsed)
                            Spacer()
                            Text(media.track.remaining)
                        }
                        .font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                    }
                }
            } else if service.isLoading {
                ProgressView("Hämtar uppspelning…")
            } else {
                Image(systemName: "music.note").font(.largeTitle).foregroundStyle(.secondary)
                Text("Inget spelas just nu").font(.callout)
                Text("Starta musik eller video i en app på datorn.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let error = service.error { Text(error).font(.caption2).foregroundStyle(.secondary) }
            Spacer(minLength: 0)
            Text("←→ kontroll   ·   ↵ välj   ·   mellanslag spela/pausa")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .modifier(CardGlass(shape: RoundedRectangle(cornerRadius: 40), isSelected: true))
        .padding(.horizontal, NotchLayout.contentInset)
        .padding(.bottom, NotchLayout.contentInset)
        .focusable(interactions: .edit)
        .focused($focused)
        .focusEffectDisabled()
        .onAppear { focused = true }
        .onKeyPress(keys: [.leftArrow, .rightArrow, .return, .space]) { key in
            guard key.modifiers.isEmpty else { return .ignored }
            switch key.key {
            case .leftArrow: selectedControl = (selectedControl + 2) % 3
            case .rightArrow: selectedControl = (selectedControl + 1) % 3
            case .return: Task { await service.perform(commands[selectedControl]) }
            default: Task { await service.perform(.togglePlayback) }
            }
            return .handled
        }
        .task { await service.observe() }
    }

    private func control(_ title: String, symbol: String, index: Int) -> some View {
        Button { Task { await service.perform(commands[index]) } } label: {
            Image(systemName: symbol).frame(width: 36, height: 28)
        }
        .buttonStyle(NotchControlStyle(isSelected: selectedControl == index))
        .focusable(false)
        .disabled(service.isPerformingAction)
        .accessibilityLabel(title)
    }
}
