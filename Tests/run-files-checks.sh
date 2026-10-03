#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
checks=".build/FilesChecks"
mkdir -p "$checks/ModuleCache"
xcrun swiftc -swift-version 6 -module-cache-path "$checks/ModuleCache" -parse-as-library \
    smool/Applets/Files/*.swift smool/Applets/Applet.swift \
    smool/NotchLayout.swift smool/ScreenNotch.swift smool/HomeApp.swift \
    smool/Shared/Media/AlbumArtwork.swift smool/Shared/Media/MediaTrack.swift \
    smool/Shared/FloatingComposer.swift Tests/FilesAppletChecks.swift -o "$checks/files-applet"
"$checks/files-applet"
