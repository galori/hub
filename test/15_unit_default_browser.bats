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

run_hub_eval() {
    local code="$1"
    bash -c "
        export HOME='$HOME'
        export STUB_CALLS='$STUB_CALLS'
        source '$HUB_SCRIPT' >/dev/null 2>&1
        $code
    " 2>/dev/null
}

write_handler_plist() {
    local app="$1"
    mkdir -p "$app/Contents"
    cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>sh.hub.http-handler</string>
</dict>
</plist>
PLIST
}

@test "http handler display name uses slot 2 browser" {
    seed_apps "iTerm2:echo terminal" "Safari:echo browser"

    run run_hub_eval "http_handler_display_name"

    [[ "$status" -eq 0 ]]
    [[ "$output" = "Safari (via Hub)" ]]
}

@test "http handler display name falls back without slot 2" {
    seed_apps "iTerm2:echo terminal"

    run run_hub_eval "http_handler_display_name"

    [[ "$status" -eq 0 ]]
    [[ "$output" = "Hub HTTP Handler" ]]
}

@test "http handler app path uses slot 2 browser name" {
    seed_apps "iTerm2:echo terminal" "Google Chrome:echo browser"

    run run_hub_eval "http_handler_app_path"

    [[ "$status" -eq 0 ]]
    [[ "$output" = "$HOME/Applications/Google Chrome (via Hub).app" ]]
}

@test "stale http handler bundles are removed" {
    local active="$HOME/Applications/Safari (via Hub).app"
    local legacy="$HOME/Applications/HubHTTPHandler.app"
    local fallback="$HOME/Applications/Hub HTTP Handler.app"
    local previous="$HOME/Applications/Google Chrome (via Hub).app"
    write_handler_plist "$active"
    write_handler_plist "$legacy"
    write_handler_plist "$fallback"
    write_handler_plist "$previous"

    run run_hub_eval "cleanup_stale_http_handlers '$active'"

    [[ "$status" -eq 0 ]]
    [[ -d "$active" ]]
    [[ ! -d "$legacy" ]]
    [[ ! -d "$fallback" ]]
    [[ ! -d "$previous" ]]
}

@test "slot 2 app changes refresh http handler" {
    run run_hub_eval "
        build_http_handler() { echo build_http_handler >> \"\$STUB_CALLS\"; }
        apps_save_slot 1 iTerm2 'echo terminal' iTerm2 >/dev/null
        apps_save_slot 2 Safari 'echo browser' Safari >/dev/null
        apps_remove_slot 1 >/dev/null
        apps_remove_slot 2 >/dev/null
    "

    [[ "$status" -eq 0 ]]
    [[ "$(grep -c '^build_http_handler$' "$STUB_CALLS")" -eq 2 ]]
}

@test "apps reset refreshes http handler" {
    seed_apps "iTerm2:echo terminal" "Safari:echo browser"

    run bash -c "
        export HOME='$HOME'
        export STUB_CALLS='$STUB_CALLS'
        source '$HUB_SCRIPT' >/dev/null 2>&1
        build_http_handler() { echo build_http_handler >> \"\$STUB_CALLS\"; }
        cmd_apps reset -y
    " 2>/dev/null

    [[ "$status" -eq 0 ]]
    assert_called "^build_http_handler$"
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
