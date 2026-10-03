import SwiftUI

struct PlayerArtwork: View {
    let image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.white.opacity(0.06))
                    .overlay { Image(systemName: "music.note").foregroundStyle(.secondary) }
            }
        }
    }
}
