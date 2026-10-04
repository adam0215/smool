#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
checks="$(mktemp -d /tmp/smool-codex-composer.XXXXXX)"
trap 'rm -rf "$checks"' EXIT
# Snapshot the shared checkout so concurrent edits do not invalidate compilation.
cp -R smool "$checks/smool"
for name in CodexComposer CodexSessionRequest Applet CodexNavigation NotesApplet; do
    sed '/^@main$/d' "Tests/${name}Checks.swift" > "$checks/${name}Checks.swift"
done
cat > "$checks/Main.swift" <<'SWIFT'
@main
struct ComposerChecks {
    @MainActor static func main() throws {
        try CodexComposerChecks.main()
        try CodexSessionRequestChecks.main()
        AppletChecks.main()
        CodexNavigationChecks.main()
        try NotesAppletChecks.main()
    }
}
SWIFT
sources=()
while IFS= read -r source; do sources+=("$source"); done < <(rg --files "$checks/smool" --glob '*.swift' | rg -v '/SmoolApp.swift$' | sort)
xcrun swiftc -swift-version 6 -module-cache-path "$checks/ModuleCache" -parse-as-library \
    "${sources[@]}" "$checks/"*Checks.swift "$checks/Main.swift" -o "$checks/checks"
"$checks/checks"
