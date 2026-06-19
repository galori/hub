#!/usr/bin/env bats
# Unit tests for workspace JSON operations (cmd_list, get_workspace_path,
# ensure_general_workspace, update_bar_label, remove_bar_label)

load helpers/stubs

REPO_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
HUB_SCRIPT="$REPO_DIR/scripts/hub"

setup() {
    setup_stubs

    # Override path vars to use isolated dirs
    export WORKSPACES_FILE="$HOME/.config/hub/workspaces.json"
    export RECENT_REPOS_FILE="$HOME/.config/hub/recent_repos.json"
    export APPS_FILE="$HOME/.config/hub/apps.json"

    # Seed a realistic workspaces.json
    cat > "$WORKSPACES_FILE" <<'JSON'
[
  {"name":"Alpha","path":"/tmp/alpha","root_repo":"/tmp/alpha","workspace_id":"1","color":"ff0000"},
  {"name":"Beta","path":"/tmp/beta","root_repo":"/tmp/beta","workspace_id":"2"},
  {"name":"Gamma","path":"/tmp/gamma/worktree","root_repo":"/tmp/gamma","workspace_id":"A"}
]
JSON
}

teardown() {
    teardown_stubs
}

# ---------------------------------------------------------------------------
# get_workspace_path
# ---------------------------------------------------------------------------

@test "get_workspace_path returns path for known ID" {
    result="$(WORKSPACES_FILE="$WORKSPACES_FILE" \
        bash -c "source '$HUB_SCRIPT' >/dev/null 2>&1; get_workspace_path 1")"
    [[ "$result" == "/tmp/alpha" ]]
}

@test "get_workspace_path returns path for letter ID" {
    result="$(WORKSPACES_FILE="$WORKSPACES_FILE" \
        bash -c "source '$HUB_SCRIPT' >/dev/null 2>&1; get_workspace_path A")"
    [[ "$result" == "/tmp/gamma/worktree" ]]
}

@test "get_workspace_path returns empty for unknown ID" {
    result="$(WORKSPACES_FILE="$WORKSPACES_FILE" \
        bash -c "source '$HUB_SCRIPT' >/dev/null 2>&1; get_workspace_path Z")"
    [[ -z "$result" ]]
}

@test "get_workspace_path returns empty when workspaces.json missing" {
    empty_home="$(mktemp -d)"
    result="$(HOME="$empty_home" bash -c "source '$HUB_SCRIPT' >/dev/null 2>&1; get_workspace_path 1")"
    rm -rf "$empty_home"
    [[ -z "$result" ]]
}

# ---------------------------------------------------------------------------
# cmd_list (non-verbose)
# ---------------------------------------------------------------------------

@test "cmd_list prints all workspace IDs and names" {
    output="$(WORKSPACES_FILE="$WORKSPACES_FILE" \
        bash -c "source '$HUB_SCRIPT' >/dev/null 2>&1; cmd_list")"
    [[ "$output" == *"1"*"Alpha"* ]]
    [[ "$output" == *"2"*"Beta"* ]]
    [[ "$output" == *"A"*"Gamma"* ]]
}

@test "cmd_list prints header row" {
    output="$(WORKSPACES_FILE="$WORKSPACES_FILE" \
        bash -c "source '$HUB_SCRIPT' >/dev/null 2>&1; cmd_list")"
    [[ "$output" == *"ID"* ]]
    [[ "$output" == *"NAME"* ]]
}

@test "cmd_list when no workspaces.json prints message" {
    empty_home="$(mktemp -d)"
    output="$(HOME="$empty_home" bash -c "source '$HUB_SCRIPT' >/dev/null 2>&1; cmd_list")"
    rm -rf "$empty_home"
    [[ "$output" == *"No workspaces"* ]]
}

@test "cmd_list -v includes PATH and ROOT REPO headers" {
    output="$(WORKSPACES_FILE="$WORKSPACES_FILE" \
        bash -c "source '$HUB_SCRIPT' >/dev/null 2>&1; cmd_list -v")"
    [[ "$output" == *"PATH"* ]]
    [[ "$output" == *"ROOT REPO"* ]]
    [[ "$output" == *"/tmp/alpha"* ]]
}

@test "cmd_list -v shows root_repo field" {
    output="$(WORKSPACES_FILE="$WORKSPACES_FILE" \
        bash -c "source '$HUB_SCRIPT' >/dev/null 2>&1; cmd_list -v")"
    [[ "$output" == *"/tmp/gamma"* ]]
}

@test "cmd_list shows empty message when JSON is empty array" {
    echo "[]" > "$WORKSPACES_FILE"
    output="$(WORKSPACES_FILE="$WORKSPACES_FILE" \
        bash -c "source '$HUB_SCRIPT' >/dev/null 2>&1; cmd_list")"
    [[ "$output" == *"No workspaces"* ]]
}

# ---------------------------------------------------------------------------
# ensure_general_workspace
# ---------------------------------------------------------------------------

@test "ensure_general_workspace creates Z entry when absent" {
    WORKSPACES_FILE="$WORKSPACES_FILE" \
        bash -c "source '$HUB_SCRIPT' >/dev/null 2>&1; ensure_general_workspace" >/dev/null 2>&1
    count="$(jq '[.[] | select(.workspace_id == "Z")] | length' "$WORKSPACES_FILE")"
    [[ "$count" == "1" ]]
}

@test "ensure_general_workspace does not duplicate Z entry" {
    # Run twice
    for _ in 1 2; do
        WORKSPACES_FILE="$WORKSPACES_FILE" \
            bash -c "source '$HUB_SCRIPT' >/dev/null 2>&1; ensure_general_workspace" >/dev/null 2>&1
    done
    count="$(jq '[.[] | select(.workspace_id == "Z")] | length' "$WORKSPACES_FILE")"
    [[ "$count" == "1" ]]
}

@test "ensure_general_workspace sets name to General" {
    WORKSPACES_FILE="$WORKSPACES_FILE" \
        bash -c "source '$HUB_SCRIPT' >/dev/null 2>&1; ensure_general_workspace" >/dev/null 2>&1
    name="$(jq -r '.[] | select(.workspace_id == "Z") | .name' "$WORKSPACES_FILE")"
    [[ "$name" == "General" ]]
}

@test "ensure_general_workspace works on empty workspaces.json" {
    echo "[]" > "$WORKSPACES_FILE"
    WORKSPACES_FILE="$WORKSPACES_FILE" \
        bash -c "source '$HUB_SCRIPT' >/dev/null 2>&1; ensure_general_workspace" >/dev/null 2>&1
    count="$(jq 'length' "$WORKSPACES_FILE")"
    [[ "$count" == "1" ]]
}

@test "ensure_general_workspace creates workspaces.json if missing" {
    rm -f "$WORKSPACES_FILE"
    WORKSPACES_FILE="$WORKSPACES_FILE" \
        bash -c "source '$HUB_SCRIPT' >/dev/null 2>&1; ensure_general_workspace" >/dev/null 2>&1
    [[ -f "$WORKSPACES_FILE" ]]
    count="$(jq 'length' "$WORKSPACES_FILE")"
    [[ "$count" == "1" ]]
}

# ---------------------------------------------------------------------------
# recent_repos update logic (extracted from cmd_new internals)
# ---------------------------------------------------------------------------

@test "recent_repos deduplicates and keeps newest first" {
    echo '["old"]' > "$RECENT_REPOS_FILE"
    # Simulate the update logic from cmd_new
    bash -c "
        existing=\$(cat '$RECENT_REPOS_FILE')
        echo \"\$existing\" | jq --arg r 'old' '[\$r] + (map(select(. != \$r))) | .[0:20]' > '$RECENT_REPOS_FILE'
    "
    result="$(jq 'length' "$RECENT_REPOS_FILE")"
    [[ "$result" == "1" ]]
    first="$(jq -r '.[0]' "$RECENT_REPOS_FILE")"
    [[ "$first" == "old" ]]
}

@test "recent_repos caps at 20 entries" {
    # Create 21 entries
    entries="$(python3 -c "import json; print(json.dumps([str(i) for i in range(21)]))")"
    echo "$entries" > "$RECENT_REPOS_FILE"
    bash -c "
        existing=\$(cat '$RECENT_REPOS_FILE')
        echo \"\$existing\" | jq --arg r 'new' '[\$r] + (map(select(. != \$r))) | .[0:20]' > '$RECENT_REPOS_FILE'
    "
    result="$(jq 'length' "$RECENT_REPOS_FILE")"
    [[ "$result" == "20" ]]
}
