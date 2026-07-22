#!/usr/bin/env bats
# Tests for the workspace write path exercised by cmd_new.
# Since cmd_new always launches a GUI dialog, we test the downstream
# workspace-saving logic directly by calling the internal write helpers.

load helpers/stubs
load helpers/fixtures

REPO_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
HUB_SCRIPT="$REPO_DIR/scripts/hub"

setup() {
    setup_stubs
    export WORKSPACES_FILE="$HOME/.config/hub/workspaces.json"
    export RECENT_REPOS_FILE="$HOME/.config/hub/recent_repos.json"
    export STUB_CALLS="$HOME/stub_calls"
    mkdir -p "$HOME/.config/hub"
}

teardown() {
    teardown_stubs
}

run_new_cli_capture() {
    bash -c '
        export HOME="$1" WORKSPACES_FILE="$2" APPS_FILE="$3"
        source "$4" >/dev/null 2>&1
        _create_workspace() { printf "%s\n" "$7"; }
        _cmd_new_cli "${@:5}"
    ' _ "$HOME" "$WORKSPACES_FILE" "$APPS_FILE" "$HUB_SCRIPT" "$@"
}

@test "hub new CLI opens no apps by default" {
    printf '[{"name":"Terminal"},{"name":"Browser"}]\n' > "$APPS_FILE"
    run run_new_cli_capture --no-repo --name scratch
    [[ "$status" -eq 0 ]]
    [[ "$output" == "" ]]
}

@test "hub new CLI accepts --apps none as no apps" {
    printf '[{"name":"Terminal"},{"name":"Browser"}]\n' > "$APPS_FILE"
    run run_new_cli_capture --no-repo --name scratch --apps none
    [[ "$status" -eq 0 ]]
    [[ "$output" == "" ]]
}

@test "hub new CLI preserves explicitly selected app slots" {
    printf '[{"name":"Terminal"},{"name":"Browser"}]\n' > "$APPS_FILE"
    run run_new_cli_capture --no-repo --name scratch --apps 1,2
    [[ "$status" -eq 0 ]]
    [[ "$output" == "1,2" ]]
}

@test "hub new CLI rejects an invalid app selector before creating workspace" {
    printf '[{"name":"Terminal"},{"name":"Browser"}]\n' > "$APPS_FILE"
    run run_new_cli_capture --no-repo --name scratch --apps unknown
    [[ "$status" -eq 2 ]]
    [[ "$output" == *"Invalid app selector: unknown"* ]]
}

# Write a workspace entry directly via the same jq path cmd_new uses.
write_workspace() {
    local name="$1" path="$2" root="$3" id="$4"
    local existing="[]"
    [[ -f "$WORKSPACES_FILE" ]] && existing="$(cat "$WORKSPACES_FILE")"
    echo "$existing" | jq --arg name "$name" --arg path "$path" \
        --arg root "$root" --arg id "$id" \
        '. + [{name: $name, path: $path, root_repo: $root, workspace_id: $id}]' \
        > "$WORKSPACES_FILE"
}

# ---------------------------------------------------------------------------
# rebuild_labels_file — called after every workspace write
# ---------------------------------------------------------------------------

@test "rebuild_labels_file writes id:name entries for all workspaces" {
    seed_workspaces "1:Alpha:/tmp/a" "2:Beta:/tmp/b"
    bash -c "
        export HOME='$HOME'
        export WORKSPACES_FILE='$WORKSPACES_FILE'
        source '$HUB_SCRIPT' >/dev/null 2>&1
        rebuild_labels_file
    " 2>/dev/null
    [[ -f "$HOME/.config/hub/hub_bar_labels" ]]
    grep -q "^1:Alpha:" "$HOME/.config/hub/hub_bar_labels"
    grep -q "^2:Beta:"  "$HOME/.config/hub/hub_bar_labels"
}

@test "rebuild_labels_file includes repo basename when root_repo set" {
    seed_workspaces "3:feature:/tmp/repo/feature:/tmp/repo"
    bash -c "
        export HOME='$HOME'
        export WORKSPACES_FILE='$WORKSPACES_FILE'
        source '$HUB_SCRIPT' >/dev/null 2>&1
        rebuild_labels_file
    " 2>/dev/null
    grep -q "^3:feature::repo" "$HOME/.config/hub/hub_bar_labels"
}

# ---------------------------------------------------------------------------
# Workspace JSON write path (mirrors cmd_new's jq invocation)
# ---------------------------------------------------------------------------

@test "workspace write adds entry to workspaces.json" {
    echo '[]' > "$WORKSPACES_FILE"
    write_workspace "NewWS" "/tmp/new" "/tmp/new" "A"
    count="$(jq 'length' "$WORKSPACES_FILE")"
    [[ "$count" -eq 1 ]]
}

@test "workspace write preserves existing entries" {
    seed_workspaces "1:Existing:/tmp/existing"
    write_workspace "NewWS" "/tmp/new" "/tmp/new" "2"
    count="$(jq 'length' "$WORKSPACES_FILE")"
    [[ "$count" -eq 2 ]]
    name="$(jq -r '.[0].name' "$WORKSPACES_FILE")"
    [[ "$name" == "Existing" ]]
}

@test "workspace write stores all required fields" {
    echo '[]' > "$WORKSPACES_FILE"
    write_workspace "MyWS" "/tmp/proj" "/tmp/proj" "5"
    ws="$(jq '.[0]' "$WORKSPACES_FILE")"
    [[ "$(echo "$ws" | jq -r '.name')"         == "MyWS"     ]]
    [[ "$(echo "$ws" | jq -r '.path')"         == "/tmp/proj" ]]
    [[ "$(echo "$ws" | jq -r '.root_repo')"    == "/tmp/proj" ]]
    [[ "$(echo "$ws" | jq -r '.workspace_id')" == "5"         ]]
}

# ---------------------------------------------------------------------------
# ensure_general_workspace — called during hub up / install
# ---------------------------------------------------------------------------

run_ensure_general_workspace() {
    local runner="$HOME/runner_egw.sh"
    {
        echo "#!/usr/bin/env bash"
        echo "export HOME='$HOME'"
        echo "export WORKSPACES_FILE='$WORKSPACES_FILE'"
        echo "export PATH='$STUB_BIN':\"\$PATH\""
        echo "source '$HUB_SCRIPT' >/dev/null 2>&1"
        echo "ensure_general_workspace"
    } > "$runner"
    chmod +x "$runner"
    bash "$runner" 2>/dev/null
}

@test "ensure_general_workspace creates Z entry when missing" {
    echo '[]' > "$WORKSPACES_FILE"
    run_ensure_general_workspace
    count="$(jq '[.[] | select(.workspace_id == "Z")] | length' "$WORKSPACES_FILE")"
    [[ "$count" -eq 1 ]]
}

@test "ensure_general_workspace is idempotent" {
    echo '[]' > "$WORKSPACES_FILE"
    run_ensure_general_workspace
    run_ensure_general_workspace
    count="$(jq '[.[] | select(.workspace_id == "Z")] | length' "$WORKSPACES_FILE")"
    [[ "$count" -eq 1 ]]
}

@test "ensure_general_workspace does not overwrite existing Z entry" {
    seed_workspaces "Z:MyGeneral:/tmp/custom"
    run_ensure_general_workspace
    name="$(jq -r '.[] | select(.workspace_id == "Z") | .name' "$WORKSPACES_FILE")"
    [[ "$name" == "MyGeneral" ]]
}
