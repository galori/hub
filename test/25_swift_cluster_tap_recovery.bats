#!/usr/bin/env bats
# Unit tests for the shift-cluster event-tap health check.
# The pure decision function is extracted from hub_bar.swift and compiled
# standalone, so the recovery policy is testable without a live CGEventTap.

REPO_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
HUB_BAR_SRC="$REPO_DIR/lib/hub_bar.swift"

setup() {
    if [[ -n "${SKIP_SWIFT_COMPILE:-}" ]]; then
        skip "SKIP_SWIFT_COMPILE set"
    fi
    if ! command -v swiftc &>/dev/null; then
        skip "swiftc not available"
    fi
    COMPILE_OUT="$(mktemp -d)"
    export CLANG_MODULE_CACHE_PATH="$COMPILE_OUT/module-cache"
    mkdir -p "$CLANG_MODULE_CACHE_PATH"

    sed -n '/>>> cluster-tap-recovery/,/<<< cluster-tap-recovery/p' "$HUB_BAR_SRC" \
        > "$COMPILE_OUT/main.swift"
    cat >> "$COMPILE_OUT/main.swift" <<'SWIFT'
for valid in [true, false] {
    for enabled in [true, false] {
        print("\(valid) \(enabled) \(clusterTapRecoveryAction(portIsValid: valid, tapIsEnabled: enabled))")
    }
}
SWIFT
    BIN="$COMPILE_OUT/cluster_tap_recovery"
    swiftc -O -o "$BIN" "$COMPILE_OUT/main.swift"
}

teardown() {
    if [[ -n "${COMPILE_OUT:-}" ]]; then rm -rf "$COMPILE_OUT"; fi
}

@test "a valid, enabled tap needs no recovery" {
    run "$BIN"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"true true healthy"* ]]
}

@test "a valid but disabled tap is re-enabled in place" {
    run "$BIN"
    [[ "$output" == *"true false reenable"* ]]
}

@test "an invalid mach port is recreated from scratch" {
    run "$BIN"
    [[ "$output" == *"false true recreate"* ]]
    [[ "$output" == *"false false recreate"* ]]
}

@test "hub_bar installs a periodic health check for the cluster tap" {
    grep -q 'clusterTapWatchdogTimer' "$HUB_BAR_SRC"
    grep -q 'checkClusterTapHealth' "$HUB_BAR_SRC"
}

@test "hub_bar re-checks the cluster tap on wake from sleep" {
    local wake_block
    wake_block="$(sed -n '/NSWorkspace.didWakeNotification/,/^            }/p' "$HUB_BAR_SRC")"
    [[ "$wake_block" == *'checkClusterTapHealth'* ]]
}
