#!/usr/bin/env bats
# Smoke tests: verify all Swift source files compile without errors.
# These are intentionally slow (real swiftc) — run separately if needed.
# Skip with: SKIP_SWIFT_COMPILE=1 bats test/

REPO_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
LIB_DIR="$REPO_DIR/lib"
THEME_SRC="$LIB_DIR/theme.swift"

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

# UI files require theme.swift — copy src to main.swift (multi-file Swift requires
# the entry-point file to be named main.swift).
compile_ui_file() {
    local src="$1"
    local name
    name="$(basename "$src" .swift)"
    local tmp_dir
    tmp_dir="$(mktemp -d)"
    cp "$src" "$tmp_dir/main.swift"
    swiftc -O -o "$COMPILE_OUT/$name" -framework Cocoa "$THEME_SRC" "$tmp_dir/main.swift" 2>&1
    local rc=$?
    rm -rf "$tmp_dir"
    return $rc
}

# CLI-only helpers have no UI and don't depend on theme.swift.
compile_cli_file() {
    local src="$1"
    local name
    name="$(basename "$src" .swift)"
    swiftc -O -o "$COMPILE_OUT/$name" -framework Cocoa "$src" 2>&1
}

@test "overlay.swift compiles without errors" {
    run compile_ui_file "$LIB_DIR/overlay.swift"
    [[ "$status" -eq 0 ]]
}

@test "new_workspace_dialog.swift compiles without errors" {
    run compile_ui_file "$LIB_DIR/new_workspace_dialog.swift"
    [[ "$status" -eq 0 ]]
}

@test "confirm_dialog.swift compiles without errors" {
    run compile_ui_file "$LIB_DIR/confirm_dialog.swift"
    [[ "$status" -eq 0 ]]
}

@test "rename_dialog.swift compiles without errors" {
    run compile_ui_file "$LIB_DIR/rename_dialog.swift"
    [[ "$status" -eq 0 ]]
}

@test "dashboard_dialog.swift compiles without errors" {
    run compile_ui_file "$LIB_DIR/dashboard_dialog.swift"
    [[ "$status" -eq 0 ]]
}

@test "output_window.swift compiles without errors" {
    run compile_ui_file "$LIB_DIR/output_window.swift"
    [[ "$status" -eq 0 ]]
}

@test "browser_ctl.swift compiles without errors" {
    run compile_cli_file "$LIB_DIR/browser_ctl.swift"
    [[ "$status" -eq 0 ]]
}

@test "http_handler.swift compiles without errors" {
    run compile_ui_file "$LIB_DIR/http_handler.swift"
    [[ "$status" -eq 0 ]]
}

@test "hub_toggle_app.swift compiles without errors" {
    run compile_cli_file "$LIB_DIR/hub_toggle_app.swift"
    [[ "$status" -eq 0 ]]
}

@test "hub_bar.swift compiles without errors" {
    run compile_ui_file "$LIB_DIR/hub_bar.swift"
    [[ "$status" -eq 0 ]]
}
