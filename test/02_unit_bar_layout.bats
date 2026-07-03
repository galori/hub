#!/usr/bin/env bats
# Unit tests for cmd_bar_layout logic.

load helpers/stubs

REPO_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
HUB_SCRIPT="$REPO_DIR/scripts/hub"

layout_file() {
    echo "$HOME/.config/hub/layout_mode"
}

set_layout() {
    echo "$1" > "$(layout_file)"
}

run_bar_layout() {
    bash -c "source '$HUB_SCRIPT' >/dev/null 2>&1; cmd_bar_layout $*" >/dev/null 2>&1
}

setup() {
    setup_stubs
    export STUB_CALLS="$HOME/stub_calls"
    mkdir -p "$HOME/.config/hub"
    make_stub_recording pkill "" 0
}

teardown() {
    teardown_stubs
}

@test "bar-layout shrink writes shrink" {
    run_bar_layout shrink
    [[ "$(cat "$(layout_file)")" == "shrink" ]]
}

@test "bar-layout expand writes expand" {
    run_bar_layout expand
    [[ "$(cat "$(layout_file)")" == "expand" ]]
}

@test "bar-layout toggle defaults from shrink to expand" {
    run_bar_layout toggle
    [[ "$(cat "$(layout_file)")" == "expand" ]]
}

@test "bar-layout toggle switches expand to shrink" {
    set_layout expand
    run_bar_layout toggle
    [[ "$(cat "$(layout_file)")" == "shrink" ]]
}

@test "bar-layout ignores invalid stored values and toggles from shrink" {
    set_layout unexpected
    run_bar_layout toggle
    [[ "$(cat "$(layout_file)")" == "expand" ]]
}

@test "bar-layout with no args prints current state" {
    set_layout expand
    output="$(bash -c "source '$HUB_SCRIPT' >/dev/null 2>&1; cmd_bar_layout" 2>/dev/null)"
    [[ "$output" == *"expand"* ]]
}

@test "bar-layout invalid arg returns non-zero" {
    run bash -c "source '$HUB_SCRIPT' >/dev/null 2>&1; cmd_bar_layout bogus" 2>/dev/null
    [[ "$status" -ne 0 ]]
}
