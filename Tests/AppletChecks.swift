import SwiftUI

@MainActor @Observable
private final class SampleApplet: Applet {
    let id = AppletID(rawValue: "sample")
    let title = "Sample"
    let icon = AppletIcon.symbol("star")
    let tint = Color.orange
    var contentHeight: CGFloat = 150
    var deactivations = 0

    func makeView(context: AppletContext, artwork: NSImage?) -> AnyView { AnyView(Text(title)) }
    func deactivate() { deactivations += 1 }
}

@main
struct AppletChecks {
    @MainActor static func main() {
        let suite = "smool.applet-checks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        let home = HomeApplet()
        let spotify = SpotifyApplet()
        let codex = CodexApplet()
        let music = MusicApplet()
        let sample = SampleApplet()
        let registry = AppletRegistry([home, spotify, codex, music, sample])
        let presentation = NotchPresentation(registry: registry, settings: settings)

        precondition(registry.applets.map(\.title) == ["Home", "Spotify", "Codex", "Music", "Sample"])
        precondition(registry.applet(for: HomeApp.spotify) === spotify)
        precondition(registry.applet(for: HomeApp.codex) === codex)
        precondition(registry.shortcutNumber(for: .spotify) == 2)
        precondition(registry.applet(number: 3) === codex)
        precondition(registry.applet(number: 0) == nil && registry.applet(number: 6) == nil)
        for applet in registry.applets {
            for offset in -20...20 {
                let next = registry.neighbor(of: applet.id, offset: offset)
                precondition(registry.neighbor(of: next, offset: -offset) == applet.id)
            }
        }
        precondition(registry.neighbor(of: home.id, offset: -1) == sample.id)
        precondition(presentation.contentHeight == 120)
        home.actions[0].perform()
        precondition(presentation.contentHeight == 168)
        home.dismissOverlay()
        precondition(home.showCalendar, "Closing the panel must preserve the calendar")

        presentation.select(spotify.id)
        precondition(!home.showCalendar && presentation.contentHeight == 156)
        precondition(spotify.handleArrow(.down, command: false))
        precondition(spotify.state.page == .playlists && spotify.pages[1].isSelected)
        spotify.pages[0].select()
        precondition(spotify.handleArrow(.left, command: false) && spotify.state.selectedControl == 1)
        precondition(!spotify.handleArrow(.right, command: true))
        precondition(spotify.state.selectedControl == 1)

        presentation.select(codex.id)
        codex.pages[2].select()
        precondition(presentation.contentHeight == 176 && codex.state.page == .usage)
        codex.state.scope = .search
        precondition(!codex.handleArrow(.down, command: false), "Search retains native arrow keys")
        let thread = CodexThread(json: .object(["id": .string("fixture"), "title": .string("Fixture")]))!
        codex.state.page = .active
        codex.state.scope = .composer(thread)
        codex.service.drafts[thread.id] = "Keep this draft"
        precondition(presentation.contentHeight == 300)
        precondition(!codex.handleArrow(.up, command: false), "Composer retains native arrow keys")
        codex.state.showsProjects = true
        precondition(codex.hasPresentedOverlay)
        presentation.select(music.id)
        precondition(!codex.state.showsProjects && presentation.contentHeight == 144)
        presentation.select(codex.id)
        precondition(codex.state.scope == .deck && presentation.contentHeight == 300)
        precondition(codex.service.drafts[thread.id] == "Keep this draft")
        codex.pages[0].select()
        precondition(codex.state.scope == .deck)
        precondition(codex.handleArrow(.up, command: false) && codex.state.page == .usage)

        presentation.select(sample.id)
        precondition(presentation.contentHeight == 150)
        sample.contentHeight = 200
        precondition(presentation.contentHeight == 200)
        presentation.select(sample.id)
        presentation.select(AppletID(rawValue: "removed"))
        precondition(presentation.selection == sample.id && sample.deactivations == 0)
        presentation.showsActions = true
        presentation.select(home.id)
        precondition(sample.deactivations == 1 && !presentation.showsActions)
        presentation.select(spotify.id)
        precondition(spotify.state.selectedControl == 1, "Applet state survives navigation")

        // Removing and reordering registrations changes all host navigation together.
        let reduced = AppletRegistry([home, sample, music])
        precondition(reduced.applet(for: HomeApp.spotify) == nil)
        precondition(reduced.applet(for: HomeApp.codex) == nil)
        precondition(reduced.shortcutNumber(for: .spotify) == nil)
        precondition(reduced.applet(number: 2) === sample)
        precondition(reduced.neighbor(of: home.id, offset: -1) == music.id)
        let reordered = AppletRegistry([home, codex, spotify])
        precondition(reordered.shortcutNumber(for: .codex) == 2)
        precondition(reordered.shortcutNumber(for: .spotify) == 3)
        let only = NotchPresentation(registry: AppletRegistry([sample]))
        precondition(only.selection == sample.id)
        precondition(only.registry.neighbor(of: sample.id, offset: -1) == sample.id)

        print("Passed: applet registration, removal, ordering, shortcuts, navigation, dynamic sizing, overlays, and retained state.")
    }
}
