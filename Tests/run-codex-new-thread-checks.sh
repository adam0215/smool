#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
checks="$(mktemp -d /tmp/smool-codex-new-thread.XXXXXX)"
trap 'rm -rf "$checks"' EXIT
xcrun swiftc -swift-version 6 -warnings-as-errors -module-cache-path "$checks/ModuleCache" -parse-as-library \
    smool/Applets/Codex/CodexProtocol.swift smool/Applets/Codex/CodexActivity.swift \
    smool/Applets/Codex/CodexTransport.swift smool/Applets/Codex/CodexClient.swift \
    smool/Applets/Codex/CodexService.swift smool/Applets/Codex/CodexProjects.swift \
    Tests/CodexNewThreadChecks.swift -o "$checks/new-thread"
"$checks/new-thread"
