#!/usr/bin/env bats
# Integration test: hub new — workspace with a custom post-setup script
#
# Like 02_new_workspace.bats, but the fixture repo includes a
# .superset/config.json "setup" key pointing to hub-test-setup.sh. That
# script touches .hub-test-marker in the worktree cwd. The test polls for
# the marker file because hub runs the setup command backgrounded/disowned.
#
# hub's setup invocation (scripts/hub:1057-1077):
#   ( /bin/zsh --no-rcs -c "cd <worktree>; <repo>/<setup-script>" ) &; disown
# So the marker appears asynchronously — we allow up to 30 seconds.
#
# IMPORTANT: AeroSpace focus switches to the new workspace mid-test.
# See README.md for session requirements.

# shellcheck disable=SC2034
BATS_TEST_DIRNAME="${BATS_TEST_DIRNAME:-$(dirname "$0")}"
load helpers

FIXTURE_REPO=""
WS_NAME=""
WS_ID=""

setup() {
    require_live_session

    FIXTURE_REPO="$BATS_TEST_TMPDIR/repo"
    make_fixture_repo "$FIXTURE_REPO" --with-setup

    WS_NAME="$(unique_ws_name)"
    WS_ID=""
}

teardown() {
    cleanup_workspace "$WS_ID"
}

# ---------------------------------------------------------------------------
@test "hub new with setup script creates the git worktree" {
    run "$(hub_bin)" new --path "$FIXTURE_REPO" --worktree "$WS_NAME" --no-apps
    echo "# status: $status" >&3
    echo "# output: $output" >&3
    [[ "$status" -eq 0 ]]

    [[ -d "$FIXTURE_REPO/worktrees/$WS_NAME" ]]
    git -C "$FIXTURE_REPO" worktree list | grep -q "$WS_NAME"
}

# ---------------------------------------------------------------------------
@test "hub new with setup script registers workspace in workspaces.json" {
    run "$(hub_bin)" new --path "$FIXTURE_REPO" --worktree "$WS_NAME" --no-apps
    [[ "$status" -eq 0 ]]

    local wsfile="$HOME/.config/hub/workspaces.json"
    [[ -f "$wsfile" ]]
    jq -e --arg n "$WS_NAME" '.[] | select(.name == $n)' "$wsfile" >/dev/null

    WS_ID="$(ws_id_for_name "$WS_NAME")"
    echo "# allocated workspace ID: $WS_ID" >&3
    [[ -n "$WS_ID" ]]
}

# ---------------------------------------------------------------------------
@test "hub new with setup script creates a bar_labels entry" {
    run "$(hub_bin)" new --path "$FIXTURE_REPO" --worktree "$WS_NAME" --no-apps
    [[ "$status" -eq 0 ]]

    WS_ID="$(ws_id_for_name "$WS_NAME")"
    [[ -n "$WS_ID" ]]

    local labels_file="$HOME/.config/hub/bar_labels"
    [[ -f "$labels_file" ]]
    grep -q "^$WS_ID:$WS_NAME:" "$labels_file"
    echo "# bar_labels entry found for $WS_ID:$WS_NAME" >&3
}

# ---------------------------------------------------------------------------
@test "hub new post-setup script writes marker file in the worktree" {
    run "$(hub_bin)" new --path "$FIXTURE_REPO" --worktree "$WS_NAME" --no-apps
    [[ "$status" -eq 0 ]]

    WS_ID="$(ws_id_for_name "$WS_NAME")"

    local marker="$FIXTURE_REPO/worktrees/$WS_NAME/.hub-test-marker"

    # hub runs the setup script backgrounded/disowned — poll for the marker.
    wait_for 30 "post-setup marker file exists at $marker" \
        "[ -f '$marker' ]"

    echo "# marker path: $marker" >&3
    [[ -f "$marker" ]]
}
