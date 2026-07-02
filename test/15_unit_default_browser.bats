#!/usr/bin/env bats

load helpers/stubs
load helpers/fixtures

REPO_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
HUB_SCRIPT="$REPO_DIR/scripts/hub"

setup() {
    setup_stubs
    export STUB_CALLS="$HOME/stub_calls"
    export PREV_BROWSER_FILE="$HOME/.config/hub/prev_browser"
    mkdir -p "$HOME/.config/hub"
}

teardown() {
    teardown_stubs
}

write_browser_ctl() {
    local current_browser="$1"
    cat > "$HOME/.config/hub/browser_ctl" <<SH
#!/usr/bin/env bash
echo "browser_ctl \$*" >> "$STUB_CALLS"
if [[ "\${1:-}" = "get" ]]; then
    echo "$current_browser"
fi
SH
    chmod +x "$HOME/.config/hub/browser_ctl"
}

run_hub_function() {
    local function_name="$1"
    bash -c "
        export HOME='$HOME'
        export STUB_CALLS='$STUB_CALLS'
        source '$HUB_SCRIPT' >/dev/null 2>&1
        $function_name
    " 2>/dev/null
}

@test "hub up browser save stores a non-hub default browser before switching" {
    write_browser_ctl "com.apple.Safari"

    run_hub_function save_and_set_hub_default_browser

    [[ "$(cat "$PREV_BROWSER_FILE")" = "com.apple.Safari" ]]
    assert_called "browser_ctl get"
    assert_called "browser_ctl set sh.hub.http-handler"
}

@test "hub up browser save does not store HubHTTPHandler as the previous browser" {
    write_browser_ctl "sh.hub.http-handler"

    run_hub_function save_and_set_hub_default_browser

    [[ ! -f "$PREV_BROWSER_FILE" ]]
    assert_called "browser_ctl get"
    assert_called "browser_ctl set sh.hub.http-handler"
}

@test "hub up browser save preserves an existing real previous browser when current is HubHTTPHandler" {
    write_browser_ctl "sh.hub.http-handler"
    echo "com.google.Chrome" > "$PREV_BROWSER_FILE"

    run_hub_function save_and_set_hub_default_browser

    [[ "$(cat "$PREV_BROWSER_FILE")" = "com.google.Chrome" ]]
    assert_called "browser_ctl get"
    assert_called "browser_ctl set sh.hub.http-handler"
}

@test "hub down browser restore refuses a stale HubHTTPHandler saved browser" {
    write_browser_ctl "ignored"
    echo "sh.hub.http-handler" > "$PREV_BROWSER_FILE"

    run_hub_function restore_previous_default_browser

    [[ ! -f "$PREV_BROWSER_FILE" ]]
    assert_not_called "browser_ctl set sh.hub.http-handler"
}

@test "hub reboot disables default browser changes for down and up" {
    bash -c "
        export HOME='$HOME'
        export STUB_CALLS='$STUB_CALLS'
        source '$HUB_SCRIPT' >/dev/null 2>&1
        cmd_down() { echo \"down:\${HUB_SKIP_DEFAULT_BROWSER_CHANGE:-0}\" >> '$STUB_CALLS'; }
        cmd_install() { echo \"install:\${HUB_SKIP_DEFAULT_BROWSER_CHANGE:-0}\" >> '$STUB_CALLS'; }
        cmd_up() { echo \"up:\${HUB_SKIP_DEFAULT_BROWSER_CHANGE:-0}\" >> '$STUB_CALLS'; }
        cmd_reboot
    " >/dev/null 2>&1

    assert_called "^down:1$"
    assert_called "^install:0$"
    assert_called "^up:1$"
}
