import SwiftUI

struct SpotifyPlaylistsView: View {
    let service: SpotifyService
    @Binding var selection: SpotifyPlaylist
    @Binding var isEditing: Bool
    @State private var link = ""
    @State private var linkError: String?
    @AppStorage("spotify.playlist.releaseRadar") private var releaseRadar = ""
    @AppStorage("spotify.playlist.newMusicFriday") private var newMusicFriday = SpotifyPlaylist.newMusicFriday.defaultURI
    @AppStorage("spotify.playlist.daylist") private var daylist = ""
    @FocusState private var browsing: Bool
    @FocusState private var editingLink: Bool

    private var savedURI: String {
        switch selection {
        case .releaseRadar: releaseRadar
        case .newMusicFriday: newMusicFriday.isEmpty ? selection.defaultURI : newMusicFriday
        case .daylist: daylist
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            if isEditing {
                linkEditor
            } else {
                HStack(spacing: 8) {
                    ForEach(SpotifyPlaylist.allCases) { playlist in
                        Button {
                            selection = playlist
                            activate()
                        } label: {
                            VStack(spacing: 10) {
                                Image(systemName: playlist.symbol)
                                    .font(.system(size: 24, weight: .light))
                                    .modifier(GlassInk(illumination: 1, isSelected: selection == playlist))
                                Text(playlist.title)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.primary.opacity(selection == playlist ? 0.95 : 0.7))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 84)
                            .modifier(CardGlass(shape: RoundedRectangle(cornerRadius: 16), isSelected: selection == playlist))
                            .contentShape(.rect(cornerRadius: 16))
                        }
                        .buttonStyle(.plain)
                        .focusable(false)
                        .accessibilityAddTraits(selection == playlist ? .isSelected : [])
                    }
                }


                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(selection.subtitle).font(.system(size: 11))
                        Text(savedURI.isEmpty ? "Anslut din personliga lista en gång." : "Spela direkt i Spotify.")
                            .font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if !savedURI.isEmpty {
                        Button { beginEditing() } label: { Image(systemName: "ellipsis") }
                            .buttonStyle(NotchControlStyle())
                            .focusable()
                            .accessibilityLabel("Ändra spellistelänk")
                    }
                    Button(savedURI.isEmpty ? "Anslut" : "Spela") { activate() }
                        .buttonStyle(NotchControlStyle())
                        .focusable()
                        .disabled(service.isPerformingAction)
                }
                if let error = service.actionError {
                    Text(error).font(.system(size: 9)).foregroundStyle(.orange).lineLimit(2)
                }
            }
        }
        .focusable(!isEditing, interactions: .edit)
        .focused($browsing)
        .focusEffectDisabled()
        .task { await Task.yield(); browsing = !isEditing }
        .onKeyPress(keys: [.leftArrow, .rightArrow]) { key in
            guard browsing, !isEditing else { return .ignored }
            selection = adjacentPage(in: SpotifyPlaylist.allCases, to: selection, offset: key.key == .leftArrow ? -1 : 1)
            return .handled
        }
        .onKeyPress(keys: [.return, .space]) { _ in
            guard browsing, !isEditing else { return .ignored }
            activate()
            return .handled
        }
        .onKeyPress(.escape) {
            guard isEditing else { return .ignored }
            finishEditing()
            return .handled
        }
    }

    private var linkEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Anslut \(selection.title)")
                .font(.system(size: 14, weight: .medium))
            Text("Öppna Spotifys lista, välj Dela och kopiera länken. Du behöver bara göra det en gång.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField("Spotify-spellistelänk", text: $link)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .padding(9)
                .background(.white.opacity(0.035), in: .rect(cornerRadius: 10))
                .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.12)) }
                .focused($editingLink)
                .onSubmit(saveLink)
                .onExitCommand { finishEditing() }
                .task { await Task.yield(); editingLink = true }
                .accessibilityLabel("Spotify-länk till \(selection.title)")
            HStack(spacing: 8) {
                Button("Sök i Spotify ↗") { service.search(selection) }
                    .buttonStyle(NotchControlStyle()).focusable()
                Spacer()
                Button("Tillbaka") { finishEditing() }
                    .buttonStyle(NotchControlStyle()).focusable()
                Button("Spara", action: saveLink)
                    .buttonStyle(NotchControlStyle()).focusable()
                    .disabled(link.isEmpty)
            }
            if let linkError {
                Text(linkError).font(.system(size: 9)).foregroundStyle(.orange)
            }
        }
    }

    private func activate() {
        guard !savedURI.isEmpty else { beginEditing(); return }
        Task { await service.perform(.playlist(savedURI)) }
    }

    private func beginEditing() {
        link = savedURI
        linkError = nil
        browsing = false
        isEditing = true
    }

    private func finishEditing() {
        editingLink = false
        isEditing = false
        browsing = true
    }

    private func saveLink() {
        guard let uri = SpotifyPlaylist.uri(from: link) else {
            linkError = "Använd en open.spotify.com/playlist-länk."
            return
        }
        switch selection {
        case .releaseRadar: releaseRadar = uri
        case .newMusicFriday: newMusicFriday = uri
        case .daylist: daylist = uri
        }
        finishEditing()
    }
}
