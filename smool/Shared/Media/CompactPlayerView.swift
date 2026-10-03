import SwiftUI

struct CompactPlayerView: View {
    let track: MediaTrack
    let artwork: NSImage?
    let selectedControl: Int
    var hasPrevious = false
    var isBusy = false
    let perform: (Int) -> Void

    private var playIndex: Int { hasPrevious ? 1 : 0 }

    var body: some View {
        HStack(spacing: 14) {
            PlayerArtwork(image: artwork)
                .frame(width: 72, height: 72)
                .clipShape(.rect(cornerRadius: 14))
                .accessibilityLabel("Skivomslag")

            VStack(alignment: .leading, spacing: 6) {
                Text(track.title)
                    .font(.system(size: 17, weight: .medium))
                    .lineLimit(2)
                Text(track.artist)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                ProgressView(value: track.progress)
                    .tint(.white.opacity(0.5))
                    .scaleEffect(x: 1, y: 0.5)
                    .accessibilityLabel("\(track.elapsed), \(track.remaining) kvar")
                    .help("\(track.elapsed) · \(track.remaining)")
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 4) {
                if hasPrevious { control("Föregående", symbol: "backward.end.fill", index: 0) }
                control(track.playing ? "Pausa" : "Spela", symbol: track.playing ? "pause.fill" : "play.fill", index: playIndex)
                control("Nästa", symbol: "forward.end.fill", index: playIndex + 1)
            }
        }
    }

    private func control(_ title: String, symbol: String, index: Int) -> some View {
        Button { perform(index) } label: {
            Image(systemName: symbol)
                .font(.system(size: index == playIndex ? 20 : 12, weight: .medium))
                .foregroundStyle(index == playIndex || selectedControl == index ? .white : .white.opacity(0.45))
                .frame(width: index == playIndex ? 44 : 26, height: 48)
                .background(.white.opacity(index == selectedControl ? 0.1 : 0), in: .rect(cornerRadius: 16))
                .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(index == selectedControl ? 0.18 : 0), lineWidth: 0.5) }
        }
        .buttonStyle(.plain)
        .focusable(false)
        .disabled(isBusy)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selectedControl == index ? .isSelected : [])
        .help(title)
    }
}
