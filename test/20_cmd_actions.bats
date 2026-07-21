#!/usr/bin/env bats
# Stubbed command tests for custom action management and dispatch.

load helpers/stubs

REPO_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
HUB="$REPO_DIR/scripts/hub"

setup() {
    setup_stubs

    export WORKSPACES_FILE="$HOME/.config/hub/workspaces.json"
    export ACTIONS_FILE="$HOME/.config/hub/actions.json"
    export ACTION_PRESETS_FILE="$HOME/.config/hub/action_presets.json"
    export HUB_LOG_FILE="$HOME/.config/hub/hub.log"
    export STUB_CALLS="$HOME/stub_calls"

    cat > "$WORKSPACES_FILE" <<'JSON'
[{"name":"Main","path":"/tmp/main","root_repo":"/tmp/main","workspace_id":"1"}]
JSON

    mkdir -p /tmp/main

    cat > "$ACTION_PRESETS_FILE" <<'JSON'
{
  "hello": {"slug":"hello","description":"Test preset","command":"printf 'hello from %s\\n' \"$PWD\""}
}
JSON

    cat > "$ACTIONS_FILE" <<'JSON'
[
  {"slug":"hello","description":"Test action","command":"printf 'hello from %s\\n' \"$PWD\""}
]
JSON

    cat > "$STUB_BIN/aerospace" <<'SH'
#!/usr/bin/env bash
case "$*" in
    "list-workspaces --focused") echo "1" ;;
    *) exit 0 ;;
esac
SH
    chmod +x "$STUB_BIN/aerospace"
}

teardown() {
    teardown_stubs
}

@test "hub actions list shows configured actions" {
    run "$HUB" actions list
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"hello"* ]]
    [[ "$output" == *"Test action"* ]]
}

@test "hub actions presets shows available presets" {
    run "$HUB" actions presets
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"hello"* ]]
    [[ "$output" == *"Test preset"* ]]
}

@test "hub actions add preset writes action JSON" {
    echo "[]" > "$ACTIONS_FILE"
    run "$HUB" actions add hello -y
    [[ "$status" -eq 0 ]]
    [[ "$(jq -r '.[0].slug' "$ACTIONS_FILE")" == "hello" ]]
    [[ "$(jq -r '.[0].command' "$ACTIONS_FILE")" == *"hello from"* ]]
}

@test "hub actions add custom command writes action JSON" {
    echo "[]" > "$ACTIONS_FILE"
    run "$HUB" actions add custom --command "echo custom" --description "Custom action"
    [[ "$status" -eq 0 ]]
    [[ "$(jq -r '.[0].slug' "$ACTIONS_FILE")" == "custom" ]]
    [[ "$(jq -r '.[0].command' "$ACTIONS_FILE")" == "echo custom" ]]
    [[ "$(jq -r '.[0].description' "$ACTIONS_FILE")" == "Custom action" ]]
}

@test "hub actions add custom command logs saved action" {
    echo "[]" > "$ACTIONS_FILE"
    run "$HUB" actions add custom --command "echo custom" --description "Custom action"
    [[ "$status" -eq 0 ]]
    grep -q "save action custom" "$HUB_LOG_FILE"
    grep -q "action custom command: echo custom" "$HUB_LOG_FILE"
}

@test "hub actions remove deletes matching slug" {
    run "$HUB" actions remove hello -y
    [[ "$status" -eq 0 ]]
    [[ "$(jq 'length' "$ACTIONS_FILE")" == "0" ]]
}

@test "hub actions remove logs removed action" {
    run "$HUB" actions remove hello -y
    [[ "$status" -eq 0 ]]
    grep -q "remove action hello" "$HUB_LOG_FILE"
}

@test "hub actions reset --defaults restores shipped actions" {
    cat > "$ACTION_PRESETS_FILE" <<'JSON'
{
  "pr": {"slug":"pr","description":"Open PR","command":"echo pr"},
  "jira": {"slug":"jira","description":"Open Jira","command":"echo jira"},
  "web": {"slug":"web","description":"Open web","command":"echo web"}
}
JSON
    echo "[]" > "$ACTIONS_FILE"
    run "$HUB" actions reset --defaults -y
    [[ "$status" -eq 0 ]]
    [[ "$(jq -r 'map(.slug) | join(",")' "$ACTIONS_FILE")" == "pr,jira,web" ]]
}

@test "hub actions reset logs default restore" {
    echo "[]" > "$ACTIONS_FILE"
    run "$HUB" actions reset --defaults -y
    [[ "$status" -eq 0 ]]
    grep -q "restore default actions" "$HUB_LOG_FILE"
}

@test "hub actions run executes from the caller's current directory" {
    run "$HUB" actions run hello
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"hello from $REPO_DIR"* ]]
}

@test "hub actions run --focused executes from focused workspace path" {
    run "$HUB" actions run hello --focused
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"hello from /tmp/main"* ]]
}

@test "hub actions run substitutes hub script placeholder" {
    cat > "$ACTIONS_FILE" <<'JSON'
[
  {"slug":"showhub","description":"Show hub path","command":"echo {hub}"}
]
JSON
    run "$HUB" actions run showhub
    [[ "$status" -eq 0 ]]
    [[ "$output" == "$HUB" ]]
}

@test "hub actions run logs command attempt and success" {
    run "$HUB" actions run hello
    [[ "$status" -eq 0 ]]
    grep -q "run action hello on workspace 1 path $REPO_DIR" "$HUB_LOG_FILE"
    grep -q "action hello: printf 'hello from %s" "$HUB_LOG_FILE"
    grep -q "action hello completed with exit 0" "$HUB_LOG_FILE"
}

@test "hub actions run logs command failure" {
    cat > "$ACTIONS_FILE" <<'JSON'
[
  {"slug":"fail","description":"Fail action","command":"echo before-fail; exit 7"}
]
JSON
    run "$HUB" actions run fail
    [[ "$status" -eq 7 ]]
    [[ "$output" == *"before-fail"* ]]
    grep -q "run action fail on workspace 1 path $REPO_DIR" "$HUB_LOG_FILE"
    grep -q "action fail: echo before-fail; exit 7" "$HUB_LOG_FILE"
    grep -q "action fail failed with exit 7" "$HUB_LOG_FILE"
}

@test "hub actions run loads exported shell environment while preserving bash execution" {
    cat > "$HOME/.zshrc" <<'SH'
export HUB_ACTION_TEST_ENV=from-zshrc
SH
    cat > "$ACTIONS_FILE" <<'JSON'
[
  {"slug":"envcheck","description":"Check action env","command":"printf '%s:%s\\n' \"$HUB_ACTION_TEST_ENV\" \"${BASH_VERSION:+bash}\""}
]
JSON
    run "$HUB" actions run envcheck
    [[ "$status" -eq 0 ]]
    [[ "$output" == "from-zshrc:bash" ]]
}

@test "hub actions slug executes matching action directly" {
    run "$HUB" actions hello
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"hello from $REPO_DIR"* ]]
}

@test "default web action routes resolved worktree URL through hub open-url" {
    command="$(jq -r '.web.command' "$REPO_DIR/config/action_presets.json")"
    [[ "$command" == *"worktree url"* ]]
    [[ "$command" == *"{hub} open-url"* ]]
    [[ "$command" == *"{workspace}"* ]]
}

@test "hub actions help documents hub placeholder" {
    run "$HUB" actions help
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"{hub} = Hub CLI script"* ]]
}

@test "Hub Bar actions request the focused workspace" {
    grep -Fq "actions run '\(slug)' --focused" "$REPO_DIR/lib/hub_bar.swift"
}

@test "hub actions run missing slug fails cleanly" {
    run "$HUB" actions run missing
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"No action configured for slug: missing"* ]]
}

@test "hub actions add rejects invalid slugs" {
    run "$HUB" actions add "bad slug" --command "echo bad"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"Invalid action slug"* ]]
}
