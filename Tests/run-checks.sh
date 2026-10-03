#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
checks=".build/Checks"
mkdir -p "$checks/ModuleCache" "$checks/renders"

swiftc=(xcrun swiftc -swift-version 6 -module-cache-path "$checks/ModuleCache" -parse-as-library)
"${swiftc[@]}" smool/AudioEnvelope.swift Tests/AudioEnvelopeChecks.swift -o "$checks/audio-envelope"
"$checks/audio-envelope"
"${swiftc[@]}" smool/AudioEnvelope.swift smool/AudioSpectrumAnalyzer.swift Tests/AudioSpectrumChecks.swift -o "$checks/audio-spectrum"
"$checks/audio-spectrum"
"${swiftc[@]}" smool/AudioEnvelope.swift smool/MusicGlow.swift Tests/MusicGlowChecks.swift -o "$checks/music-glow"
"$checks/music-glow" "$checks/renders"
"${swiftc[@]}" smool/PageNavigation.swift Tests/NotchNavigationChecks.swift -o "$checks/navigation"
"$checks/navigation"
"${swiftc[@]}" smool/ScreenNotch.swift smool/NotchLayout.swift Tests/NotchLayoutChecks.swift -o "$checks/layout"
"$checks/layout"
"${swiftc[@]}" smool/Shared/Media/MediaBridge.swift smool/Applets/Spotify/SpotifyService.swift smool/Shared/Media/MediaTrack.swift smool/Shared/Media/SpotifyBridge.swift smool/Shared/Media/SpotifyPlaylist.swift Tests/SpotifyChecks.swift -o "$checks/spotify"
"$checks/spotify"
"${swiftc[@]}" smool/Applets/Codex/CodexProtocol.swift smool/Applets/Codex/CodexTransport.swift smool/Applets/Codex/CodexClient.swift smool/Applets/Codex/CodexService.swift smool/Applets/Codex/CodexProjects.swift Tests/CodexProtocolChecks.swift -o "$checks/codex"
"$checks/codex"
"${swiftc[@]}" smool/HomeApp.swift smool/Applets/Home/HomeGlass.swift smool/HomeGlow.swift smool/NotchLayout.swift smool/ScreenNotch.swift Tests/HomeLightingChecks.swift -o "$checks/lighting"
"$checks/lighting" "$checks/renders"
"${swiftc[@]}" smool/NotchHeader.swift smool/NotchLayout.swift smool/ScreenNotch.swift Tests/NotchHeaderRenderingChecks.swift -o "$checks/header"
"$checks/header" "$checks/renders"

"${swiftc[@]}" smool/Shared/Media/MediaBridge.swift smool/Applets/Spotify/SpotifyService.swift smool/Shared/Media/MediaTrack.swift smool/Shared/Media/SpotifyBridge.swift smool/Shared/Media/SpotifyPlaylist.swift smool/Shared/Media/AlbumArtwork.swift smool/ArtworkGlow.swift Tests/ArtworkGlowChecks.swift -o "$checks/artwork-glow"
"$checks/artwork-glow" "$checks/renders"

"${swiftc[@]}" smool/Applets/Codex/ProjectIcon.swift Tests/ProjectIconChecks.swift -o "$checks/project-icons"
"$checks/project-icons"

"${swiftc[@]}" smool/PageNavigation.swift smool/Applets/Codex/CodexAppletState.swift smool/Applets/Codex/CodexProtocol.swift smool/Applets/Codex/CodexTransport.swift smool/Applets/Codex/CodexClient.swift smool/Applets/Codex/CodexService.swift smool/Applets/Codex/CodexProjects.swift Tests/CodexNavigationChecks.swift -o "$checks/codex-navigation"
"$checks/codex-navigation"

"${swiftc[@]}" smool/Applets/Codex/CodexProtocol.swift smool/Applets/Codex/CodexProjects.swift Tests/CodexProjectsChecks.swift -o "$checks/codex-projects"
"$checks/codex-projects"

sources=()
while IFS= read -r source; do
    sources+=("$source")
done < <(find smool -name '*.swift' ! -name 'SmoolApp.swift' | sort)
"${swiftc[@]}" "${sources[@]}" Tests/AppletChecks.swift -o "$checks/applets"
"$checks/applets"
