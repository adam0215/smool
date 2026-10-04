#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
checks="$(mktemp -d /tmp/smool-codex-session.XXXXXX)"
trap 'rm -rf "$checks"' EXIT
cat > "$checks/peer" <<EOF
#!/bin/sh
exec /usr/bin/python3 "$PWD/Tests/CodexSessionFixture.py"
EOF
chmod +x "$checks/peer"
xcrun swiftc -swift-version 6 -warnings-as-errors -module-cache-path "$checks/ModuleCache" -parse-as-library \
    smool/Applets/Codex/CodexProtocol.swift smool/Applets/Codex/CodexActivity.swift \
    smool/Applets/Codex/CodexTransport.swift smool/Applets/Codex/CodexClient.swift \
    smool/Applets/Codex/CodexService.swift smool/Applets/Codex/CodexSession.swift smool/Applets/Codex/CodexProjects.swift \
    Tests/CodexSessionChecks.swift -o "$checks/session"
"$checks/session" "$checks/peer"
