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

The home view shows the current time, a Swedish date, and battery status. Its Spotify and Codex cards open applets inside the notch. Four capsule tabs stay visible beside the camera, with a subtle tint on the selected tab. Applets expand the panel downward; Home keeps its compact height.

`NotchTab` names the four destinations. `PageStack` displays a stack of glass cards and owns vertical page navigation. Each applet owns selection and actions inside its cards.

| Key | Action |
| --- | --- |
| ⌃⌥Space | Show or hide smool |
| ⌘1 / ⌘2 / ⌘3 / ⌘4 | Home / Spotify / Codex / Music |
| ⌘← / ⌘→ | Previous or next tab |
| ↑ / ↓ | Switch stack cards, or move through a focused Codex list |
| ← / → | Select a home card, playback control, playlist, or usage window |
| Return | Enter a card or activate the selection; the clock opens the calendar |
| ← / → in the calendar | Previous or next day |
| Space in the player | Play or pause |
| ⌘F in Codex | Search thread titles and prompts |
| Tab / Shift-Tab | Move through controls |
| ⌘Return | Send the message being composed |
| Escape | Step back through editor, list, and stack, then close the panel |

Arrow keys retain normal editing behavior inside text fields. Card stacks wrap at their edges. Tabs show icons without shortcut badges. The header greets the signed-in Mac user in Swedish. Reduced Motion and Reduced Transparency settings are respected, and the camera area stays black.

### Spotify

The player shows artwork, title, artist, elapsed and remaining time, play/pause, and next track. It uses macOS playback commands while Spotify is the current system player, and Spotify’s scripting dictionary for artwork, playlists, and playback when another app is active. If Spotify’s scripting process times out, the player uses the system snapshot until Spotify restarts. macOS may ask to allow smool to control Spotify. Allow it in System Settings → Privacy & Security → Automation if necessary. Polling runs only while this applet is visible. The integration never reads login credentials or tokens. Artwork uses a separate ephemeral network session with cookies and credential storage disabled; image URLs and redirects are restricted to Spotify’s HTTPS CDN domains.

The playlist card offers Release Radar, New Music Friday, and daylist. Spotify's Mac scripting interface does not expose the user's personalized playlist links. New Music Friday Sweden is ready to play. Release Radar and daylist need their personal Spotify playlist link once. Their Connect action opens a separate setup card with an explicitly labeled Spotify search. Saved links stay on this Mac.

### Music and calendar

The Music tab follows the current macOS media player, including apps and browsers that publish Now Playing information. Left/right selects previous, play/pause, or next; Return activates the selection and Space toggles playback. It polls only while visible and verifies the player identity before sending a command. It uses the private `MRNowPlayingRequest` interface through a bounded `osascript` subprocess, so future macOS changes may require an update. The approach is also documented by [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter#useful-links). When the system supplies artwork it appears in the player; Spotify artwork also falls back to its scripting interface. Both music views blend the bottom light into the cover’s colors over 0.9 seconds. A small, blurred color map preserves the cover’s color distribution without keeping a second full-size image; Reduce Motion makes the change immediate.

Return on the home clock opens a daily agenda using EventKit. macOS asks for calendar access on first entry. Left/right moves between days, Return opens that day in Calendar, and Escape returns home. Events are read locally and never modified. See [Apple’s EventKit access documentation](https://developer.apple.com/documentation/eventkit/accessing-the-event-store).

### Codex

Codex has cards for active threads, previous threads, and a ring showing the percentage remaining in the Codex seven-day window with its reset time. Other usage buckets are omitted. Usage refreshes automatically while visible; ⌘R remains available without a visible refresh button. Several threads are visible at once. Press Return to enter the list, use up and down to select, Return to compose, and ⌘Return to send. ⌘F searches titles and prompts. The archive button includes older archived threads. Draft text belongs to its recipient; drafts, searches, card selection, and list position survive tab changes.

The integration uses the installed Codex CLI for history and account limits, and the desktop app's local IPC connection to follow and message existing threads. Desktop IPC is versioned but private; an incompatible or unavailable connection produces an explicit error. History alone is never treated as evidence that a thread is running. Choosing an unconnected historical thread opens that exact thread in Codex, waits for its owner, and returns focus to smool before composing. smool does not resume a second competing session or answer approval requests on your behalf.

Run `Tests/run-checks.sh` for navigation, geometry, Spotify URL/privacy constraints, Codex protocol/state fixtures, and lighting checks. These checks never send prompts or change playback.

The bundled Spotify and Codex logos are the SVG assets from the [home design in Figma](https://www.figma.com/design/G2aym3oehQkvnPmGcSge4L/Smool?node-id=2-386), using the monochrome artwork supplied in the design. The logo library is [SVGL](https://svgl.app/).
