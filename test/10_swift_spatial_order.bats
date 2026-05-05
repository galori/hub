#!/usr/bin/env bats
# Smoke tests for the compiled spatial_order Swift binary.
# Skipped when SKIP_SWIFT_COMPILE=1.

REPO_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
SPATIAL_ORDER_SRC="$REPO_DIR/lib/spatial_order.swift"

setup() {
    if [[ -n "${SKIP_SWIFT_COMPILE:-}" ]]; then
        skip "SKIP_SWIFT_COMPILE set"
    fi
    COMPILE_OUT="$(mktemp -d)"
    BIN="$COMPILE_OUT/spatial_order"
    swiftc -O -o "$BIN" "$SPATIAL_ORDER_SRC" 2>/tmp/swiftc_err
}

teardown() {
    [[ -n "${COMPILE_OUT:-}" ]] && rm -rf "$COMPILE_OUT"
}

@test "spatial_order.swift compiles without errors" {
    [[ -x "$BIN" ]]
}

@test "spatial_order exits 0 with no arguments" {
    run "$BIN"
    [[ "$status" -eq 0 ]]
}

@test "spatial_order prints nothing for window IDs not on screen" {
    # Use an ID that definitely doesn't exist (0 is never a real window ID)
    run "$BIN" 0
    [[ "$status" -eq 0 ]]
    [[ -z "$output" ]]
}

@test "spatial_order exits 0 with multiple non-existent window IDs" {
    run "$BIN" 0 1 2
    [[ "$status" -eq 0 ]]
}
