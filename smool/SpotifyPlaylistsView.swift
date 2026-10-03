import SwiftUI

struct SpotifyPlaylistsView: View {
    let service: SpotifyService
    @Binding var selection: SpotifyPlaylist
    @Binding var isEditing: Bool
    @Binding var link: String
    @State private var linkError: String?
    @AppStorage("spotify.playlist.releaseRadar") private var releaseRadar = ""
    @AppStorage("spotify.playlist.newMusicFriday") private var newMusicFriday = SpotifyPlaylist.newMusicFriday.defaultURI
    @AppStorage("spotify.playlist.daylist") private var daylist = ""
    @FocusState private var editingLink: Bool

    private var savedURI: String {
        switch selection {
        case .releaseRadar: releaseRadar
        case .newMusicFriday: newMusicFriday.isEmpty ? selection.defaultURI : newMusicFriday
        case .daylist: daylist
        }
    }

    var body: some View {
        VStack(spacing: 4) {
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
                                    .font(.system(size: 28, weight: .light))
                                    .foregroundStyle(selection == playlist ? .primary : .secondary)
                                Text(playlist.title)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.primary.opacity(selection == playlist ? 0.95 : 0.7))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 84)
                            .background(.white.opacity(selection == playlist ? 0.085 : 0.025), in: .rect(cornerRadius: 16))
                            .overlay {
                                RoundedRectangle(cornerRadius: 16)
                                    .strokeBorder(.white.opacity(selection == playlist ? 0.3 : 0.06), lineWidth: 0.5)
                            }
                            .contentShape(.rect(cornerRadius: 16))
                        }
                        .buttonStyle(.plain)
                        .focusable(false)
                        .accessibilityAddTraits(selection == playlist ? .isSelected : [])
                        .help("↵ Spela eller anslut · ⌘L Ändra länk")
                    }
                }

                Group {
                    Button("Ändra spellistelänk", action: beginEditing)
                        .keyboardShortcut("l", modifiers: .command)
                    Button("Spela eller anslut", action: activate)
                        .keyboardShortcut(.return, modifiers: [])
                        .disabled(service.isPerformingAction)
                }
                .hidden().frame(height: 0)
                if let error = service.actionError {
                    Text(error).font(.system(size: 9)).foregroundStyle(.orange).lineLimit(2)
                }
            }
        }
    }

    private var linkEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Anslut \(selection.title)")
                .font(.system(size: 14, weight: .medium))
            Text("Klistra in länken från Dela i Spotify.")
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
                Button { service.search(selection) } label: { ShortcutLabel("Sök i Spotify", keys: "⌘O") }
                    .keyboardShortcut("o", modifiers: .command)
                    .buttonStyle(NotchControlStyle()).focusable(false)
                Spacer()
                Button(action: saveLink) { ShortcutLabel("Spara", keys: "↵") }
                    .keyboardShortcut(.return, modifiers: [])
                    .buttonStyle(NotchControlStyle()).focusable(false)
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
        isEditing = true
    }

    private func finishEditing() {
        editingLink = false
        isEditing = false
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
