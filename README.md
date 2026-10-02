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

The home view shows the current time, a Swedish date, and battery status. Open Spotify with ⌘1 or Codex with ⌘2, or choose a card with the arrow keys or Tab and press Return or Space. If an app is not installed, its website opens instead.

The glass cards and lettering catch a shared light that brightens as the panel opens. Focus or hover over Spotify for green light and Codex for dark purple. The Home button or ⌘0 returns to blue. Battery percentage uses the standard label color. The light stays below a black band at the screen edge, and the corner cards follow the panel's curve. Reduced Motion and Reduced Transparency settings are respected.

The bundled Spotify and Codex logos are the SVG assets from the [home design in Figma](https://www.figma.com/design/G2aym3oehQkvnPmGcSge4L/Smool?node-id=2-386), using the monochrome artwork supplied in the design. The logo library is [SVGL](https://svgl.app/).
