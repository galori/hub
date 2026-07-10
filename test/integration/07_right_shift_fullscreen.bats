#!/usr/bin/env bats
# Integration test: double-tapping right shift toggles AeroSpace fullscreen.

BATS_TEST_DIRNAME="${BATS_TEST_DIRNAME:-$(dirname "$0")}" 
load helpers

setup() {
    require_live_session
    INITIAL_FULLSCREEN="$(window_is_fullscreen)"
}

teardown() {
    local current
    current="$(window_is_fullscreen 2>/dev/null || true)"
    if [[ "$INITIAL_FULLSCREEN" =~ ^(true|false)$ && "$current" != "$INITIAL_FULLSCREEN" ]]; then
        aerospace fullscreen >/dev/null 2>&1 || true
    fi
}

window_is_fullscreen() {
    aerospace list-windows --focused --format '%{window-is-fullscreen}' 2>/dev/null
}

double_tap_right_shift() {
    swift -e 'import CoreGraphics
import Darwin
let source = CGEventSource(stateID: .hidSystemState)
for _ in 0..<2 {
    CGEvent(keyboardEventSource: source, virtualKey: 60, keyDown: true)?.post(tap: .cghidEventTap)
    usleep(50_000)
    CGEvent(keyboardEventSource: source, virtualKey: 60, keyDown: false)?.post(tap: .cghidEventTap)
    usleep(100_000)
}'
}

@test "right-shift double-tap toggles the focused AeroSpace window fullscreen" {
    local initial expected
    initial="$INITIAL_FULLSCREEN"
    [[ "$initial" == "true" || "$initial" == "false" ]]
    [[ "$initial" == "true" ]] && expected=false || expected=true

    double_tap_right_shift
    wait_for 5 "focused window fullscreen becomes $expected" \
        "[[ \"\$(aerospace list-windows --focused --format '%{window-is-fullscreen}' 2>/dev/null)\" == '$expected' ]]"

    double_tap_right_shift
    wait_for 5 "focused window fullscreen returns to $initial" \
        "[[ \"\$(aerospace list-windows --focused --format '%{window-is-fullscreen}' 2>/dev/null)\" == '$initial' ]]"
}
