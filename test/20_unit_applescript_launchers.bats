#!/usr/bin/env bats

REPO_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

setup() {
    if ! command -v osacompile &>/dev/null; then
        skip "osacompile not available"
    fi
    export COMPILE_OUT
    COMPILE_OUT="$(mktemp -d)"
}

teardown() {
    if [[ -n "${COMPILE_OUT:-}" ]]; then rm -rf "$COMPILE_OUT"; fi
}

compile_script() {
    local src="$1"
    local name
    name="$(basename "$src" .applescript)"
    osacompile -o "$COMPILE_OUT/$name.scpt" "$src"
}

@test "generic AppleScript launchers compile" {
    local script
    for script in \
        "$REPO_DIR/applescript/app_launcher_lib.applescript" \
        "$REPO_DIR/generic_app_launch.applescript" \
        "$REPO_DIR/generic_terminal_launch.applescript" \
        "$REPO_DIR/generic_browser_launch.applescript"; do
        run compile_script "$script"
        [[ "$status" -eq 0 ]]
    done
}
