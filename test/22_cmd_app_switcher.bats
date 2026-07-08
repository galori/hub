#!/usr/bin/env bats
# Stubbed command tests for cmd_app_switcher gating and dispatch, including
# the custom-action tiles added alongside the launch-bar app tiles.

load helpers/stubs

REPO_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
HUB="$REPO_DIR/scripts/hub"

setup() {
    setup_stubs

    export WORKSPACES_FILE="$HOME/.config/hub/workspaces.json"
    export STUB_CALLS="$HOME/stub_calls"

    cat > "$WORKSPACES_FILE" <<'JSON'
[{"name":"Main","path":"/tmp/main","root_repo":"/tmp/main","workspace_id":"1"}]
JSON
    mkdir -p /tmp/main

    cat > "$STUB_BIN/aerospace" <<'SH'
#!/usr/bin/env bash
case "$*" in
    "list-workspaces --focused") echo "1" ;;
    *) exit 0 ;;
esac
SH
    chmod +x "$STUB_BIN/aerospace"

    # Fake compiled binary: the real one is a Cocoa modal we can't drive in
    # CI, so this stub stands in for "the user picked an item" by writing
    # whatever $FAKE_SWITCHER_RESULT holds straight to APP_SWITCHER_RESULT.
    cat > "$STUB_BIN/app_switcher" <<'SH'
#!/usr/bin/env bash
if [[ -n "${FAKE_SWITCHER_RESULT:-}" ]]; then
    printf '%s' "$FAKE_SWITCHER_RESULT" > "$APP_SWITCHER_RESULT"
fi
exit 0
SH
    chmod +x "$STUB_BIN/app_switcher"
    export APP_SWITCHER_BIN="$STUB_BIN/app_switcher"
}

teardown() {
    teardown_stubs
}

@test "cmd_app_switcher is a no-op with no apps and no actions configured" {
    echo "[]" > "$APPS_FILE"
    echo "[]" > "$ACTIONS_FILE"
    run "$HUB" app-switcher
    [[ "$status" -eq 0 ]]
}

@test "cmd_app_switcher runs the modal when only actions are configured" {
    rm -f "$APPS_FILE"
    cat > "$ACTIONS_FILE" <<'JSON'
[{"slug":"web","description":"Open web","command":"echo web-ran"}]
JSON
    export FAKE_SWITCHER_RESULT="action:web"
    run "$HUB" app-switcher
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"web-ran"* ]]
}

@test "cmd_app_switcher dispatches an app slot selection to cmd_open --force" {
    cat > "$APPS_FILE" <<'JSON'
[{"name":"iTerm2","launch":"echo launch-iterm","icon":"iTerm2"}]
JSON
    echo "[]" > "$ACTIONS_FILE"
    export HUB_LOG_FILE="$HOME/.config/hub/hub.log"
    # cmd_app_switcher always passes --force (like Cmd-F1..F5), so open_app_slot
    # skips the existing-window focus check and goes straight to launching —
    # match that here rather than asserting a focus branch that never runs.
    export FAKE_SWITCHER_RESULT="1"
    run "$HUB" app-switcher
    [[ "$status" -eq 0 ]]
    grep -q "launch iTerm2 on workspace 1" "$HUB_LOG_FILE"
}

@test "cmd_app_switcher dispatches an action selection via actions_run" {
    cat > "$APPS_FILE" <<'JSON'
[{"name":"iTerm2","launch":"echo launch-iterm","icon":"iTerm2"}]
JSON
    cat > "$ACTIONS_FILE" <<'JSON'
[{"slug":"pr","description":"Open PR","command":"echo pr-ran from $PWD"}]
JSON
    export FAKE_SWITCHER_RESULT="action:pr"
    run "$HUB" app-switcher
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"pr-ran from /tmp/main"* ]]
}

@test "cmd_app_switcher does nothing when the modal is cancelled" {
    cat > "$APPS_FILE" <<'JSON'
[{"name":"iTerm2","launch":"echo launch-iterm","icon":"iTerm2"}]
JSON
    echo "[]" > "$ACTIONS_FILE"
    unset FAKE_SWITCHER_RESULT
    run "$HUB" app-switcher
    [[ "$status" -eq 0 ]]
    [[ "$output" != *"launch-iterm"* ]]
}
