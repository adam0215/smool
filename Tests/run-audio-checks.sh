#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
checks=".build/Checks"
mkdir -p "$checks/ModuleCache" "$checks/renders"

swiftc=(xcrun swiftc -swift-version 6 -warnings-as-errors -module-cache-path "$checks/ModuleCache" -parse-as-library)
audio=(smool/Applets/Audio/AudioDevice.swift smool/Applets/Audio/CoreAudioDevices.swift smool/Applets/Audio/AudioService.swift)

"${swiftc[@]}" "${audio[@]}" Tests/AudioDeviceChecks.swift -o "$checks/audio-devices"
"$checks/audio-devices"

"${swiftc[@]}" "${audio[@]}" \
    smool/Applets/Audio/AudioApplet.swift smool/Applets/Audio/AudioAppletView.swift \
    smool/Applets/Applet.swift smool/HomeApp.swift \
    smool/Shared/Media/AlbumArtwork.swift smool/Shared/Media/MediaTrack.swift \
    smool/NotchLayout.swift smool/ScreenNotch.swift smool/Shared/ActionList.swift \
    smool/Shared/FloatingComposer.swift smool/AppletPadding.swift \
    Tests/AudioAppletRenderingChecks.swift -o "$checks/audio-render"
"$checks/audio-render" "$checks/renders"
