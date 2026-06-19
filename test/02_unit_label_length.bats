#!/usr/bin/env bats
# Unit tests for cmd_label_length logic

load helpers/stubs

REPO_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
HUB_SCRIPT="$REPO_DIR/scripts/hub"

set_current() {
    echo "$1" > "$HOME/.config/hub/label_maxlen"
}

set_labels() {
    # Each arg is a "ID:Name:" line
    printf '%s\n' "$@" > "$HOME/.config/hub/bar_labels"
}

setup() {
    setup_stubs
    mkdir -p "$HOME/.config/hub"
}

teardown() {
    teardown_stubs
}

# ---------------------------------------------------------------------------
# grow (+)
# ---------------------------------------------------------------------------

@test "label-length grow from 4 increments by 2" {
    set_current 4
    bash -c "source '$HUB_SCRIPT' >/dev/null 2>&1; cmd_label_length +" >/dev/null 2>&1
    result="$(cat "$HOME/.config/hub/label_maxlen")"
    [[ "$result" == "6" ]]
}

@test "label-length grow from unlimited stays unlimited" {
    set_current -1
    bash -c "source '$HUB_SCRIPT' >/dev/null 2>&1; cmd_label_length +" >/dev/null 2>&1
    result="$(cat "$HOME/.config/hub/label_maxlen")"
    [[ "$result" == "-1" ]]
}

@test "label-length grow accepts 'grow' alias" {
    set_current 2
    bash -c "source '$HUB_SCRIPT' >/dev/null 2>&1; cmd_label_length grow" >/dev/null 2>&1
    result="$(cat "$HOME/.config/hub/label_maxlen")"
    [[ "$result" == "4" ]]
}

@test "label-length grow to longest resets to unlimited (-1)" {
    set_labels "1:Hello:" "2:World:"
    set_current 3   # longest=5, 3+2=5 >= 5 → -1
    bash -c "source '$HUB_SCRIPT' >/dev/null 2>&1; cmd_label_length +" >/dev/null 2>&1
    result="$(cat "$HOME/.config/hub/label_maxlen")"
    [[ "$result" == "-1" ]]
}

# ---------------------------------------------------------------------------
# shrink (-)
# ---------------------------------------------------------------------------

@test "label-length shrink from 6 decrements by 2" {
    set_current 6
    bash -c "source '$HUB_SCRIPT' >/dev/null 2>&1; cmd_label_length -" >/dev/null 2>&1
    result="$(cat "$HOME/.config/hub/label_maxlen")"
    [[ "$result" == "4" ]]
}

@test "label-length shrink clamps to 0" {
    set_current 1
    bash -c "source '$HUB_SCRIPT' >/dev/null 2>&1; cmd_label_length -" >/dev/null 2>&1
    result="$(cat "$HOME/.config/hub/label_maxlen")"
    [[ "$result" == "0" ]]
}

@test "label-length shrink from unlimited uses longest-2" {
    set_labels "1:Hello:" "2:World:"   # longest = 5
    set_current -1
    bash -c "source '$HUB_SCRIPT' >/dev/null 2>&1; cmd_label_length -" >/dev/null 2>&1
    result="$(cat "$HOME/.config/hub/label_maxlen")"
    [[ "$result" == "3" ]]  # 5 - 2
}

@test "label-length shrink from unlimited with no labels stays at 0" {
    rm -f "$HOME/.config/hub/bar_labels"
    set_current -1
    bash -c "source '$HUB_SCRIPT' >/dev/null 2>&1; cmd_label_length -" >/dev/null 2>&1
    result="$(cat "$HOME/.config/hub/label_maxlen")"
    [[ "$result" == "-1" ]]  # longest=0, no change
}

@test "label-length shrink accepts 'shrink' alias" {
    set_current 8
    bash -c "source '$HUB_SCRIPT' >/dev/null 2>&1; cmd_label_length shrink" >/dev/null 2>&1
    result="$(cat "$HOME/.config/hub/label_maxlen")"
    [[ "$result" == "6" ]]
}

# ---------------------------------------------------------------------------
# set by number
# ---------------------------------------------------------------------------

@test "label-length accepts explicit number" {
    bash -c "source '$HUB_SCRIPT' >/dev/null 2>&1; cmd_label_length 10" >/dev/null 2>&1
    result="$(cat "$HOME/.config/hub/label_maxlen")"
    [[ "$result" == "10" ]]
}

@test "label-length number >= longest resets to unlimited" {
    set_labels "1:Hi:" "2:There:"   # longest = 5
    bash -c "source '$HUB_SCRIPT' >/dev/null 2>&1; cmd_label_length 99" >/dev/null 2>&1
    result="$(cat "$HOME/.config/hub/label_maxlen")"
    [[ "$result" == "-1" ]]
}

# ---------------------------------------------------------------------------
# display (no args)
# ---------------------------------------------------------------------------

@test "label-length with no args prints current state (unlimited)" {
    set_current -1
    output="$(bash -c "source '$HUB_SCRIPT' >/dev/null 2>&1; cmd_label_length" 2>/dev/null)"
    [[ "$output" == *"unlimited"* ]]
}

@test "label-length with no args prints 0 as workspace number only" {
    set_current 0
    output="$(bash -c "source '$HUB_SCRIPT' >/dev/null 2>&1; cmd_label_length" 2>/dev/null)"
    [[ "$output" == *"workspace number only"* ]]
}

@test "label-length with no args prints N chars" {
    set_current 7
    output="$(bash -c "source '$HUB_SCRIPT' >/dev/null 2>&1; cmd_label_length" 2>/dev/null)"
    [[ "$output" == *"7 chars"* ]]
}

# ---------------------------------------------------------------------------
# invalid input
# ---------------------------------------------------------------------------

@test "label-length with invalid arg returns non-zero" {
    run bash -c "source '$HUB_SCRIPT' >/dev/null 2>&1; cmd_label_length bogus" 2>/dev/null
    [[ "$status" -ne 0 ]]
}
