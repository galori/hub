# Shared helpers for shipping prebuilt Swift binaries so `hub install` does
# not require Xcode or Command Line Tools on ordinary machines. Sourced by
# scripts/hub and by scripts/build-swift-prebuilt.sh / scripts/check-swift-prebuilt.sh.
#
# Prebuilt binaries live in lib/prebuilt/<key> with a matching
# lib/prebuilt/<key>.sha256 fingerprint file. The fingerprint covers every
# source file that feeds that binary, so a stale prebuilt is detected instead
# of silently served. Local compilation with swiftc is opt-in via
# HUB_SHOULD_BUILD_SWIFT=1 and only used as a fallback.

: "${SWIFT_PREBUILT_DIR:=$LIB_DIR/prebuilt}"

# swift_source_fingerprint <src-file>... -> sha256 hex on stdout
swift_source_fingerprint() {
    cat "$@" 2>/dev/null | shasum -a 256 | awk '{print $1}'
}

# try_install_prebuilt_swift <key> <bin> <src-file>...
# Installs lib/prebuilt/<key> to $bin when its committed fingerprint matches
# the current source(s). Returns 1 (no output) when there is no usable
# prebuilt binary for the current sources.
try_install_prebuilt_swift() {
    local key="$1" bin="$2"
    shift 2
    local prebuilt="$SWIFT_PREBUILT_DIR/$key"
    local fp_file="$SWIFT_PREBUILT_DIR/$key.sha256"
    [[ -x "$prebuilt" && -f "$fp_file" ]] || return 1

    local current
    current="$(swift_source_fingerprint "$@")"
    [[ -n "$current" && "$current" == "$(cat "$fp_file" 2>/dev/null)" ]] || return 1

    mkdir -p "$(dirname "$bin")"
    cp "$prebuilt" "$bin"
    chmod +x "$bin"
    return 0
}

# swift_local_build_allowed <name> -> 0 if the caller should fall back to a
# local swiftc build; otherwise warns and returns 1.
swift_local_build_allowed() {
    local name="$1"
    if [[ "${HUB_SHOULD_BUILD_SWIFT:-}" == "1" ]]; then
        return 0
    fi
    warn "$name: no matching prebuilt binary is bundled for this source revision."
    warn "Set HUB_SHOULD_BUILD_SWIFT=1 to compile it locally (requires Xcode or Command Line Tools)."
    return 1
}
