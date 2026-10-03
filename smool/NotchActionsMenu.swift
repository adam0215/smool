import SwiftUI

private struct NotchAction: Identifiable {
    let id: String
    let symbol: String
    var shortcut = ""
    var selected = false
    let perform: () -> Void
}

struct NotchActionsMenu: View {
    @Bindable var presentation: NotchPresentation

    var body: some View {
        Button { presentation.showsActions.toggle() } label: {
            Image(systemName: "ellipsis").font(.system(size: 14, weight: .semibold))
                .frame(width: 24, height: 24).contentShape(Rectangle())
        }
        .buttonStyle(.plain).focusable(false)
        .keyboardShortcut("k", modifiers: .command)
        .accessibilityLabel("Åtgärder")
        .help("Åtgärder · ⌘K")
        .popover(isPresented: $presentation.showsActions, arrowEdge: .bottom) {
            ActionList(actions: actions) { presentation.showsActions = false }
                .preferredColorScheme(.dark)
        }
    }

    private var actions: [NotchAction] {
        switch presentation.tab {
        case .codex: codexActions
        case .spotify: [
            NotchAction(id: "Spelare", symbol: "play.circle", selected: presentation.spotifyState.page == .player) { presentation.spotifyState.page = .player },
            NotchAction(id: "Spellistor", symbol: "music.note.list", selected: presentation.spotifyState.page == .playlists) { presentation.spotifyState.page = .playlists },
            NotchAction(id: "Öppna Spotify", symbol: "arrow.up.right") { presentation.spotify.openSpotify() },
            NotchAction(id: "Uppdatera", symbol: "arrow.clockwise", shortcut: "⌘R") { Task { await presentation.spotify.retry(); await presentation.spotifyState.catalog.load(force: true) } }
        ]
        case .music: [
            NotchAction(id: "Spela eller pausa", symbol: "playpause", shortcut: "␣") { Task { await presentation.music.perform(.togglePlayback) } },
            NotchAction(id: "Föregående låt", symbol: "backward.end") { Task { await presentation.music.perform(.previousTrack) } },
            NotchAction(id: "Nästa låt", symbol: "forward.end") { Task { await presentation.music.perform(.nextTrack) } }
        ]
        case .home: [
            NotchAction(id: presentation.showCalendar ? "Till klockan" : "Visa kalender", symbol: presentation.showCalendar ? "clock" : "calendar") { presentation.showCalendar.toggle() },
            NotchAction(id: "Öppna Kalender", symbol: "arrow.up.right") { presentation.calendar.openCalendar() }
        ]
        }
    }

    private var codexActions: [NotchAction] {
        let state = presentation.codexState
        let service = CodexService.shared
        var actions = [
            NotchAction(id: "Sök trådar", symbol: "magnifyingglass", shortcut: "⌘F") {
                if state.page == .usage { state.page = .history }
                state.scope = .search
            },
            NotchAction(id: "Visa arkiverade", symbol: "archivebox", shortcut: "⇧⌘A", selected: service.includesArchived) {
                state.page = .history
                state.scope = .deck
                Task { await service.setIncludesArchived(!service.includesArchived) }
            },
            NotchAction(id: "Gruppera per projekt", symbol: "folder", shortcut: "⇧⌘P", selected: state.groupsByProject) {
                state.groupsByProject.toggle()
                state.page = .history
                state.scope = .deck
            },
            NotchAction(id: "Aktiva trådar", symbol: "waveform", selected: state.page == .active) { state.scope = .deck; state.page = .active },
            NotchAction(id: "Tidigare trådar", symbol: "clock", selected: state.page == .history) { state.scope = .deck; state.page = .history },
            NotchAction(id: "Användning", symbol: "chart.pie", selected: state.page == .usage) { state.scope = .deck; state.page = .usage }
        ]
        if state.groupsByProject, state.page == .history, state.scope == .deck {
            actions.insert(contentsOf: [
                NotchAction(id: "Föregående projekt", symbol: "chevron.left", shortcut: "⌘←") { state.moveProject(-1, in: service.threads) },
                NotchAction(id: "Nästa projekt", symbol: "chevron.right", shortcut: "⌘→") { state.moveProject(1, in: service.threads) }
            ], at: 3)
        }
        return actions
    }
}

private struct ActionList: View {
    let actions: [NotchAction]
    let dismiss: () -> Void
    @State private var highlighted = 0
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Åtgärder").font(.caption.weight(.medium)).foregroundStyle(.secondary).padding(8)
            ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                Button { invoke(action) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: action.symbol).frame(width: 16)
                        Text(action.id)
                        Spacer(minLength: 12)
                        if action.selected { Image(systemName: "checkmark").font(.caption2) }
                        Text(action.shortcut).foregroundStyle(.secondary).font(.caption)
                    }
                    .font(.system(size: 12))
                    .padding(.horizontal, 10).padding(.vertical, 9)
                    .background(.white.opacity(highlighted == index ? 0.1 : 0), in: .rect(cornerRadius: 9))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain).focusable(false)
                .onHover { if $0 { highlighted = index } }
                .accessibilityAddTraits(action.selected ? .isSelected : [])
            }
        }
        .padding(8).frame(width: 280)
        .focusable(interactions: .edit).focused($focused).focusEffectDisabled()
        .task { await Task.yield(); focused = true }
        .onKeyPress(keys: [.upArrow, .downArrow], phases: [.down, .repeat]) { key in
            highlighted = (highlighted + (key.key == .upArrow ? actions.count - 1 : 1)) % actions.count
            return .handled
        }
        .onChange(of: actions.count) { _, count in highlighted = min(highlighted, max(0, count - 1)) }
        .onKeyPress(.return) {
            guard actions.indices.contains(highlighted) else { return .ignored }
            invoke(actions[highlighted])
            return .handled
        }
        .onKeyPress(.escape) { dismiss(); return .handled }
    }

    private func invoke(_ action: NotchAction) {
        dismiss()
        action.perform()
    }
}
