# smool

smool is a native macOS utility built around design and user experience. The goal is to bring access to apps and services to the notch through a simple interface you can navigate entirely with the keyboard. It should be fast, use minimal resources, and only appear when you need or want it.

The app includes Codex activity, a file shelf, quick notes, audio devices, timers, workspaces, quick actions, Spotify, system music, and a calendar.

## Development

The project uses SwiftUI and AppKit and requires macOS 26 and Xcode 26 or later. Open `smool.xcodeproj`, select the `smool` scheme, and run with ⌘R. No provisioning profile is needed to run locally.

You can also build and launch from the terminal:

```sh
xcodebuild -project smool.xcodeproj -scheme smool -configuration Debug -derivedDataPath .build build
open .build/Build/Products/Debug/smool.app
```

The app appears in the menu bar. Toggle the panel with ⌃⌥Space. Escape also closes it.

The home view keeps the clock and up to three chosen applets. With two, the clock sits between them. With three, the clock sits on the left, followed by two rectangular tiles and the curved outer tile. Settings lets you choose, enable and reorder applets. Glass tabs show four applets at a time beside the camera. Moving beyond a group reveals the next group; navigation wraps to Home. The plain +N control opens the complete applet menu. Actions and Workspaces stay on the right as host tools, outside the applet tabs. The camera area stays black.

`Applets/BuiltInApplets.swift` registers applets. Each owns its services, state, view, actions, keyboard handling and content height. Navigation, home tiles and shortcuts use the same saved preferences. Ordinary controls sit on the background; floating actions and composers share native Liquid Glass with accessibility fallbacks.

| Key | Action |
| --- | --- |
| ⌃⌥Space | Show or hide smool |
| ⌘1–9 | First nine enabled applets in saved order |
| ⌘, | Open Settings |
| ⌃⌥C | Preview selected text, then save a note or prepare a Codex draft |
| ⌘← / ⌘→ | Previous or next project in grouped Codex history; otherwise previous or next tab |
| ⌃Tab / ⌃⇧Tab | Next or previous tab |
| ⌘K | Open Actions; arrows select, Return activates, Escape returns to the source view |
| ⌘⇧W | Open Workspaces |
| ↑ / ↓ | Switch pages; select an event in the calendar |
| ← / → | Select a home card, playback control, playlist, or Codex thread |
| Return | Enter a card or activate the selection; the clock opens the calendar |
| ← / → in the calendar | Previous or next day |
| Space in the player | Play or pause |
| ⌘F in Codex | Search thread titles and previews |
| ⌘N in Codex | Write to the selected thread, or focus the New thread composer |
| ⌘N in Notes, Timers or Workspaces | Create an item |
| ⌘⇧N in Actions | Save a new action |
| Space in the file shelf | Quick Look the selected file |
| Tab / Shift-Tab | Move through controls |
| Return in a Codex composer | Send the message; Shift-Return inserts a line break |
| Escape | Leave details or editing, then close the panel |
| ? | Show or hide contextual keyboard help |

Arrow keys retain normal editing behavior inside text fields. Pages wrap at their edges. Tabs show icons without shortcut badges. Reduced Motion and Reduced Transparency settings are respected, and the camera area stays black.

The expanded panel has black-tinted Liquid Glass below its opaque black header. A sharp, single-pixel lower rim brightens the content's own colors with color-dodge blending, without a white stroke or blurred halo. The rim shares the panel's geometry animations and stays mounted through opening, resizing, and closing. Reduce Transparency restores the solid black background and removes the reflective rim.

Reopening shows the last loaded content while services refresh. A shared in-memory cache keeps up to 24 decoded album and playlist covers with their gradient colors, so they are available on the first frame. The audio glow also retains its last frame until capture resumes. Codex retains a display snapshot while reconnecting, but commands still check the live connection. Calendar refreshes keep the loaded day's events visible. These caches last for the app session; a first visit still needs to load data. Media polling and audio capture stop when their views close. Timers retain a deadline alarm, and optional Codex status monitoring keeps a lightweight connection while the panel is closed.

### Applet architecture

Implementations live in separate folders under `smool/Applets`. Shared media adapters live in `smool/Shared/Media`; the floating composer and glass controls live in `smool/Shared/FloatingComposer.swift`. Workspace resources and quick actions use the same typed launch model in `smool/Shared/Actions`.

To add an applet:

1. Implement `Applet` with a stable `AppletID`, title, icon, tint, content height and `makeView`. Only this host boundary uses `AnyView`.
2. Provide pages, actions, background, status or keyboard handling where needed. Each `AppletAction` carries its title, operation and optional typed `AppletShortcut`; the shortcut supplies both its label and key binding. Applet-owned observable state drives the view.
3. Register its instance in `builtInApplets()`. It becomes available in Settings, navigation and the home tile picker.

The registry retains instances for the app session. `deactivate()` handles navigation away; `dismissOverlay()` closes transient UI when the panel closes. `handleBack()` handles one Escape step inside an applet and returns whether it consumed it. Views own their visible work through SwiftUI lifecycle.

`AppletContext` supplies layout, navigation and focus restoration to views. `AppletCommandContext` supplies live command providers to Notes and Actions when the host creates its applets, so commands work before a view renders. `AppletIntegration.swift` connects selected-text capture, Notes and Codex draft handoffs. `NotchPresentation.Destination` selects the applet, Workspaces, Settings, Actions with its source, or a capture preview. The underlying applet selection remains separate.

`HomePalette` in `HomeGlow.swift` defines the clock, Spotify and Codex colors. Home cards and applet backgrounds use these shared values; `BottomGlow` animates the color and position below the black camera band. See [host integration](Docs/UX-integration.md) and [Actions and Workspaces](Docs/UX-services.md) for keyboard and draft ownership.

`AppletStatus` carries a label, symbol, attention state and optional countdown deadline. The closed notch observes these snapshots without projecting hidden activity. Clicking a status calls `activateStatus()` and opens that applet. Timer and Codex status can be disabled independently in Settings. No status opens the panel or takes keyboard focus automatically.

### Files, notes and selected text

The file shelf stores up to 40 bookmarked references to original files. Dragging a file near the notch reveals a compact shelf target, including when the notch is closed. Leaving the area or cancelling hides it again without changing keyboard focus. Drop files there or use Add files to enter a path inside smool. Arrow keys select a file, Space opens an embedded Quick Look preview, and dragging exports its real file URL. Removing an item only removes the reference. Missing files remain visible so their absence is clear.

Notes save locally with debounced, serialized, atomic writes. Leaving an editor requests a save without blocking the interface. Quitting waits for pending edits; a failed write preserves the text and offers a retry. Deleting a note requires confirmation. Open in Codex opens a recipient picker and an editable draft. It never submits the note by itself.

⌃⌥C reads selected text from the foreground app using macOS Accessibility, before the notch takes focus. It previews the text and offers notes or Codex. Access is requested only from the explicit permission button. Unsupported apps and secure fields report a clear error; the feature does not read clipboard history or simulate Copy. Captured text is limited to 64 kB.

### Audio and timers

Audio lists available Core Audio output and input devices and changes the system defaults on request. Volume controls follow device capabilities; fixed-volume devices show a disabled control. Per-channel volume changes preserve balance. Property listeners run only while the applet is visible, without microphone recording.

Timers accept `25 min`, `90 s`, `2 h` or `1:30` for minutes and seconds. Bare numbers mean minutes. Opening Timers leaves the input unfocused; Tab enters it, Return starts the timer, and Escape leaves editing while preserving the draft. Up to eight timers can run, pause, resume or extend. Persisted deadlines handle sleep and relaunch; expired timers remain until acknowledged. A single deadline alarm handles completion, while only visible countdowns redraw each second. There are no focus sessions or activity tracking.

### Workspaces and quick actions

Workspaces collect chosen apps, folders, web links and Codex thread links. Open a single resource or the selected resources together. Quick actions store ordered app, folder, web and Apple Shortcuts entries. A shortcut is listed by name and stable identifier and only runs after explicit activation. Launch failures are shown without automatic retries. Local references use bookmarks; URLs and saved documents are validated before use.

Saved-action and workspace changes become visible after their atomic write succeeds. Failed saves leave the editor available for an explicit retry; failed deletions and moves are not replayed later. Quitting waits for pending work, including edits made while another store is saving, and reports failures before dismissing editors. A completed earlier failure does not permanently block a later Quit command.

Feature data lives in `~/Library/Application Support/smool`; preferences use the app's defaults. Invalid persisted documents are preserved instead of being overwritten with empty lists.

### Apple Screen Time

No Screen Time applet is included. The native macOS APIs available in the inspected SDK do not provide a supported route to the existing aggregate app/time data requested for smool. The project does not implement its own tracker. See [the API investigation](Docs/ScreenTime.md) for Apple references and availability checks.

### Spotify

The player shows artwork, title, artist, a thin progress bar, play/pause, and next track in one row. Elapsed and remaining time are available through the progress bar’s tooltip and accessibility label. It uses macOS playback commands while Spotify is the current system player, and Spotify’s scripting dictionary for artwork, playlists, and playback when another app is active. If Spotify’s scripting process times out, the player uses the system snapshot until Spotify restarts. macOS may ask to allow smool to control Spotify. Allow it in System Settings → Privacy & Security → Automation if necessary. Polling runs only while this applet is visible. The integration never reads login credentials or tokens. Artwork uses a separate ephemeral network session with cookies and credential storage disabled; image URLs and redirects are restricted to Spotify’s HTTPS CDN domains.

The playlist page fetches current names and artwork for three public Spotify editorial selections through [Spotify’s oEmbed API](https://developer.spotify.com/documentation/embeds/reference/oembed). The selection IDs are bundled; metadata refreshes hourly or from Actions. Return plays the selected playlist without entering links. These are public selections, not personalized recommendations or the user's private library. No Spotify account tokens are read. Failed loads can be retried from Actions.

### Music and calendar

The Music tab follows the current macOS media player, including apps and browsers that publish Now Playing information. Left/right selects previous, play/pause, or next; Return activates the selection and Space toggles playback. It polls only while visible and verifies the player identity before sending a command. It uses the private `MRNowPlayingRequest` interface through a bounded `osascript` subprocess, so future macOS changes may require an update. The approach is also documented by [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter#useful-links). When the system supplies artwork it appears in the player; Spotify artwork also falls back to its scripting interface. Both music views blend the bottom light into the cover’s colors over 0.9 seconds. A small, blurred color map preserves the cover’s color distribution without keeping a second full-size image; Reduce Motion makes the change immediate.

Return on the home clock opens a daily agenda using EventKit. On first entry, Return on Connect requests calendar access from macOS. A large date sits beside one event at a time. Left/right moves between days and up/down selects an event. Return reveals its location or calendar; Return again opens Calendar. Escape leaves details, then returns home. Events are read locally and never modified. See [Apple’s EventKit access documentation](https://developer.apple.com/documentation/eventkit/accessing-the-event-store).

### Codex

Codex shows the latest message, running tools, searches, thinking state and available public reasoning summaries. Finished tools disappear from the compact activity view. Active threads, history, New thread and weekly usage have separate pages. Left/right switches threads; Return opens the selected thread in Codex. ⌘N opens a narrow reply composer with a text field and send button. Return sends, Shift-Return inserts a line break, and Escape closes it without deleting its draft. A selected active thread remains available after completion.

New thread contains a project picker and composer. Sending creates a thread in the selected local project and submits the initial message through the installed Codex app-server. smool keeps that process alive through the first turn, including while the notch is closed. Follow-up messages during that turn steer the same process. After completion, the saved thread can be opened and continued in Codex. Failed attempts retain the draft and reuse an already-created thread on retry.

During a locally running turn, approval requests and questions appear in the activity view and Actions. Review them with the keyboard, allow or decline explicitly, or leave with Escape and return to the saved answer later. Stop turn is available in Actions and with ⌘. Opening the thread in Codex is deferred until the local turn ends. Unsupported client requests offer cancellation followed by continuing in Codex. Model and permission settings are inherited; smool never approves a request automatically.

Requests, approvals and failures have distinct status, with a link to the exact desktop thread when interaction belongs there. Notes and selected text enter the same explicit recipient picker. Live updates validate snapshot and patch revisions. `CodexActivityPresentation` keeps the latest message, current tools and available working summaries; completed tools leave the compact view. `CodexService` owns connections and schedules publication, while `CodexHistoryReader` owns cancellable newest-message reads and a bounded preview cache. History reads do not resume the thread. Closing the panel retains content. With background status enabled, the desktop connection continues; hidden activity is not repeatedly projected into UI.

⌘F searches thread titles and previews. Actions exposes archived threads and project grouping; ⌘P opens the project picker. Grouped history uses ⌘←/⌘→ for projects. Saved desktop project membership and worktree assignments remain supported. Usage shows the Codex seven-day window and its reset time. Images are represented as attachment markers, and very large or older activity remains available in the desktop app.

The integration uses the installed Codex CLI app-server for history, account limits and first turns, and the desktop app's local IPC connection to follow and message existing desktop threads. Desktop IPC is versioned but private; an incompatible or unavailable connection produces an explicit error. History alone is never treated as evidence that a thread is running. Choosing an unconnected historical thread opens that exact thread in Codex, waits for its owner, and returns focus to smool before composing. smool does not resume a second competing session.

Activity follows the public data in desktop snapshots. Searches, image tools and waits without a completion marker clear when the next activity arrives or the turn finishes. Raw MCP progress notifications that the desktop discards before broadcasting are unavailable through this connection.

## Checks

`Tests/run-checks.sh` is the entry point for model, persistence, protocol, navigation, rendering, keyboard and lifecycle checks. It discovers every `Tests/*Checks.swift`, compiles shared app code once, and runs each check in a separate process. Content hashes invalidate cached builds when sources, bundled images, the runner or toolchain change.

```sh
Tests/run-checks.sh
Tests/run-checks.sh --list
Tests/run-checks.sh FilesApplet ActionFlows
Tests/run-checks.sh CodexTransport CodexSession
Tests/run-checks.sh NotchSizing -- --automatic-sizing
```

The last command explicitly enables the alternative sizing diagnostic; the default suite uses the production sizing configuration. Arguments after `--` require exactly one named check. A failing build or check stops the run and returns its exit code.

Each new check keeps its own `@main` entry point and imports app types with `@testable import SmoolChecksSupport`. Rendering checks receive the output directory as their first argument. The Codex session check receives its Python peer executable instead; transport checks launch their own executable as the peer. These fixtures never contact real Codex threads. Launch fixtures do not open resources, Core Audio discovery is read-only, and checks do not run shortcuts or change playback or audio devices. Keyboard and sizing checks create native windows and need a logged-in macOS session. Home and host rendering checks capture only their own windows through ScreenCaptureKit so Liquid Glass content appears in the PNGs; view bitmap caching omits that composited content. Window capture requires an unlocked session with the display awake.

Builds and images live in `.build/Checks/Runner`, with rendered PNGs in its `renders` directory. Set `SMOOL_CHECKS_DIR` to use a different directory. The runner locks that directory for the duration of a run. Keep AppKit checks sequential so they do not compete for keyboard focus.

A successful build does not verify the interface. Inspect the rendered images and exercise the keyboard, drafts, Home colors, closed-notch spacing and Reduce Motion paths described in [UI regression checks](Docs/UX-review-findings.md).

The bundled Spotify and Codex logos are the SVG assets from the [home design in Figma](https://www.figma.com/design/G2aym3oehQkvnPmGcSge4L/Smool?node-id=2-386), using the monochrome artwork supplied in the design. The logo library is [SVGL](https://svgl.app/).
