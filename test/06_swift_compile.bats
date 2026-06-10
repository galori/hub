#!/usr/bin/env bats
# Smoke tests: verify all Swift source files compile without errors.
# These are intentionally slow (real swiftc) — run separately if needed.
# Skip with: SKIP_SWIFT_COMPILE=1 bats test/

REPO_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
LIB_DIR="$REPO_DIR/lib"

setup() {
    if [[ -n "${SKIP_SWIFT_COMPILE:-}" ]]; then
        skip "SKIP_SWIFT_COMPILE set"
    fi
    if ! command -v swiftc &>/dev/null; then
        skip "swiftc not available"
    fi
    export COMPILE_OUT
    COMPILE_OUT="$(mktemp -d)"
}

teardown() {
    if [[ -n "${COMPILE_OUT:-}" ]]; then rm -rf "$COMPILE_OUT"; fi
}

compile_swift_file() {
    local src="$1"
    local name
    name="$(basename "$src" .swift)"
    swiftc -O -o "$COMPILE_OUT/$name" -framework Cocoa "$src" 2>&1
}

@test "overlay.swift compiles without errors" {
    run compile_swift_file "$LIB_DIR/overlay.swift"
    [[ "$status" -eq 0 ]]
}

@test "new_workspace_dialog.swift compiles without errors" {
    run compile_swift_file "$LIB_DIR/new_workspace_dialog.swift"
    [[ "$status" -eq 0 ]]
}

@test "confirm_dialog.swift compiles without errors" {
    run compile_swift_file "$LIB_DIR/confirm_dialog.swift"
    [[ "$status" -eq 0 ]]
}

@test "rename_dialog.swift compiles without errors" {
    run compile_swift_file "$LIB_DIR/rename_dialog.swift"
    [[ "$status" -eq 0 ]]
}

@test "dashboard_dialog.swift compiles without errors" {
    run compile_swift_file "$LIB_DIR/dashboard_dialog.swift"
    [[ "$status" -eq 0 ]]
}

@test "output_window.swift compiles without errors" {
    run compile_swift_file "$LIB_DIR/output_window.swift"
    [[ "$status" -eq 0 ]]
}

@test "browser_ctl.swift compiles without errors" {
    run compile_swift_file "$LIB_DIR/browser_ctl.swift"
    [[ "$status" -eq 0 ]]
}

@test "http_handler.swift compiles without errors" {
    run compile_swift_file "$LIB_DIR/http_handler.swift"
    [[ "$status" -eq 0 ]]
}
