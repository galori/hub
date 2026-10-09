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

@test "hub actions command substitutions execute from the caller's current directory" {
    cat > "$ACTIONS_FILE" <<'JSON'
[
  {"slug":"subshell","description":"Check subshell cwd","command":"value=$(pwd); printf '%s\\n' \"$value\""}
]
JSON
    run "$HUB" actions run subshell
    [[ "$status" -eq 0 ]]
    [[ "$output" == "$REPO_DIR" ]]
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

@test "default web action preset runs the web script with hub and workspace" {
    export ACTIONS_DIR="$HOME/stub-actions"
    mkdir -p "$ACTIONS_DIR"
    cat > "$ACTIONS_DIR/web" <<SH
#!/usr/bin/env bash
printf '%s|%s' "\$1" "\$2" > "$HOME/web_args"
SH
    chmod +x "$ACTIONS_DIR/web"
    jq -n --argjson p "$(jq '.web' "$REPO_DIR/config/action_presets.json")" '[$p]' > "$ACTIONS_FILE"
    run "$HUB" actions run web --focused
    [[ "$status" -eq 0 ]]
    [[ "$(cat "$HOME/web_args")" == "$HUB|1" ]]
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

# --- shipped default actions ---

run_default_action() {
    local slug="$1"; shift
    (cd "$ACTION_REPO" && "$REPO_DIR/default-actions/$slug" "$@")
}

stub_open_recording() {
    cat > "$STUB_BIN/open" <<SH
#!/usr/bin/env bash
echo "\$*" > "$HOME/opened_url"
SH
    chmod +x "$STUB_BIN/open"
}

setup_action_repo() {
    rm -f "$STUB_BIN/git"
    ACTION_REPO="$HOME/actionrepo"
    git init -q "$ACTION_REPO"
    git -C "$ACTION_REPO" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
    git -C "$ACTION_REPO" checkout -q -b "${1:-main}"
}

@test "run substitutes {actions_dir} in action commands" {
    export ACTIONS_DIR="$HOME/my-actions"
    cat > "$ACTIONS_FILE" <<'JSON'
[{"slug":"dir","command":"printf '%s' '{actions_dir}'"}]
JSON
    run "$HUB" actions run dir
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"/my-actions"* ]]
}

@test "jira default action errors when HUB_JIRA_HOST is unset" {
    setup_action_repo "ABC-123-thing"
    stub_open_recording
    run env -u HUB_JIRA_HOST bash -c "cd '$ACTION_REPO' && '$REPO_DIR/default-actions/jira'"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"HUB_JIRA_HOST"* ]]
    [[ ! -f "$HOME/opened_url" ]]
}

@test "jira default action opens the ticket on HUB_JIRA_HOST" {
    setup_action_repo "ABC-123-thing"
    stub_open_recording
    export HUB_JIRA_HOST="example.atlassian.net"
    run run_default_action jira
    [[ "$status" -eq 0 ]]
    [[ "$(cat "$HOME/opened_url")" == "https://example.atlassian.net/browse/ABC-123" ]]
}

@test "jira default action fails when the branch has no ticket prefix" {
    setup_action_repo "no-ticket"
    stub_open_recording
    export HUB_JIRA_HOST="example.atlassian.net"
    run run_default_action jira
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"No Jira ticket prefix"* ]]
}

@test "web default action errors when HUB_WEB_URL_CMD is unset" {
    stub_open_recording
    run env -u HUB_WEB_URL_CMD "$REPO_DIR/default-actions/web"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"HUB_WEB_URL_CMD"* ]]
    [[ ! -f "$HOME/opened_url" ]]
}

@test "web default action opens the URL printed by HUB_WEB_URL_CMD via hub" {
    stub_open_recording
    cat > "$HOME/fake-hub" <<SH
#!/usr/bin/env bash
echo "\$*" > "$HOME/hub_args"
SH
    chmod +x "$HOME/fake-hub"
    export HUB_WEB_URL_CMD="echo https://app.test:1234"
    run "$REPO_DIR/default-actions/web" "$HOME/fake-hub" 7
    [[ "$status" -eq 0 ]]
    [[ "$(cat "$HOME/hub_args")" == "open-url https://app.test:1234 7" ]]
}

@test "web default action falls back to open without a hub script" {
    stub_open_recording
    export HUB_WEB_URL_CMD="echo https://app.test:1234"
    run "$REPO_DIR/default-actions/web"
    [[ "$status" -eq 0 ]]
    [[ "$(cat "$HOME/opened_url")" == "https://app.test:1234" ]]
}

@test "pr default action fails when gh finds no pull request" {
    stub_open_recording
    make_stub gh "" 1
    run "$REPO_DIR/default-actions/pr"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"No pull request"* ]]
}

@test "pr default action opens the pull request URL" {
    stub_open_recording
    make_stub gh "https://github.com/o/r/pull/1" 0
    run "$REPO_DIR/default-actions/pr"
    [[ "$status" -eq 0 ]]
    [[ "$(cat "$HOME/opened_url")" == "https://github.com/o/r/pull/1" ]]
    [[ "$output" == *"Opening the PR at https://github.com/o/r/pull/1"* ]]
}

@test "web default action fails when HUB_WEB_URL_CMD prints no URL" {
    stub_open_recording
    export HUB_WEB_URL_CMD="true"
    run "$REPO_DIR/default-actions/web"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"produced no URL"* ]]
    [[ ! -f "$HOME/opened_url" ]]
}

@test "web default action falls back to open when the hub script fails" {
    stub_open_recording
    printf '#!/usr/bin/env bash\nexit 1\n' > "$HOME/fake-hub"
    chmod +x "$HOME/fake-hub"
    export HUB_WEB_URL_CMD="echo https://app.test:1234"
    run "$REPO_DIR/default-actions/web" "$HOME/fake-hub" 7
    [[ "$status" -eq 0 ]]
    [[ "$(cat "$HOME/opened_url")" == "https://app.test:1234" ]]
}

repo_action_url() {
    local dir="$1"
    local command
    command="$(jq -r '.repo.command' "$REPO_DIR/config/action_presets.json")"
    cat > "$STUB_BIN/open" <<SH
#!/usr/bin/env bash
echo "\$*" > "$HOME/opened_url"
SH
    chmod +x "$STUB_BIN/open"
    (cd "$dir" && bash -c "$command")
}

@test "repo action opens the remote repo from a root checkout (ssh remote)" {
    rm -f "$STUB_BIN/git"
    git init -q "$HOME/rootrepo"
    git -C "$HOME/rootrepo" remote add origin git@github.com:galori/hub.git
    run repo_action_url "$HOME/rootrepo"
    [[ "$status" -eq 0 ]]
    [[ "$(cat "$HOME/opened_url")" == "https://github.com/galori/hub" ]]
}

@test "repo action opens the remote repo from a linked worktree (https remote)" {
    rm -f "$STUB_BIN/git"
    git init -q "$HOME/rootrepo"
    git -C "$HOME/rootrepo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
    git -C "$HOME/rootrepo" remote add origin https://github.com/galori/hub.git
    git -C "$HOME/rootrepo" worktree add -q "$HOME/rootrepo-wt" -b feature
    run repo_action_url "$HOME/rootrepo-wt"
    [[ "$status" -eq 0 ]]
    [[ "$(cat "$HOME/opened_url")" == "https://github.com/galori/hub" ]]
}

@test "repo action fails outside a git repository" {
    rm -f "$STUB_BIN/git"
    mkdir -p "$HOME/plain"
    run repo_action_url "$HOME/plain"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"No git remote 'origin' found"* ]]
    [[ ! -f "$HOME/opened_url" ]]
}

assert_repo_action_url() {
    local remote="$1" expected="$2"
    rm -f "$STUB_BIN/git"
    git init -q "$HOME/rootrepo"
    git -C "$HOME/rootrepo" remote add origin "$remote"
    run repo_action_url "$HOME/rootrepo"
    [[ "$status" -eq 0 ]]
    [[ "$(cat "$HOME/opened_url")" == "$expected" ]]
    [[ "$output" != *"tok"* ]]
}

@test "repo action strips credentials from https remotes" {
    assert_repo_action_url "https://user:tok@github.com/galori/hub.git" "https://github.com/galori/hub"
}

@test "repo action handles ssh:// remotes with and without a port" {
    assert_repo_action_url "ssh://git@github.com/galori/hub.git" "https://github.com/galori/hub"
    rm -rf "$HOME/rootrepo"
    assert_repo_action_url "ssh://git@git.example.com:2222/galori/hub.git" "https://git.example.com/galori/hub"
}
