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
"${swiftc[@]}" smool/Applets/Codex/CodexProtocol.swift smool/Applets/Codex/CodexActivity.swift smool/Applets/Codex/CodexTransport.swift smool/Applets/Codex/CodexClient.swift smool/Applets/Codex/CodexService.swift smool/Applets/Codex/CodexProjects.swift Tests/CodexProtocolChecks.swift -o "$checks/codex"
"$checks/codex"
"${swiftc[@]}" smool/HomeApp.swift smool/Applets/Home/HomeGlass.swift smool/HomeGlow.swift smool/NotchLayout.swift smool/ScreenNotch.swift Tests/HomeLightingChecks.swift -o "$checks/lighting"
"$checks/lighting" "$checks/renders"
"${swiftc[@]}" smool/NotchHeader.swift smool/NotchLayout.swift smool/ScreenNotch.swift Tests/NotchHeaderRenderingChecks.swift -o "$checks/header"
"$checks/header" "$checks/renders"

"${swiftc[@]}" smool/Shared/Media/MediaBridge.swift smool/Applets/Spotify/SpotifyService.swift smool/Shared/Media/MediaTrack.swift smool/Shared/Media/SpotifyBridge.swift smool/Shared/Media/SpotifyPlaylist.swift smool/Shared/Media/AlbumArtwork.swift smool/ArtworkGlow.swift Tests/ArtworkGlowChecks.swift -o "$checks/artwork-glow"
"$checks/artwork-glow" "$checks/renders"

"${swiftc[@]}" smool/Applets/Codex/ProjectIcon.swift Tests/ProjectIconChecks.swift -o "$checks/project-icons"
"$checks/project-icons"

"${swiftc[@]}" smool/Applets/Codex/CodexProtocol.swift smool/Applets/Codex/CodexProjects.swift Tests/CodexProjectsChecks.swift -o "$checks/codex-projects"
"$checks/codex-projects"

sources=()
while IFS= read -r source; do
    sources+=("$source")
done < <(find smool -name '*.swift' ! -name 'SmoolApp.swift' | sort)
"${swiftc[@]}" "${sources[@]}" Tests/AppletChecks.swift -o "$checks/applets"
"$checks/applets"

# Feature models run without changing devices, executing shortcuts or sending prompts.
"${swiftc[@]}" smool/Shared/Capture/SelectedTextCapture.swift Tests/SelectedTextChecks.swift -o "$checks/selected-text"
"$checks/selected-text"
"${swiftc[@]}" smool/Applets/Audio/AudioDevice.swift smool/Applets/Audio/AudioService.swift smool/Applets/Audio/CoreAudioDevices.swift Tests/AudioDeviceChecks.swift -o "$checks/audio-devices"
"$checks/audio-devices"
"${swiftc[@]}" smool/Applets/Notes/NotesStore.swift Tests/NotesStoreChecks.swift -o "$checks/notes-store"
"$checks/notes-store"
"${swiftc[@]}" smool/Applets/Files/FileShelfRepository.swift Tests/FileShelfChecks.swift -o "$checks/file-shelf"
"$checks/file-shelf"
"${swiftc[@]}" smool/Applets/Files/FileShelfRepository.swift smool/Applets/Files/FileShelfStore.swift Tests/FileShelfStoreChecks.swift -o "$checks/file-shelf-store"
"$checks/file-shelf-store"
"${swiftc[@]}" smool/Shared/Actions/SavedAction.swift smool/Shared/Actions/ActionLauncher.swift smool/Applets/QuickActions/QuickActionStore.swift smool/Applets/Workspaces/WorkspaceStore.swift Tests/SavedActionsChecks.swift -o "$checks/saved-actions"
"$checks/saved-actions"
bash Tests/run-codex-activity-checks.sh
bash Tests/run-timer-checks.sh

for name in HostSettings HostRendering NotesApplet AudioAppletRendering ActionApplets Integration Termination; do
    "${swiftc[@]}" "${sources[@]}" "Tests/${name}Checks.swift" -o "$checks/$name"
    "$checks/$name" "$checks/renders"
done
