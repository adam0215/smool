#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
checks="$(mktemp -d /tmp/smool-notch-sizing.XXXXXX)"
trap 'rm -rf "$checks"' EXIT
sources=()
while IFS= read -r source; do sources+=("$source"); done < <(rg --files smool --glob '*.swift' | rg -v '/SmoolApp.swift$' | sort)
xcrun swiftc -swift-version 6 -module-cache-path .build/Checks/ModuleCache -parse-as-library \
    "${sources[@]}" Tests/NotchSizingChecks.swift -o "$checks/checks"
"$checks/checks" "$@"
