#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
checks=".build/Checks"
mkdir -p "$checks/ModuleCache" "$checks/renders"

swiftc=(xcrun swiftc -swift-version 6 -module-cache-path "$checks/ModuleCache" -parse-as-library)
"${swiftc[@]}" smool/AudioEnvelope.swift Tests/AudioEnvelopeChecks.swift -o "$checks/audio-envelope"
"$checks/audio-envelope"
"${swiftc[@]}" smool/NotchTab.swift Tests/NotchNavigationChecks.swift -o "$checks/navigation"
"$checks/navigation"
"${swiftc[@]}" smool/ScreenNotch.swift smool/NotchLayout.swift Tests/NotchLayoutChecks.swift -o "$checks/layout"
"$checks/layout"
"${swiftc[@]}" smool/MediaBridge.swift smool/SpotifyService.swift Tests/SpotifyChecks.swift -o "$checks/spotify"
"$checks/spotify"
"${swiftc[@]}" smool/CodexProtocol.swift smool/CodexTransport.swift smool/CodexClient.swift smool/CodexService.swift smool/CodexProjects.swift Tests/CodexProtocolChecks.swift -o "$checks/codex"
"$checks/codex"
"${swiftc[@]}" smool/HomeApp.swift smool/HomeGlass.swift smool/HomeGlow.swift smool/NotchLayout.swift smool/ScreenNotch.swift Tests/HomeLightingChecks.swift -o "$checks/lighting"
"$checks/lighting" "$checks/renders"
"${swiftc[@]}" smool/NotchHeader.swift smool/NotchLayout.swift smool/ScreenNotch.swift Tests/NotchHeaderRenderingChecks.swift -o "$checks/header"
"$checks/header" "$checks/renders"

"${swiftc[@]}" smool/MediaBridge.swift smool/SpotifyService.swift smool/AlbumArtwork.swift smool/ArtworkGlow.swift Tests/ArtworkGlowChecks.swift -o "$checks/artwork-glow"
"$checks/artwork-glow" "$checks/renders"

"${swiftc[@]}" smool/ProjectIcon.swift Tests/ProjectIconChecks.swift -o "$checks/project-icons"
"$checks/project-icons"

"${swiftc[@]}" smool/NotchTab.swift smool/CodexAppletState.swift smool/CodexProtocol.swift smool/CodexTransport.swift smool/CodexClient.swift smool/CodexService.swift smool/CodexProjects.swift Tests/CodexNavigationChecks.swift -o "$checks/codex-navigation"
"$checks/codex-navigation"

"${swiftc[@]}" smool/CodexProtocol.swift smool/CodexProjects.swift Tests/CodexProjectsChecks.swift -o "$checks/codex-projects"
"$checks/codex-projects"
