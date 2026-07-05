#!/usr/bin/env bats
# Unit tests for bounded menu-bar AppleScript waits.

load helpers/stubs

REPO_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

setup() {
    setup_stubs
    export STUB_CALLS="$HOME/stub_calls"
    make_stub_recording killall "" 0
    # shellcheck disable=SC1090
    source "$REPO_DIR/scripts/hub"
}

teardown() {
    teardown_stubs
}

@test "wait_for_menu_bar kills a stuck menu bar AppleScript" {
    export HUB_MENU_BAR_TIMEOUT=1
    sleep 30 &
    local stuck_pid=$!
    MENU_BAR_PID="$stuck_pid"

    run wait_for_menu_bar

    [[ "$status" -eq 0 ]]
    ! kill -0 "$stuck_pid" 2>/dev/null
    grep -q 'killall System Settings' "$STUB_CALLS"
}
