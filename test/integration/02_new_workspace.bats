#!/usr/bin/env bats
# Integration test: hub new — plain workspace creation
#
# Creates a real worktree-based hub workspace from a temporary fixture repo,
# asserts the worktree, workspaces.json entry, and bar label all land
# correctly, then cleans up via hub remove.
#
# IMPORTANT: This test switches AeroSpace focus to the newly created workspace
# ID mid-run. This is expected and intentional — it mirrors production behaviour.
# Do not run on a machine where you are actively working. See README.md.

# shellcheck disable=SC2034
BATS_TEST_DIRNAME="${BATS_TEST_DIRNAME:-$(dirname "$0")}"
load helpers

# Variables shared between setup and teardown
FIXTURE_REPO=""
WS_NAME=""
WS_ID=""

setup() {
    require_live_session

    # Create a temp fixture repo (BATS_TEST_TMPDIR is auto-cleaned by Bats)
    FIXTURE_REPO="$BATS_TEST_TMPDIR/repo"
    make_fixture_repo "$FIXTURE_REPO"

    WS_NAME="$(unique_ws_name)"
    WS_ID=""  # populated after hub new
}

teardown() {
    cleanup_workspace "$WS_ID"
    # BATS_TEST_TMPDIR (and FIXTURE_REPO inside it) is removed by Bats after the test.
}

# ---------------------------------------------------------------------------
@test "hub new creates the git worktree on disk" {
    run "$(hub_bin)" new --path "$FIXTURE_REPO" --worktree "$WS_NAME" --no-apps
    echo "# status: $status" >&3
    echo "# output: $output" >&3
    [[ "$status" -eq 0 ]]

    # Worktree dir must exist at <repo>/worktrees/<name>
    [[ -d "$FIXTURE_REPO/worktrees/$WS_NAME" ]]

    # Must show up in git worktree list
    git -C "$FIXTURE_REPO" worktree list | grep -q "$WS_NAME"
}

# ---------------------------------------------------------------------------
@test "hub new registers the workspace in workspaces.json" {
    run "$(hub_bin)" new --path "$FIXTURE_REPO" --worktree "$WS_NAME" --no-apps
    [[ "$status" -eq 0 ]]

    local wsfile="$HOME/.config/hub/workspaces.json"
    [[ -f "$wsfile" ]]

    # Entry must exist
    jq -e --arg n "$WS_NAME" '.[] | select(.name == $n)' "$wsfile" >/dev/null

    # Capture the allocated ID for the bar label assertion and teardown
    WS_ID="$(ws_id_for_name "$WS_NAME")"
    echo "# allocated workspace ID: $WS_ID" >&3
    [[ -n "$WS_ID" ]]
}

# ---------------------------------------------------------------------------
@test "hub new workspace appears in hub list output" {
    run "$(hub_bin)" new --path "$FIXTURE_REPO" --worktree "$WS_NAME" --no-apps
    [[ "$status" -eq 0 ]]

    WS_ID="$(ws_id_for_name "$WS_NAME")"

    run "$(hub_bin)" list
    echo "# hub list output: $output" >&3
    [[ "$output" == *"$WS_NAME"* ]]
}

# ---------------------------------------------------------------------------
@test "hub new creates a bar_labels entry for the workspace" {
    run "$(hub_bin)" new --path "$FIXTURE_REPO" --worktree "$WS_NAME" --no-apps
    [[ "$status" -eq 0 ]]

    WS_ID="$(ws_id_for_name "$WS_NAME")"
    [[ -n "$WS_ID" ]]

    local labels_file="$HOME/.config/hub/bar_labels"
    [[ -f "$labels_file" ]]
    grep -q "^$WS_ID:$WS_NAME:" "$labels_file"
}
