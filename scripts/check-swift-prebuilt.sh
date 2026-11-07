#!/usr/bin/env bash
# CI guard: fails if any lib/*.swift source changed without refreshing its
# matching lib/prebuilt/<key> binary via scripts/build-swift-prebuilt.sh.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LIB_DIR="$REPO_DIR/lib"
SWIFT_PREBUILT_DIR="$LIB_DIR/prebuilt"

source "$SCRIPT_DIR/lib/swift_prebuilt.sh"
source "$SCRIPT_DIR/lib/swift_tools_manifest.sh"

stale=()
for entry in "${SWIFT_TOOLS_MANIFEST[@]}"; do
    IFS='|' read -r key src extras <<<"$entry"
    fp_file="$SWIFT_PREBUILT_DIR/$key.sha256"
    bin_file="$SWIFT_PREBUILT_DIR/$key"

    if [[ ! -f "$fp_file" || ! -x "$bin_file" ]]; then
        stale+=("$key (missing prebuilt binary or fingerprint)")
        continue
    fi

    extra_sources=()
    if [[ -n "$extras" ]]; then
        extra_names=()
        IFS=',' read -r -a extra_names <<<"$extras"
        for extra_name in "${extra_names[@]}"; do
            extra_sources+=("$LIB_DIR/$extra_name")
        done
    fi
    if [[ ${#extra_sources[@]} -gt 0 ]]; then
        current="$(swift_source_fingerprint "$LIB_DIR/$src" "${extra_sources[@]}")"
    else
        current="$(swift_source_fingerprint "$LIB_DIR/$src")"
    fi
    committed="$(cat "$fp_file")"
    if [[ "$current" != "$committed" ]]; then
        stale+=("$key (source changed since prebuilt was built)")
    fi
done

if [[ "${#stale[@]}" -gt 0 ]]; then
    echo "Stale prebuilt Swift binaries detected:" >&2
    printf '  - %s\n' "${stale[@]}" >&2
    echo >&2
    echo "Run scripts/build-swift-prebuilt.sh and commit lib/prebuilt/." >&2
    exit 1
fi

echo "All prebuilt Swift binaries match their sources."
