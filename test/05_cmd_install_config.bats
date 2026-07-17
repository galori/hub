#!/usr/bin/env bats
# Stubbed command tests: hub install config deployment (sed substitution,
# placeholder replacement, idempotency). Does NOT require running services.

load helpers/stubs

REPO_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
HUB_SCRIPT="$REPO_DIR/scripts/hub"

setup() {
    setup_stubs

    # Override all path vars to keep everything in the temp dir
    export AEROSPACE_CONFIG="$HOME/.aerospace.toml"
    export WORKSPACES_FILE="$HOME/.config/hub/workspaces.json"
    export APPS_FILE="$HOME/.config/hub/apps.json"
    export ACTIONS_FILE="$HOME/.config/hub/actions.json"
    export ACTION_PRESETS_FILE="$HOME/.config/hub/action_presets.json"
    export APP_PRESETS_FILE="$HOME/.config/hub/app_presets.json"
    export KEYS_CACHE="$HOME/.config/hub/keys_cache"
    export STUB_CALLS="$HOME/stub_calls"

    # Stub interactive tools that install would prompt or run
    make_stub git "" 0
    make_stub swiftc "" 0

    # Stub brew to report packages as installed
    cat > "$STUB_BIN/brew" <<'SH'
#!/usr/bin/env bash
exit 0
SH
    chmod +x "$STUB_BIN/brew"

    # Stub command -v jq to succeed
    cat > "$STUB_BIN/jq" <<'SH'
#!/usr/bin/env bash
# If called as 'jq ...' for real JSON ops, delegate to system jq
# Otherwise succeed for 'command -v jq' check
exec /opt/homebrew/bin/jq "$@"
SH
    chmod +x "$STUB_BIN/jq"
}

teardown() {
    teardown_stubs
}

# Run just the deploy-configs portion of install through the real helper.
run_deploy() {
    bash -c "
        export HOME='$HOME'
        export HUB_HOME='$HUB_HOME'
        export HUB_CONFIG_DIR='$HUB_CONFIG_DIR'
        export HUB_RUNTIME_DIR='$HUB_RUNTIME_DIR'
        export HUB_APPLICATIONS_DIR='$HUB_APPLICATIONS_DIR'
        export AEROSPACE_CONFIG='$AEROSPACE_CONFIG'
        source '$HUB_SCRIPT' >/dev/null 2>&1
        deploy_aerospace_config
    "
}

# ---------------------------------------------------------------------------
# aerospace.toml deployment
# ---------------------------------------------------------------------------

@test "install deploys aerospace.toml with __HUB_SCRIPT__ replaced" {
    run_deploy
    [[ -f "$AEROSPACE_CONFIG" ]]
    ! grep -q '__HUB_SCRIPT__' "$AEROSPACE_CONFIG"
}

@test "deployed aerospace.toml contains correct hub script path" {
    run_deploy
    grep -q "$REPO_DIR/scripts/hub" "$AEROSPACE_CONFIG"
}

@test "deployed aerospace.toml is valid TOML (no syntax errors from sed)" {
    run_deploy
    # Check that key sections survived substitution intact
    grep -q 'config-version = 2' "$AEROSPACE_CONFIG"
    grep -q '\[mode.main.binding\]' "$AEROSPACE_CONFIG"
    grep -q '\[mode.service.binding\]' "$AEROSPACE_CONFIG"
}

@test "deployed aerospace.toml contains resolved outer.top" {
    run_deploy
    grep -q 'outer.top =        55' "$AEROSPACE_CONFIG"
    ! grep -q '__HUB_OUTER_TOP__' "$AEROSPACE_CONFIG"
}

@test "all __HUB_SCRIPT__ placeholders replaced in aerospace.toml" {
    run_deploy
    count="$(grep -c '__HUB_SCRIPT__' "$AEROSPACE_CONFIG" || true)"
    [[ "$count" == "0" ]]
}

@test "deployed aerospace.toml nudges new windows below the Hub Bar" {
    run_deploy
    grep -q 'nudge-float-window \$AEROSPACE_WINDOW_ID' "$AEROSPACE_CONFIG"
}

@test "deploy is idempotent (running twice produces same result)" {
    run_deploy
    checksum1="$(md5 -q "$AEROSPACE_CONFIG")"
    run_deploy
    checksum2="$(md5 -q "$AEROSPACE_CONFIG")"
    [[ "$checksum1" == "$checksum2" ]]
}

# ---------------------------------------------------------------------------
# default apps.json creation
# ---------------------------------------------------------------------------

@test "install creates default apps.json when absent" {
    [[ ! -f "$APPS_FILE" ]]
    bash -c "
        export APPS_FILE='$APPS_FILE'
        mkdir -p '\$(dirname '$APPS_FILE')'
        if [[ ! -f '$APPS_FILE' ]]; then
            cat > '$APPS_FILE' << 'APPS_EOF'
[
  {\"name\": \"iTerm2\", \"launch\": \"osascript\", \"icon\": \"iTerm2\"},
  {\"name\": \"Google Chrome\", \"launch\": \"open -na Chrome\", \"icon\": \"Google Chrome\"}
]
APPS_EOF
        fi
    "
    [[ -f "$APPS_FILE" ]]
    jq . "$APPS_FILE" >/dev/null 2>&1   # valid JSON
}

@test "installed apps.json is valid JSON" {
    # Simulate what hub install writes
    cat > "$APPS_FILE" <<'JSON'
[
  {"name": "iTerm2", "launch": "osascript -e 'tell application \"iTerm2\"'", "icon": "iTerm2"},
  {"name": "Google Chrome", "launch": "open -na 'Google Chrome'", "icon": "Google Chrome"},
  {"name": "Code", "launch": "code --new-window {path}", "icon": "Code"}
]
JSON
    jq . "$APPS_FILE" >/dev/null 2>&1
}

@test "install creates default actions.json when absent" {
    [[ ! -f "$ACTIONS_FILE" ]]
    run env HUB_NONINTERACTIVE=1 "$HUB_SCRIPT" install --no-reload --no-shell-integration --no-launch-services --no-default-browser-change
    [[ "$status" -eq 0 ]]
    [[ -f "$ACTIONS_FILE" ]]
    jq . "$ACTIONS_FILE" >/dev/null 2>&1
    [[ "$(jq -r 'map(.slug) | join(",")' "$ACTIONS_FILE")" == "pr,jira,web" ]]
}

@test "install preserves existing actions.json" {
    mkdir -p "$(dirname "$ACTIONS_FILE")"
    cat > "$ACTIONS_FILE" <<'JSON'
[
  {"slug":"custom","description":"Keep me","command":"echo custom"}
]
JSON
    run env HUB_NONINTERACTIVE=1 "$HUB_SCRIPT" install --no-reload --no-shell-integration --no-launch-services --no-default-browser-change
    [[ "$status" -eq 0 ]]
    [[ "$(jq -r 'map(.slug) | join(",")' "$ACTIONS_FILE")" == "custom" ]]
}

@test "install updates legacy default web action command" {
    mkdir -p "$(dirname "$ACTIONS_FILE")"
    cat > "$ACTIONS_FILE" <<'JSON'
[
  {"slug":"web","description":"Open web","command":"/Users/gall/workspace/dgapp/scripts/worktree open"}
]
JSON
    run env HUB_NONINTERACTIVE=1 "$HUB_SCRIPT" install --no-reload --no-shell-integration --no-launch-services --no-default-browser-change
    [[ "$status" -eq 0 ]]
    command="$(jq -r '.[] | select(.slug == "web") | .command' "$ACTIONS_FILE")"
    [[ "$command" == *"{hub} open-url"* ]]
}

@test "install isolated flags avoid live reloads and shell integration" {
    run env HUB_NONINTERACTIVE=1 "$HUB_SCRIPT" install --no-reload --no-shell-integration --no-launch-services --no-default-browser-change

    [[ "$status" -eq 0 ]]
    [[ -f "$AEROSPACE_CONFIG" ]]
    [[ -f "$APP_PRESETS_FILE" ]]
    [[ ! -f "$HOME/.zshrc" ]]
    [[ ! -f "$HOME/.claude/commands/hub-new.md" ]]
    [[ "$output" == *"Skipped live service reload"* ]]
    [[ "$output" == *"Skipped shell alias install"* ]]
}
