#!/usr/bin/env bats
# Integration test: hub fullscreen padding
#
# Toggles real Hub fullscreen state and verifies AeroSpace's top outer gap
# keeps tiled windows below the native Hub Bar in both modes, including while
# the auto-hidden macOS menu bar is revealed by moving the cursor to the top.

# shellcheck disable=SC2034
BATS_TEST_DIRNAME="${BATS_TEST_DIRNAME:-$(dirname "$0")}"
load helpers

ORIGINAL_FULLSCREEN_STATE=""

setup() {
    require_live_session
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

assert_outer_top_clears_hub_bar() {
    local mode="$1"
    local required actual

    wait_for 15 "AeroSpace outer.top clears Hub Bar in $mode mode" \
        "required=\"\$(hub_bar_clearance_for_mode '$mode')\"; actual=\"\$(aerospace_outer_top)\"; [[ \"\$actual\" =~ ^[0-9]+$ && \"\$actual\" -eq \"\$required\" ]]"

    required="$(hub_bar_clearance_for_mode "$mode")"
    actual="$(aerospace_outer_top)"
    echo "# $mode required outer.top = $required; actual $actual" >&3
    [[ "$actual" -eq "$required" ]]
}

assert_outer_top_clears_hub_bar_window() {
    local description="$1"
    local bounds top height required actual

    wait_for 15 "$description" \
        'bounds="$(hub_bar_primary_bounds)"; top="${bounds%% *}"; height="${bounds##* }"; actual="$(aerospace_outer_top)"; [[ "$top" =~ ^[0-9]+$ && "$height" =~ ^[0-9]+$ && "$actual" =~ ^[0-9]+$ ]] && [[ "$actual" -eq $((top + height + 15)) ]]'

    bounds="$(hub_bar_primary_bounds)"
    top="${bounds%% *}"
    height="${bounds##* }"
    required=$((top + height + 15))
    actual="$(aerospace_outer_top)"
    echo "# required outer.top from Hub Bar window = $required; actual $actual; bounds top=$top height=$height" >&3
    [[ "$actual" -eq "$required" ]]
}

assert_menu_bar_auto_hide_value() {
    local expected="$1"
    local actual
    actual="$(menu_bar_auto_hide_value)"
    echo "# menu bar auto-hide expected $expected; actual $actual" >&3
    [[ "$actual" == "$expected" ]]
}

# ---------------------------------------------------------------------------
@test "hub-full-screen keeps AeroSpace windows below the Hub Bar" {
    run "$(hub_bin)" fullscreen on
    echo "# status: $status" >&3
    echo "# output: $output" >&3
    [[ "$status" -eq 0 ]]

    wait_for 15 "fullscreen state file exists" \
        "[[ -f '$HOME/.config/hub/fullscreen' ]]"
    assert_menu_bar_auto_hide_value Always
    assert_outer_top_clears_hub_bar fullscreen
}

# ---------------------------------------------------------------------------
@test "hub-full-screen expands AeroSpace top padding while the macOS menu bar is revealed" {
    move_cursor_to_main_display_center

    run "$(hub_bin)" fullscreen on
    echo "# status: $status" >&3
    echo "# output: $output" >&3
    [[ "$status" -eq 0 ]]

    wait_for 15 "fullscreen state file exists" \
        "[[ -f '$HOME/.config/hub/fullscreen' ]]"
    assert_menu_bar_auto_hide_value Always
    assert_outer_top_clears_hub_bar_window "AeroSpace outer.top clears Hub Bar before menu reveal"

    move_cursor_to_main_display_top_edge

    wait_for 15 "Hub Bar moves below revealed macOS menu bar" \
        'bounds="$(hub_bar_primary_bounds)"; top="${bounds%% *}"; [[ "$top" =~ ^[0-9]+$ && "$top" -gt 0 ]]'
    assert_outer_top_clears_hub_bar_window "AeroSpace outer.top clears revealed menu bar and Hub Bar"

    move_cursor_to_main_display_center
}

# ---------------------------------------------------------------------------
@test "hub-not-full-screen keeps AeroSpace windows below the Hub Bar" {
    run "$(hub_bin)" fullscreen off
    echo "# status: $status" >&3
    echo "# output: $output" >&3
    [[ "$status" -eq 0 ]]

    wait_for 15 "fullscreen state file is removed" \
        "[[ ! -f '$HOME/.config/hub/fullscreen' ]]"
    assert_menu_bar_auto_hide_value Never
    assert_outer_top_clears_hub_bar normal
}
