/// Add or remove an applet here. The host derives its navigation and controls from this list.
@MainActor
func builtInApplets() -> AppletRegistry {
    AppletRegistry([
        HomeApplet(),
        SpotifyApplet(),
        CodexApplet(),
        MusicApplet(),
        FilesApplet(),
        NotesApplet(),
        AudioApplet(),
        TimersApplet(),
        WorkspacesApplet(),
        QuickActionsApplet()
    ])
}
