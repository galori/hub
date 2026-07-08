#!/usr/bin/env bats
# Unit tests for Hub fullscreen menu-bar reveal padding metrics.

REPO_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
LIB_DIR="$REPO_DIR/lib"
THEME_SRC="$LIB_DIR/theme.swift"
HUB_BAR_SRC="$LIB_DIR/hub_bar.swift"

setup() {
    if [[ -n "${SKIP_SWIFT_COMPILE:-}" ]]; then
        skip "SKIP_SWIFT_COMPILE set"
    fi
    if ! command -v swiftc &>/dev/null; then
        skip "swiftc not available"
    fi
    export COMPILE_OUT
    COMPILE_OUT="$(mktemp -d)"
    export CLANG_MODULE_CACHE_PATH="$COMPILE_OUT/module-cache"
    mkdir -p "$CLANG_MODULE_CACHE_PATH"
}

teardown() {
    if [[ -n "${COMPILE_OUT:-}" ]]; then rm -rf "$COMPILE_OUT"; fi
}

compile_and_run_harness() {
    local harness="$COMPILE_OUT/main.swift"
    cp "$HUB_BAR_SRC" "$harness"
    cat >> "$harness" <<'SWIFT'
import Cocoa

func fail(_ message: String) -> Never {
    fputs(message + "\n", stderr)
    exit(1)
}

let singleRowMetric = fullscreenTransientAerospaceMetric(rows: 1, menuBarRevealInset: 24)
guard singleRowMetric == 64 else {
    fail("expected single-row revealed metric to include menu bar and Hub Bar height, got \(singleRowMetric)")
}

let doubleRowMetric = fullscreenTransientAerospaceMetric(rows: 2, menuBarRevealInset: 24)
guard doubleRowMetric == 104 else {
    fail("expected multi-row revealed metric to include menu bar and all Hub Bar rows, got \(doubleRowMetric)")
}

let clampedMetric = fullscreenTransientAerospaceMetric(rows: 0, menuBarRevealInset: -12)
guard clampedMetric == 40 else {
    fail("expected invalid rows/inset to clamp to one Hub Bar row, got \(clampedMetric)")
}
SWIFT

    swiftc -D HUB_BAR_TEST -O -o "$COMPILE_OUT/menu_bar_reveal_metric" \
        -framework Cocoa "$THEME_SRC" "$harness"
    "$COMPILE_OUT/menu_bar_reveal_metric"
}

@test "fullscreen menu-bar reveal metric includes both menu bar and Hub Bar height" {
    compile_and_run_harness
}
