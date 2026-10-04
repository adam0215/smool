#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
export LC_ALL=C

usage() {
    cat <<'USAGE'
Usage: Tests/run-checks.sh [CheckName ...] [-- test-arguments ...]
       Tests/run-checks.sh --list

With no names, run every Tests/*Checks.swift in a separate process.
Names accept an optional Checks suffix. Extra arguments require exactly one check.

Examples:
  Tests/run-checks.sh FilesApplet ActionFlows
  Tests/run-checks.sh NotchSizing -- --automatic-sizing

SMOOL_CHECKS_DIR overrides the build, resource and rendering directory.
USAGE
}

available=()
for source in Tests/*Checks.swift; do
    [[ -f "$source" ]] || continue
    name="${source##*/}"
    available+=("${name%Checks.swift}")
done
if [[ ${#available[@]} -eq 0 ]]; then
    echo "No Tests/*Checks.swift sources found." >&2
    exit 1
fi

selected=()
extra=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --help|-h) usage; exit 0 ;;
        --list) printf '%s\n' "${available[@]}"; exit 0 ;;
        --) shift; extra=("$@"); break ;;
        -*) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
        *)
            name="${1%Checks}"
            if [[ ! -f "Tests/${name}Checks.swift" || "$name" == */* ]]; then
                echo "Unknown check: $1. Use --list to see available checks." >&2
                exit 2
            fi
            for previous in "${selected[@]+${selected[@]}}"; do
                if [[ "$previous" == "$name" ]]; then
                    echo "Duplicate check: $name" >&2
                    exit 2
                fi
            done
            selected+=("$name")
            shift
            ;;
    esac
done
if [[ ${#extra[@]} -gt 0 && ${#selected[@]} -ne 1 ]]; then
    echo "Arguments after -- require exactly one named check." >&2
    exit 2
fi
if [[ ${#selected[@]} -eq 0 ]]; then selected=("${available[@]}"); fi

checks="${SMOOL_CHECKS_DIR:-.build/Checks/Runner}"
mkdir -p "$checks"
checks="$(cd "$checks" && pwd)"
if ! mkdir "$checks/.lock" 2>/dev/null; then
    echo "Checks directory is already in use: $checks" >&2
    echo "Use another SMOOL_CHECKS_DIR for a concurrent run. Remove .lock only if its runner has stopped." >&2
    exit 1
fi
printf '%s\n' "$$" > "$checks/.lock/pid"
staging=""
cleanup() {
    if [[ -n "$staging" ]]; then rm -rf "$staging"; fi
    rm -rf "$checks/.lock"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
staging="$(mktemp -d "$checks/.staging.XXXXXX")"
mkdir -p "$checks/ModuleCache" "$checks/tests" "$checks/renders"

sdk="$(xcrun --sdk macosx --show-sdk-path)"
# Keep the test target aligned with MACOSX_DEPLOYMENT_TARGET in smool.xcodeproj.
target="$(uname -m)-apple-macosx26.0"
swiftc=(xcrun --sdk macosx swiftc -sdk "$sdk" -target "$target" -swift-version 6
        -Onone -g -parse-as-library -module-cache-path "$checks/ModuleCache")

# Hash contents and paths, including the toolchain and this runner. A removed or
# renamed source invalidates the cache, even when modification times are preserved.
fingerprint() { shasum -a 256 | cut -d ' ' -f 1; }
toolchain="$({
    xcrun --sdk macosx --find swiftc
    xcrun --sdk macosx swiftc --version
    xcrun --sdk macosx --show-sdk-build-version
    printf '%s\n' "$sdk" "$target"
    shasum -a 256 Tests/run-checks.sh
} | fingerprint)"
sources=()
while IFS= read -r source; do sources+=("$source"); done < <(find smool -name '*.swift' ! -path 'smool/SmoolApp.swift' | sort)
module_key="$({ printf '%s\n' "$toolchain"; shasum -a 256 "${sources[@]}"; } | fingerprint)"
if [[ ! -f "$checks/support/libSmoolChecksSupport.dylib" || ! -f "$checks/support/SmoolChecksSupport.swiftmodule" ||
      ! -f "$checks/support/key" || "$(cat "$checks/support/key")" != "$module_key" ]]; then
    echo "Building shared app code (${#sources[@]} files)"
    mkdir "$staging/support"
    "${swiftc[@]}" -enable-testing -emit-library -emit-module -module-name SmoolChecksSupport \
        -emit-module-path "$staging/support/SmoolChecksSupport.swiftmodule" \
        -Xlinker -install_name -Xlinker @rpath/libSmoolChecksSupport.dylib \
        "${sources[@]}" -o "$staging/support/libSmoolChecksSupport.dylib"
    current_sources=()
    while IFS= read -r source; do current_sources+=("$source"); done < <(find smool -name '*.swift' ! -path 'smool/SmoolApp.swift' | sort)
    current_key="$({ printf '%s\n' "$toolchain"; shasum -a 256 "${current_sources[@]}"; } | fingerprint)"
    if [[ "$current_key" != "$module_key" ]]; then
        echo "App sources changed during compilation. Rerun after edits finish." >&2
        exit 1
    fi
    printf '%s\n' "$module_key" > "$staging/support/key"
    rm -rf "$checks/support"
    mv "$staging/support" "$checks/support"
fi

assets=()
while IFS= read -r asset; do assets+=("$asset"); done < <(find smool/Assets.xcassets -type f | sort)
resource_key="$({ printf '%s\n' "$toolchain"; shasum -a 256 "${assets[@]}"; } | fingerprint)"
if [[ ! -f "$checks/resources/Assets.car" || ! -f "$checks/resources/key" ||
      "$(cat "$checks/resources/key")" != "$resource_key" ]]; then
    echo "Building bundled images"
    mkdir "$staging/resources"
    xcrun --sdk macosx actool smool/Assets.xcassets --compile "$staging/resources" \
        --platform macosx --minimum-deployment-target 26.0 --target-device mac \
        --output-format human-readable-text
    current_assets=()
    while IFS= read -r asset; do current_assets+=("$asset"); done < <(find smool/Assets.xcassets -type f | sort)
    current_key="$({ printf '%s\n' "$toolchain"; shasum -a 256 "${current_assets[@]}"; } | fingerprint)"
    if [[ "$current_key" != "$resource_key" ]]; then
        echo "Images changed during compilation. Rerun after edits finish." >&2
        exit 1
    fi
    printf '%s\n' "$resource_key" > "$staging/resources/key"
    rm -rf "$checks/resources"
    mv "$staging/resources" "$checks/resources"
fi

# The first-turn fixture remains a separate Python peer, with no installed Codex
# process involved. Bash's %q protects paths containing spaces or shell characters.
printf '#!/bin/bash\nexec /usr/bin/python3 %q\n' "$PWD/Tests/CodexSessionFixture.py" > "$staging/session-peer"
chmod +x "$staging/session-peer"

for name in "${selected[@]}"; do
    source="Tests/${name}Checks.swift"
    app="$checks/tests/$name.app"
    test_key="$({ printf '%s\n' "$module_key" "$resource_key"; shasum -a 256 "$source"; } | fingerprint)"
    if [[ ! -x "$app/Contents/MacOS/checks" || ! -f "$app/key" || "$(cat "$app/key")" != "$test_key" ]]; then
        echo "Building $name"
        bundle="$staging/$name.app"
        mkdir -p "$bundle/Contents/MacOS"
        ln -s "$checks/resources" "$bundle/Contents/Resources"
        cat > "$bundle/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>checks</string>
<key>CFBundleIdentifier</key><string>se.smool.checks.$name</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
        "${swiftc[@]}" -I "$checks/support" -L "$checks/support" -lSmoolChecksSupport \
            -Xlinker -rpath -Xlinker @executable_path/../../../../support \
            "$source" -o "$bundle/Contents/MacOS/checks"
        current_key="$({ printf '%s\n' "$module_key" "$resource_key"; shasum -a 256 "$source"; } | fingerprint)"
        if [[ "$current_key" != "$test_key" ]]; then
            echo "$source changed during compilation. Rerun after edits finish." >&2
            exit 1
        fi
        printf '%s\n' "$test_key" > "$bundle/key"
        rm -rf "$app"
        mv "$bundle" "$app"
    fi

    echo "Running $name"
    if [[ "$name" == CodexSession ]]; then
        arguments=("$staging/session-peer")
    else
        arguments=("$checks/renders")
    fi
    # Execute directly so failures, signals and the transport fixture's self-launch
    # retain their normal process semantics. set -e preserves a failing exit code.
    "$app/Contents/MacOS/checks" "${arguments[@]}" "${extra[@]+${extra[@]}}"
done
printf 'Passed: %s checks. Renders: %s\n' "${#selected[@]}" "$checks/renders"
