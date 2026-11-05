#!/usr/bin/env bats
# Integration test: run an exact command in a new Terminal window on a target workspace.
#
# This test uses the real Terminal preset, Hub request runner, and AeroSpace
# window corralling. It must run only on the dedicated live runner.

# shellcheck disable=SC2034
BATS_TEST_DIRNAME="${BATS_TEST_DIRNAME:-$(dirname "$0")}"
load helpers

FIXTURE_REPO=""
WS_NAME=""
WS_ID=""
WS_PATH=""
ORIGIN_WS=""
NEW_TERMINAL_WID=""
MARKER=""
APPS_FILE=""
APPS_BACKUP=""
APPS_EXISTED=false
TESTING_BANNER_STARTED=false

terminal_window_ids() {
    aerospace list-windows --all --format '%{window-id}|%{app-name}' 2>/dev/null \
        | awk -F'|' '$2 == "Terminal" {print $1}' \
        | sort -n
}

setup() {
    require_live_session

    FIXTURE_REPO="$BATS_TEST_TMPDIR/repo"
    make_fixture_repo "$FIXTURE_REPO"
    WS_NAME="$(unique_ws_name)"
    MARKER="$BATS_TEST_TMPDIR/terminal-command-marker"
    ORIGIN_WS="$(aerospace list-workspaces --focused 2>/dev/null || true)"

    APPS_FILE="$HOME/.config/hub/apps.json"
    APPS_BACKUP="$BATS_TEST_TMPDIR/apps.json"
    if [[ -f "$APPS_FILE" ]]; then
        cp "$APPS_FILE" "$APPS_BACKUP"
        APPS_EXISTED=true
    fi

    local repo_dir
    repo_dir="$(cd "$(dirname "$(hub_bin)")/.." && pwd)"
    jq -c '[."com.apple.Terminal"]' "$repo_dir/config/app_presets.json" > "$APPS_FILE"

    if "$(hub_bin)" testing-banner start "Testing terminal command" >/dev/null 2>&1; then
        TESTING_BANNER_STARTED=true
    fi
}

teardown() {
    if [[ -n "$NEW_TERMINAL_WID" ]]; then
        aerospace close --window-id "$NEW_TERMINAL_WID" 2>/dev/null || true
        wait_for 10 "the command test Terminal window to close" \
            "! aerospace list-windows --all --format '%{window-id}' 2>/dev/null | grep -qx '$NEW_TERMINAL_WID'" || true
    fi

    if [[ -z "$WS_ID" && -n "$WS_NAME" ]]; then
        WS_ID="$(ws_id_for_name "$WS_NAME" 2>/dev/null || true)"
    fi
    cleanup_workspace "$WS_ID"

    if [[ "$APPS_EXISTED" == "true" ]]; then
        cp "$APPS_BACKUP" "$APPS_FILE"
    else
        rm -f "$APPS_FILE"
    fi

    [[ -n "$ORIGIN_WS" ]] && aerospace workspace "$ORIGIN_WS" 2>/dev/null || true
    if [[ "$TESTING_BANNER_STARTED" == "true" ]]; then
        "$(hub_bin)" testing-banner stop >/dev/null 2>&1 || true
    fi
}

@test "hub open runs in the registered workspace and corrals the exact Terminal window" {
    run "$(hub_bin)" new --path "$FIXTURE_REPO" --worktree "$WS_NAME" --no-apps
    echo "# hub new status: $status" >&3
    echo "# hub new output: $output" >&3
    [[ "$status" -eq 0 ]]

    WS_ID="$(ws_id_for_name "$WS_NAME")"
    [[ -n "$WS_ID" ]]
    WS_PATH="$(jq -r --arg id "$WS_ID" '.[] | select(.workspace_id == $id) | .path' "$HOME/.config/hub/workspaces.json")"
    [[ -d "$WS_PATH" ]]
    [[ "$ORIGIN_WS" != "$WS_ID" ]]
    aerospace workspace "$ORIGIN_WS"

    local before_ids after_ids
    before_ids="$(terminal_window_ids)"

    run env HUB_OPEN_POLL_ATTEMPTS=40 HUB_OPEN_POLL_INTERVAL=0.25 \
        "$(hub_bin)" open 1 --workspace "$WS_ID" -- \
        /bin/sh -c 'pwd > "$1"' sh "$MARKER"
    echo "# hub open status: $status" >&3
    echo "# hub open output: $output" >&3
    [[ "$status" -eq 0 ]]

    wait_for 20 "the command marker" "[[ -f '$MARKER' ]]"
    [[ "$(cat "$MARKER")" == "$WS_PATH" ]]

    after_ids="$(terminal_window_ids)"
    NEW_TERMINAL_WID="$(comm -13 \
        <(printf '%s\n' "$before_ids") \
        <(printf '%s\n' "$after_ids") | head -1)"
    [[ -n "$NEW_TERMINAL_WID" ]]

    local new_window_workspace
    new_window_workspace="$(aerospace list-windows --all \
        --format '%{window-id}|%{app-name}|%{workspace}' 2>/dev/null \
        | awk -F'|' -v wid="$NEW_TERMINAL_WID" '$1 == wid && $2 == "Terminal" {print $3; exit}')"
    [[ "$new_window_workspace" == "$WS_ID" ]]
}
