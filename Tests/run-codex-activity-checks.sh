#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
checks=".build/Checks"
mkdir -p "$checks/ModuleCache"
swiftc=(xcrun swiftc -swift-version 6 -module-cache-path "$checks/ModuleCache" -parse-as-library)
model=(smool/Applets/Codex/CodexProtocol.swift smool/Applets/Codex/CodexActivity.swift)
service=(smool/Applets/Codex/CodexTransport.swift smool/Applets/Codex/CodexClient.swift smool/Applets/Codex/CodexService.swift smool/Applets/Codex/CodexProjects.swift)
"${swiftc[@]}" "${model[@]}" Tests/CodexActivityChecks.swift -o "$checks/codex-activity"
"$checks/codex-activity"
"${swiftc[@]}" "${model[@]}" smool/Shared/FloatingComposer.swift smool/Applets/Codex/CodexActivityView.swift Tests/CodexActivityViewChecks.swift -o "$checks/codex-activity-view"
"$checks/codex-activity-view"
"${swiftc[@]}" "${model[@]}" "${service[@]}" smool/PageNavigation.swift smool/Applets/Codex/CodexAppletState.swift Tests/CodexServiceActivityChecks.swift -o "$checks/codex-service-activity"
"$checks/codex-service-activity"
"${swiftc[@]}" "${model[@]}" "${service[@]}" smool/PageNavigation.swift smool/Applets/Codex/CodexAppletState.swift Tests/CodexNavigationChecks.swift -o "$checks/codex-navigation"
"$checks/codex-navigation"
