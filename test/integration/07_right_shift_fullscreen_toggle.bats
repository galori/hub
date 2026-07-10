#!/usr/bin/env bats
# Integration test: right-shift double-tap fullscreen toggle
#
# The Hub Bar listens globally for two isolated right-shift presses within
# ~400ms (no other key struck in between) and toggles hub fullscreen — a
# faster alternative to the AeroSpace ctrl-alt-f binding that doesn't require
# leaving the home row. See lib/hub_bar.swift's handleRightShiftTap.

# shellcheck disable=SC2034
BATS_TEST_DIRNAME="${BATS_TEST_DIRNAME:-$(dirname "$0")}"
load helpers

ORIGINAL_FULLSCREEN_STATE=""

setup() {
    require_live_session

    pgrep -f "hub_bar" >/dev/null || skip "hub_bar is not running — run test 1 (hub up) first"

    if [[ -f "$HOME/.config/hub/fullscreen" ]]; then
        ORIGINAL_FULLSCREEN_STATE="on"
    else
        ORIGINAL_FULLSCREEN_STATE="off"
    fi
}

teardown() {
    local hub
    hub="$(hub_bin)"

    if [[ "$ORIGINAL_FULLSCREEN_STATE" == "on" ]]; then
        "$hub" fullscreen on >/dev/null 2>&1 || true
    else
        "$hub" fullscreen off >/dev/null 2>&1 || true
    fi
}

# ---------------------------------------------------------------------------
@test "right-shift double-tap toggles fullscreen on" {
    run "$(hub_bin)" fullscreen off
    echo "# status: $status" >&3
    echo "# output: $output" >&3
    [[ "$status" -eq 0 ]]
    wait_for 15 "fullscreen state file is removed" \
        "[[ ! -f '$HOME/.config/hub/fullscreen' ]]"

    post_right_shift_double_tap 150

    wait_for 5 "fullscreen state file exists after right-shift double-tap" \
        "[[ -f '$HOME/.config/hub/fullscreen' ]]"
}

# ---------------------------------------------------------------------------
@test "right-shift double-tap toggles fullscreen off" {
    run "$(hub_bin)" fullscreen on
    echo "# status: $status" >&3
    echo "# output: $output" >&3
    [[ "$status" -eq 0 ]]
    wait_for 15 "fullscreen state file exists" \
        "[[ -f '$HOME/.config/hub/fullscreen' ]]"

    post_right_shift_double_tap 150

    wait_for 5 "fullscreen state file is removed after right-shift double-tap" \
        "[[ ! -f '$HOME/.config/hub/fullscreen' ]]"
}

# ---------------------------------------------------------------------------
@test "right-shift taps separated by a real keystroke do not toggle fullscreen" {
    run "$(hub_bin)" fullscreen off
    echo "# status: $status" >&3
    echo "# output: $output" >&3
    [[ "$status" -eq 0 ]]
    wait_for 15 "fullscreen state file is removed" \
        "[[ ! -f '$HOME/.config/hub/fullscreen' ]]"

    post_right_shift_double_tap 200 --with-escape-between

    # Give the Hub Bar a moment to (not) react, then assert it never toggled.
    sleep 1
    [[ ! -f "$HOME/.config/hub/fullscreen" ]]
}

# ---------------------------------------------------------------------------
@test "right-shift taps more than 400ms apart do not toggle fullscreen" {
    run "$(hub_bin)" fullscreen off
    echo "# status: $status" >&3
    echo "# output: $output" >&3
    [[ "$status" -eq 0 ]]
    wait_for 15 "fullscreen state file is removed" \
        "[[ ! -f '$HOME/.config/hub/fullscreen' ]]"

    post_right_shift_double_tap 800

    sleep 1
    [[ ! -f "$HOME/.config/hub/fullscreen" ]]
}
