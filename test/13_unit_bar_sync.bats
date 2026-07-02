#!/usr/bin/env bats
# Unit tests for Hub Bar → AeroSpace padding sync.

load helpers/stubs

REPO_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
HUB_SCRIPT="$REPO_DIR/scripts/hub"

setup() {
    setup_stubs
    export STUB_CALLS="$HOME/stub_calls"
    make_stub_recording aerospace "" 0

    cat > "$HOME/.aerospace.toml" <<'TOML'
# AeroSpace config managed by hub
[gaps]
    outer.top =        31
TOML
}

teardown() {
    teardown_stubs
}

@test "bar-sync clamps stale fullscreen metric after fullscreen is off" {
    echo 16 > "$HOME/.config/hub/hub_bar_height"

    run "$HUB_SCRIPT" bar-sync

    [[ "$status" -eq 0 ]]
    grep -q 'outer.top =        55' "$HOME/.aerospace.toml"
    grep -q 'aerospace reload-config' "$STUB_CALLS"
}

@test "bar-sync ignores transient height when fullscreen is off" {
    echo 40 > "$HOME/.config/hub/hub_bar_height"
    echo 70 > "$HOME/.config/hub/hub_bar_outer_top"
    echo 80 > "$HOME/.config/hub/hub_bar_height_transient"

    run "$HUB_SCRIPT" bar-sync

    [[ "$status" -eq 0 ]]
    grep -q 'outer.top =        85' "$HOME/.aerospace.toml"
    [[ ! -f "$HOME/.config/hub/hub_bar_height_transient" ]]
}

@test "bar-sync falls back to bar height when normal outer-top metric is missing" {
    echo 40 > "$HOME/.config/hub/hub_bar_height"

    run "$HUB_SCRIPT" bar-sync

    [[ "$status" -eq 0 ]]
    grep -q 'outer.top =        55' "$HOME/.aerospace.toml"
}

@test "bar-sync uses transient height while fullscreen is on" {
    touch "$HOME/.config/hub/fullscreen"
    echo 16 > "$HOME/.config/hub/hub_bar_height"
    echo 70 > "$HOME/.config/hub/hub_bar_outer_top"
    echo 80 > "$HOME/.config/hub/hub_bar_height_transient"

    run "$HUB_SCRIPT" bar-sync

    [[ "$status" -eq 0 ]]
    grep -q 'outer.top =        95' "$HOME/.aerospace.toml"
}
