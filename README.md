# smool

smool is a native macOS utility built around design and user experience. The goal is to bring access to apps and services to the notch through a simple interface you can navigate entirely with the keyboard. It should be fast, use minimal resources, and only appear when you need or want it.

This project is a work in progress. Features and integrations have not been decided yet.

## Development

The project uses SwiftUI and AppKit and requires macOS 26 and Xcode 26 or later. Open `smool.xcodeproj`, select the `smool` scheme, and run with ⌘R. No provisioning profile is needed to run locally.

You can also build and launch from the terminal:

```sh
xcodebuild -project smool.xcodeproj -scheme smool -configuration Debug -derivedDataPath .build build
open .build/Build/Products/Debug/smool.app
```

The app appears in the menu bar. Toggle the panel with ⌃⌥Space. Escape also closes it.

The home view shows the current time, a Swedish date, and battery status. Its Spotify and Codex cards open applets inside the notch. A single header row places the greeting to the left of four capsule tabs, followed by page indicators and an Actions menu. On notched displays this row sits below the camera. Applets use compact horizontal layouts, 144–176 points high. Players and Codex threads sit directly on black. Playlist tiles, the glass usage dial, and the composer provide elevation where needed. The calendar places its date beside an event card. The composer starts on one line and expands up to five lines before scrolling. The home tiles keep their layout.

`NotchTab` names the four destinations. `AppletPages` owns vertical page navigation. Clickable indicators in the header show the available pages without stacking cards. Each applet owns selection and actions inside its cards.

| Key | Action |
| --- | --- |
| ⌃⌥Space | Show or hide smool |
| ⌘1 / ⌘2 / ⌘3 / ⌘4 | Home / Spotify / Codex / Music |
| ⌘← / ⌘→ | Previous or next project in grouped Codex history; otherwise previous or next tab |
| ⌃Tab / ⌃⇧Tab | Next or previous tab |
| ⌘K | Open the Actions popover; arrows select, Return activates, Escape dismisses |
| ↑ / ↓ | Switch pages; select an event in the calendar |
| ← / → | Select a home card, playback control, playlist, or Codex thread |
| Return | Enter a card or activate the selection; the clock opens the calendar |
| ← / → in the calendar | Previous or next day |
| Space in the player | Play or pause |
| ⌘F in Codex | Search thread titles and prompts |
| Tab / Shift-Tab | Move through controls |
| ⌘Return | Send the message being composed |
| Escape | Leave details or editing, then close the panel |
| ? | Show or hide contextual keyboard help |

Arrow keys retain normal editing behavior inside text fields. Pages wrap at their edges. Tabs show icons without shortcut badges. The header greets the signed-in Mac user in Swedish. Reduced Motion and Reduced Transparency settings are respected, and the camera area stays black.

### Spotify

The player shows artwork, title, artist, a thin progress bar, play/pause, and next track in one row. Elapsed and remaining time are available through the progress bar’s tooltip and accessibility label. It uses macOS playback commands while Spotify is the current system player, and Spotify’s scripting dictionary for artwork, playlists, and playback when another app is active. If Spotify’s scripting process times out, the player uses the system snapshot until Spotify restarts. macOS may ask to allow smool to control Spotify. Allow it in System Settings → Privacy & Security → Automation if necessary. Polling runs only while this applet is visible. The integration never reads login credentials or tokens. Artwork uses a separate ephemeral network session with cookies and credential storage disabled; image URLs and redirects are restricted to Spotify’s HTTPS CDN domains.

The playlist page fetches current names and artwork for three public Spotify editorial selections through [Spotify’s oEmbed API](https://developer.spotify.com/documentation/embeds/reference/oembed). The selection IDs are bundled; metadata refreshes hourly or from Actions. Return plays the selected playlist without entering links. These are public selections, not personalized recommendations or the user's private library. No Spotify account tokens are read. Failed loads can be retried from Actions.

### Music and calendar

The Music tab follows the current macOS media player, including apps and browsers that publish Now Playing information. Left/right selects previous, play/pause, or next; Return activates the selection and Space toggles playback. It polls only while visible and verifies the player identity before sending a command. It uses the private `MRNowPlayingRequest` interface through a bounded `osascript` subprocess, so future macOS changes may require an update. The approach is also documented by [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter#useful-links). When the system supplies artwork it appears in the player; Spotify artwork also falls back to its scripting interface. Both music views blend the bottom light into the cover’s colors over 0.9 seconds. A small, blurred color map preserves the cover’s color distribution without keeping a second full-size image; Reduce Motion makes the change immediate.

Return on the home clock opens a daily agenda using EventKit. On first entry, Return on Connect requests calendar access from macOS. A large date sits beside one event at a time. Left/right moves between days and up/down selects an event. Return reveals its location or calendar; Return again opens Calendar. Escape leaves details, then returns home. Events are read locally and never modified. See [Apple’s EventKit access documentation](https://developer.apple.com/documentation/eventkit/accessing-the-event-store).

### Codex

Codex has pages for active threads, previous threads, and a glass ring showing the percentage remaining in the Codex seven-day window with its reset time. Other usage buckets are omitted. Usage refreshes automatically while visible; ⌘R remains available without a visible refresh button. One thread is visible at a time. Up/down switches between active threads, history, and usage. Left/right selects a thread, Return opens its composer, and ⌘Return sends. The glass input grows with the draft and contracts when text is removed. ⌘F searches titles and prompts. Actions exposes search, archived threads, and project grouping. In grouped history, ⌘←/⌘→ changes project; ⇧⌘P toggles grouping. Local favicons and app icons replace the thread glyph where available, with a folder fallback. Icon scanning is bounded, cached, and stays within the project. Draft text belongs to its recipient; drafts, searches, page selection, and thread selection survive tab changes.

The integration uses the installed Codex CLI for history and account limits, and the desktop app's local IPC connection to follow and message existing threads. Desktop IPC is versioned but private; an incompatible or unavailable connection produces an explicit error. History alone is never treated as evidence that a thread is running. Choosing an unconnected historical thread opens that exact thread in Codex, waits for its owner, and returns focus to smool before composing. smool does not resume a second competing session or answer approval requests on your behalf.

Run `Tests/run-checks.sh` for navigation, geometry, Spotify URL/privacy constraints, Codex protocol/state fixtures, and lighting checks. These checks never send prompts or change playback.

The bundled Spotify and Codex logos are the SVG assets from the [home design in Figma](https://www.figma.com/design/G2aym3oehQkvnPmGcSge4L/Smool?node-id=2-386), using the monochrome artwork supplied in the design. The logo library is [SVGL](https://svgl.app/).
