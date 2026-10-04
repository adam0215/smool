#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
checks="$(mktemp -d /tmp/smool-notch-file-drop.XXXXXX)"
trap 'rm -rf "$checks"' EXIT
xcrun swiftc -swift-version 6 -module-cache-path "$checks/ModuleCache" -parse-as-library \
    smool/NotchFileDrop.swift smool/NotchLayout.swift smool/ScreenNotch.swift \
    Tests/NotchFileDropChecks.swift -o "$checks/notch-file-drop"
"$checks/notch-file-drop"
xcrun swiftc -swift-version 6 -module-cache-path "$checks/ModuleCache" -parse-as-library \
    smool/NotchLayout.swift smool/ScreenNotch.swift Tests/NotchLayoutChecks.swift -o "$checks/layout"
"$checks/layout"
sources=()
while IFS= read -r source; do
    sources+=("$source")
done < <(rg --files smool -g '*.swift' | rg -v '/SmoolApp.swift$' | sort)
xcrun swiftc -swift-version 6 -module-cache-path "$checks/ModuleCache" -parse-as-library \
    "${sources[@]}" Tests/NotchFileDropIntegrationChecks.swift -o "$checks/integration"
"$checks/integration"
