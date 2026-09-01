#!/usr/bin/env bats
# Unit tests for cmd_cluster_pin logic.

load helpers/stubs

REPO_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
HUB_SCRIPT="$REPO_DIR/scripts/hub"

pin_file() {
    echo "$HOME/.config/hub/cluster_pinned"
}

position_file() {
    echo "$HOME/.config/hub/cluster_position"
}

set_pin() {
    echo "$1" > "$(pin_file)"
}

run_cluster_pin() {
    bash -c "source '$HUB_SCRIPT' >/dev/null 2>&1; cmd_cluster_pin $*" >/dev/null 2>&1
}

setup() {
    setup_stubs
    export STUB_CALLS="$HOME/stub_calls"
    mkdir -p "$HOME/.config/hub"
}

teardown() {
    teardown_stubs
}

@test "cluster-pin on writes on" {
    run_cluster_pin on
    [[ "$(cat "$(pin_file)")" == "on" ]]
}

@test "cluster-pin off writes off" {
    set_pin on
    run_cluster_pin off
    [[ "$(cat "$(pin_file)")" == "off" ]]
}

@test "cluster-pin toggle defaults from off to on" {
    run_cluster_pin toggle
    [[ "$(cat "$(pin_file)")" == "on" ]]
}

@test "cluster-pin toggle switches on to off" {
    set_pin on
    run_cluster_pin toggle
    [[ "$(cat "$(pin_file)")" == "off" ]]
}

@test "cluster-pin off clears the saved drag position" {
    set_pin on
    echo "100,200" > "$(position_file)"
    run_cluster_pin off
    [[ ! -f "$(position_file)" ]]
}

@test "cluster-pin ignores invalid stored values and toggles from off" {
    set_pin unexpected
    run_cluster_pin toggle
    [[ "$(cat "$(pin_file)")" == "on" ]]
}

@test "cluster-pin with no args prints current state" {
    set_pin on
    output="$(bash -c "source '$HUB_SCRIPT' >/dev/null 2>&1; cmd_cluster_pin" 2>/dev/null)"
    [[ "$output" == *"on"* ]]
}

@test "cluster-pin invalid arg returns non-zero" {
    run bash -c "source '$HUB_SCRIPT' >/dev/null 2>&1; cmd_cluster_pin bogus" 2>/dev/null
    [[ "$status" -ne 0 ]]
}
