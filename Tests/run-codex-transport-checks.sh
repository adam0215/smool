#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
checks=".build/Checks"
mkdir -p "$checks/ModuleCache"
xcrun swiftc -swift-version 6 -module-cache-path "$checks/ModuleCache" -parse-as-library \
    smool/Applets/Codex/CodexProtocol.swift smool/Applets/Codex/CodexTransport.swift \
    Tests/CodexTransportChecks.swift -o "$checks/codex-transport"
"$checks/codex-transport"
