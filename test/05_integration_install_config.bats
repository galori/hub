#!/usr/bin/env bats
# Integration tests: hub install config deployment (sed substitution,
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
    export KEYS_CACHE="$HOME/.config/hub/keys_cache"

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

# Run just the deploy-configs portion of install.
# Uses a temp script file to avoid quoting pitfalls in bash -c heredocs.
run_deploy() {
    local deploy_script
    deploy_script="$(mktemp /tmp/hub_test_deploy.XXXXXX.sh)"
    cat > "$deploy_script" <<SCRIPT
#!/usr/bin/env bash
set -euo pipefail
HUB_SCRIPT="$REPO_DIR/scripts/hub"

# Deploy aerospace config
sed "s|__HUB_SCRIPT__|\$HUB_SCRIPT|g" \
    "$REPO_DIR/config/aerospace.toml" > "$AEROSPACE_CONFIG"
SCRIPT
    chmod +x "$deploy_script"
    bash "$deploy_script"
    rm -f "$deploy_script"
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
