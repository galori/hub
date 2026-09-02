#!/usr/bin/env bash
# Rebuilds the prebuilt Swift binaries checked into lib/prebuilt/ so that
# `hub install` works without Xcode or Command Line Tools on ordinary
# machines. Run this after changing any lib/*.swift source, then commit the
# resulting lib/prebuilt/ changes.
#
# Requires a local Swift toolchain (Xcode or Command Line Tools). Builds
# universal (arm64 + x86_64) binaries via lipo so the prebuilt binaries run
# on both Apple Silicon and Intel Macs.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LIB_DIR="$REPO_DIR/lib"
SWIFT_PREBUILT_DIR="$LIB_DIR/prebuilt"

source "$SCRIPT_DIR/lib/swift_prebuilt.sh"
source "$SCRIPT_DIR/lib/swift_tools_manifest.sh"

command -v swiftc >/dev/null 2>&1 || {
    echo "swiftc not found — install Xcode or the Command Line Tools to rebuild prebuilt binaries." >&2
    exit 1
}

mkdir -p "$SWIFT_PREBUILT_DIR"

build_one() {
    local key="$1" src="$2" extra="$3"
    local tmp_dir
    tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/hub-swift-prebuilt.XXXXXX")"

    local main_src="$src"
    if [[ -n "$extra" ]]; then
        # Multi-file Swift: only main.swift may have top-level code.
        cp "$src" "$tmp_dir/main.swift"
        main_src="$tmp_dir/main.swift"
    fi

    local -a extra_args=()
    [[ -n "$extra" ]] && extra_args=("$extra")

    echo "Building $key (arm64 + x86_64)..."
    swiftc -O -target arm64-apple-macos11.0 -o "$tmp_dir/$key-arm64" \
        -framework Cocoa "${extra_args[@]}" "$main_src"
    swiftc -O -target x86_64-apple-macos11.0 -o "$tmp_dir/$key-x86_64" \
        -framework Cocoa "${extra_args[@]}" "$main_src"
    lipo -create -output "$SWIFT_PREBUILT_DIR/$key" \
        "$tmp_dir/$key-arm64" "$tmp_dir/$key-x86_64"
    chmod +x "$SWIFT_PREBUILT_DIR/$key"

    if [[ -n "$extra" ]]; then
        swift_source_fingerprint "$src" "$extra" > "$SWIFT_PREBUILT_DIR/$key.sha256"
    else
        swift_source_fingerprint "$src" > "$SWIFT_PREBUILT_DIR/$key.sha256"
    fi

    rm -rf "$tmp_dir"
    echo "  -> $SWIFT_PREBUILT_DIR/$key"
}

for entry in "${SWIFT_TOOLS_MANIFEST[@]}"; do
    IFS='|' read -r key src extra <<<"$entry"
    build_one "$key" "$LIB_DIR/$src" "${extra:+$LIB_DIR/$extra}"
done

echo "Done. Review and commit lib/prebuilt/."
