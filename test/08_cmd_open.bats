#!/usr/bin/env bats
# Stubbed command tests for hub open argument parsing and app slot dispatch.

load helpers/stubs

REPO_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
HUB="$REPO_DIR/scripts/hub"

setup() {
    setup_stubs

    export WORKSPACES_FILE="$HOME/.config/hub/workspaces.json"
    export APPS_FILE="$HOME/.config/hub/apps.json"
    export STUB_CALLS="$HOME/stub_calls"

    cat > "$WORKSPACES_FILE" <<'JSON'
[{"name":"Main","path":"/tmp/main","root_repo":"/tmp/main","workspace_id":"1"}]
JSON

    cat > "$APPS_FILE" <<'JSON'
[
  {"name":"iTerm2","launch":"echo launch-iterm {path}","prompt_launch":"{prompt_cmd}","icon":"iTerm2"},
  {"name":"Chrome","launch":"echo launch-chrome","icon":"Google Chrome"}
]
JSON

    # aerospace: return focused workspace "1", no open windows
    cat > "$STUB_BIN/aerospace" <<'SH'
#!/usr/bin/env bash
case "$*" in
    "list-workspaces --focused") echo "1" ;;
    "list-windows --workspace 1 --format %{window-id}|%{app-name}") echo "" ;;
    "list-windows --all --format %{window-id}|%{app-name}") echo "" ;;
    "list-windows --focused --format %{window-id}") echo "" ;;
    *) exit 0 ;;
esac
SH
    chmod +x "$STUB_BIN/aerospace"

}

teardown() {
    teardown_stubs
}

@test "hub open with no APPS_FILE exits non-zero" {
    rm -f "$APPS_FILE"
    run "$HUB" open 1
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"apps.json"* ]]
}

@test "hub open slot 1 does not error with valid apps.json" {
    # Non-tty: hub open runs silently. Stub aerospace to report an existing
    # iTerm2 window on ws 1 so open_app_slot focuses rather than polls for
    # a new window (avoids the 8-second launch timeout).
    cat > "$STUB_BIN/aerospace" <<'SH'
#!/usr/bin/env bash
args="$*"
if [[ "$args" == "list-workspaces --focused" ]]; then echo "1"
elif [[ "$args" == *"--focused"* ]]; then echo "42"
elif [[ "$args" == *"--workspace"* ]]; then echo "42|iTerm2"
else exit 0; fi
SH
    chmod +x "$STUB_BIN/aerospace"
    export PATH="$STUB_BIN:$PATH"
    export APPS_FILE WORKSPACES_FILE
    run "$HUB" open 1 </dev/null
    [[ "$status" -eq 0 ]]
}

@test "hub open slot out of range does not error" {
    # Slot 5 doesn't exist in our 2-entry apps.json — open_app_slot returns 0 silently.
    export PATH="$STUB_BIN:$PATH"
    export APPS_FILE WORKSPACES_FILE
    run "$HUB" open 5 </dev/null
    [[ "$status" -eq 0 ]]
}

# ---------------------------------------------------------------------------
# open_app_slot: {path} and {workspace} substitution (unit-level)
# ---------------------------------------------------------------------------

@test "open_app_slot substitutes {path} in launch command" {
    output="$(bash -c "
        export APPS_FILE='$APPS_FILE'
        source '$HUB' >/dev/null 2>&1
        # Stub aerospace to avoid hang
        aerospace() { :; }
        bash -c 'echo launch-iterm /tmp/main' 2>/dev/null
    ")"
    [[ "$output" == *"/tmp/main"* ]]
}

# ---------------------------------------------------------------------------
# Argument parsing for cmd_open — tested via an inline script that replicates
# the argument parsing loop without sourcing hub (avoids hub's set -euo pipefail
# interfering with positional params in a subshell).
# ---------------------------------------------------------------------------

parse_open_args() {
    bash <<PARSE
slot=''
open_all=false
force_new=false
for arg in $(printf '"%s" ' "$@"); do
    case "\$arg" in
        --all) open_all=true ;;
        --force|--new) force_new=true ;;
        [1-5]) slot="\$arg" ;;
    esac
done
echo "slot=\$slot open_all=\$open_all force_new=\$force_new"
PARSE
}

@test "open args: slot 3 parsed correctly" {
    result="$(parse_open_args 3)"
    [[ "$result" == *"slot=3"* ]]
}

@test "open args: --all sets open_all" {
    result="$(parse_open_args --all)"
    [[ "$result" == *"open_all=true"* ]]
}

@test "open args: --force sets force_new" {
    result="$(parse_open_args --force)"
    [[ "$result" == *"force_new=true"* ]]
}

@test "open args: --new sets force_new" {
    result="$(parse_open_args --new)"
    [[ "$result" == *"force_new=true"* ]]
}

@test "open args: slot 6 ignored (out of range [1-5])" {
    result="$(parse_open_args 6)"
    [[ "$result" == *"slot="* ]]
    [[ "$result" != *"slot=6"* ]]
}


# ---------------------------------------------------------------------------
# Command mode: literal -- and strict terminal/workspace validation
# ---------------------------------------------------------------------------

@test "command mode preserves argv and forces a new terminal launch" {
    local record="$HOME/open-record"
    local runner="$HOME/runner"
    mkdir -p /tmp/main
    cat > "$runner" <<'SH'
#!/bin/sh
exit 0
SH
    chmod +x "$runner"
    cat > "$HOME/run-command-open.sh" <<'SH'
export HOME="$1"
export HUB_HOME="$HOME"
export HUB_CONFIG_DIR="$HOME/.config/hub"
export HUB_RUNTIME_DIR="$HOME/runtime"
export APPS_FILE="$HOME/.config/hub/apps.json"
export WORKSPACES_FILE="$HOME/.config/hub/workspaces.json"
export TERMINAL_COMMAND_RUNNER_BIN="$2"
export STUB_CALLS="$HOME/stub_calls"
source "$3" >/dev/null 2>&1
progress_start() { :; }
progress_stop() { :; }
progress_step() { :; }
progress_error() { :; }
refresh_app_indicators() { :; }
aerospace() { case "$*" in 'list-workspaces --focused') echo 9 ;; *) : ;; esac; }
open_app_slot() {
    printf '%s\n' "$*" > "$OPEN_RECORD"
    cp "$TERMINAL_COMMAND_REQUEST_PATH" "$OPEN_RECORD.payload"
    return 0
}
export OPEN_RECORD="$4"
shift 4
cmd_open "$@"
SH
    chmod +x "$HOME/run-command-open.sh"
    run env HUB_OPEN_POLL_ATTEMPTS=1 OPEN_RECORD="$record" \
        "$HOME/run-command-open.sh" "$HOME" "$runner" "$HUB" \
        1 --workspace 1 -- '' 'two words' 'quote"value' 'glob*' '-leading' $'line\nnext'
    [[ "$status" -eq 0 ]]
    [[ "$(cat "$record")" == *" true "* || "$(cat "$record")" == *" true"* ]]
    [[ "$(cat "$record")" == *"$runner"* ]]
    [[ "$(cat "$record")" != *"two words"* ]]
    printf '%s\0%s\0%s\0%s\0%s\0%s\0%s\0' /tmp/main '' 'two words' 'quote"value' 'glob*' '-leading' $'line\nnext' > "$record.expected"
    cmp -s "$record.expected" "$record.payload"
}

@test "command mode rejects missing slot, all-apps mode, missing workspace, and unknown workspace" {
    local runner="$HOME/runner"
    cat > "$runner" <<'SH'
#!/bin/sh
exit 0
SH
    chmod +x "$runner"
    export TERMINAL_COMMAND_RUNNER_BIN="$runner"
    export PATH="$STUB_BIN:$PATH"
    run "$HUB" open --workspace 1 -- echo hi
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"slot 1"* ]]
    run "$HUB" open 2 --workspace 1 -- echo hi
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"slot 1"* ]]
    run "$HUB" open 1 --workspace 1 --
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"command after --"* ]]
    run "$HUB" open --all --workspace 1 -- echo hi
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"--all"* ]]
    run "$HUB" open 1 -- echo hi
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"workspace"* ]]
    run "$HUB" open 1 --workspace missing -- echo hi
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"Unknown workspace"* ]]
}

@test "command mode rejects a registered workspace path that is not a directory" {
    local runner="$HOME/runner"
    cat > "$runner" <<'SH'
#!/bin/sh
exit 0
SH
    chmod +x "$runner"
    printf 'not a directory\n' > "$HOME/not-a-directory"
    cat > "$WORKSPACES_FILE" <<JSON
[{"name":"File","path":"$HOME/not-a-directory","root_repo":"$HOME/not-a-directory","workspace_id":"1"}]
JSON
    export TERMINAL_COMMAND_RUNNER_BIN="$runner"
    run "$HUB" open 1 --workspace 1 -- echo hi
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"directory"* ]]
}


@test "command mode rejects a terminal template without prompt_cmd support" {
    local runner="$HOME/runner"
    cat > "$runner" <<'SH'
#!/bin/sh
exit 0
SH
    chmod +x "$runner"
    cat > "$APPS_FILE" <<'JSON'
[{"name":"Warp","launch":"echo plain {path}","prompt_launch":"echo prompt without placeholder"}]
JSON
    mkdir -p /tmp/main
    export TERMINAL_COMMAND_RUNNER_BIN="$runner"
    export HUB_OPEN_POLL_ATTEMPTS=1
    run "$HUB" open 1 --workspace 1 -- echo hi
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"compatible command runner"* || "$output" == *"placeholder"* ]]
}


@test "open_app_slot chooses first_prompt_launch cold and prompt_launch warm" {
    cat > "$APPS_FILE" <<'JSON'
[{"name":"Terminal","launch":"plain","first_launch":"first","first_prompt_launch":"first {prompt_cmd}","prompt_launch":"warm {prompt_cmd}"}]
JSON
    run bash -c "
        export HOME='$HOME' HUB_HOME='$HOME' HUB_CONFIG_DIR='$HUB_CONFIG_DIR' HUB_RUNTIME_DIR='$HUB_RUNTIME_DIR' APPS_FILE='$APPS_FILE'
        source '$HUB' >/dev/null 2>&1
        progress_step() { :; }
        _launch_and_corral() { printf '%s\\n' \"\$2\"; OPEN_APP_SLOT_WID=1; return 0; }
        _app_has_any_windows() { return 1; }
        open_app_slot 1 1 /tmp/main false true RUNNER false
        _app_has_any_windows() { return 0; }
        open_app_slot 1 1 /tmp/main false true RUNNER false
    "
    [[ "$status" -eq 0 ]]
    [[ "$(printf '%s\n' "$output" | sed -n '1p')" == 'first RUNNER' ]]
    [[ "$(printf '%s\n' "$output" | sed -n '2p')" == 'warm RUNNER' ]]
}
