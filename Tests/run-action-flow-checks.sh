#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
checks=".build/ActionsChecks"
mkdir -p "$checks/ModuleCache"
xcrun swiftc -swift-version 6 -warnings-as-errors -module-cache-path "$checks/ModuleCache" -parse-as-library \
    smool/Shared/Actions/*.swift smool/Applets/QuickActions/*.swift smool/Applets/Workspaces/*.swift \
    smool/Applets/Applet.swift smool/NotchLayout.swift smool/ScreenNotch.swift smool/HomeApp.swift \
    smool/Shared/Media/AlbumArtwork.swift smool/Shared/Media/MediaTrack.swift \
    smool/Shared/FloatingComposer.swift smool/NotchControlStyle.swift Tests/ActionFlowsChecks.swift \
    -o "$checks/action-flows"
"$checks/action-flows"
