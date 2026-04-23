#!/usr/bin/env bats
# Integration tests: invoke hub as a subprocess and assert CLI output

load helpers/stubs

REPO_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
HUB="$REPO_DIR/scripts/hub"

setup() {
    setup_stubs
    export WORKSPACES_FILE="$HOME/.config/hub/workspaces.json"
}

teardown() {
    teardown_stubs
}

write_workspaces() {
    cat > "$WORKSPACES_FILE" <<JSON
$1
JSON
}

@test "hub list shows all workspaces" {
    write_workspaces '[
      {"name":"Foo","path":"/tmp/foo","root_repo":"/tmp/foo","workspace_id":"1"},
      {"name":"Bar","path":"/tmp/bar","root_repo":"/tmp/bar","workspace_id":"B"}
    ]'
    run "$HUB" list
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Foo"* ]]
    [[ "$output" == *"Bar"* ]]
    [[ "$output" == *"1"* ]]
    [[ "$output" == *"B"* ]]
}

@test "hub list -v shows paths" {
    write_workspaces '[
      {"name":"Foo","path":"/tmp/foo","root_repo":"/tmp/root","workspace_id":"1"}
    ]'
    run "$HUB" list -v
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"/tmp/foo"* ]]
    [[ "$output" == *"/tmp/root"* ]]
}

@test "hub list with no workspaces.json exits 0 with message" {
    rm -f "$WORKSPACES_FILE"
    run "$HUB" list
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"No workspaces"* ]]
}

@test "hub list with empty workspaces exits 0 with message" {
    write_workspaces '[]'
    run "$HUB" list
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"No workspaces"* ]]
}

@test "hub list sorts by workspace_id" {
    write_workspaces '[
      {"name":"Last","path":"/tmp","root_repo":"/tmp","workspace_id":"Z"},
      {"name":"First","path":"/tmp","root_repo":"/tmp","workspace_id":"1"}
    ]'
    run "$HUB" list
    [[ "$status" -eq 0 ]]
    first_line="$(echo "$output" | grep -E '^\s*(1|Z)' | head -1)"
    [[ "$first_line" == *"1"* ]]
}

@test "hub with no command exits 0 and shows usage" {
    run "$HUB"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Usage"* ]]
}

@test "hub help exits 0 and shows usage" {
    run "$HUB" help
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Usage"* ]]
}

@test "hub unknown command exits non-zero" {
    run "$HUB" boguscommand
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"Unknown command"* ]]
}
