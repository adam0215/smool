#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
checks=".build/Checks"
mkdir -p "$checks/ModuleCache" "$checks/renders"
swiftc=(xcrun swiftc -swift-version 6 -module-cache-path "$checks/ModuleCache" -parse-as-library)

"${swiftc[@]}" smool/Applets/Timers/SmoolTimer.swift smool/Applets/Timers/TimerStore.swift \
    Tests/TimerChecks.swift -o "$checks/timers"
"$checks/timers"

"${swiftc[@]}" smool/Applets/Timers/*.swift smool/Applets/Applet.swift \
    smool/NotchLayout.swift smool/ScreenNotch.swift smool/HomeApp.swift \
    smool/Shared/Media/AlbumArtwork.swift smool/Shared/Media/MediaTrack.swift \
    smool/Shared/FloatingComposer.swift smool/NotchControlStyle.swift Tests/TimerAppletChecks.swift -o "$checks/timer-applet"
"$checks/timer-applet" "$checks/renders"
