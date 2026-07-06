#!/usr/bin/env bats
# Unit tests for `hub toggle` and the Hub.app Dock-icon install helpers.

load helpers/stubs
load helpers/fixtures

REPO_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
HUB_SCRIPT="$REPO_DIR/scripts/hub"

setup() {
    setup_stubs
    export STUB_CALLS="$HOME/stub_calls"
}

teardown() {
    teardown_stubs
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

@test "toggle calls cmd_up when hub is down" {
    run run_hub_eval "
        is_http_handler_running() { return 1; }
        cmd_up() { echo cmd_up >> \"\$STUB_CALLS\"; }
        cmd_down() { echo cmd_down >> \"\$STUB_CALLS\"; }
        cmd_toggle
    "

    [[ "$status" -eq 0 ]]
    assert_called "^cmd_up$"
    assert_not_called "^cmd_down$"
}

@test "toggle calls cmd_down when hub is up" {
    run run_hub_eval "
        is_http_handler_running() { return 0; }
        cmd_up() { echo cmd_up >> \"\$STUB_CALLS\"; }
        cmd_down() { echo cmd_down >> \"\$STUB_CALLS\"; }
        cmd_toggle
    "

    [[ "$status" -eq 0 ]]
    assert_called "^cmd_down$"
    assert_not_called "^cmd_up$"
}

@test "hub toggle dispatches to cmd_toggle" {
    run run_hub_eval "
        cmd_toggle() { echo cmd_toggle >> \"\$STUB_CALLS\"; }
        hub_main toggle
    "

    [[ "$status" -eq 0 ]]
    assert_called "^cmd_toggle$"
}

# write_hub_app_executable — creates an executable file at the path
# pin_hub_dock_icon requires before it will consider Hub.app installed.
write_hub_app_executable() {
    local app="$1"
    mkdir -p "$app/Contents/MacOS"
    cat > "$app/Contents/MacOS/Hub" <<'SH'
#!/usr/bin/env bash
exit 0
SH
    chmod +x "$app/Contents/MacOS/Hub"
}

@test "pin_hub_dock_icon skips when Hub.app is not installed" {
    run run_hub_eval "
        HUB_APP_PATH='$HOME/Applications/Hub.app'
        HUB_APP_EXECUTABLE='Hub'
        pin_hub_dock_icon
    "

    [[ "$status" -eq 0 ]]
    assert_not_called "^defaults write com.apple.dock"
}

@test "pin_hub_dock_icon skips when HUB_SKIP_LAUNCH_SERVICES is set" {
    write_hub_app_executable "$HOME/Applications/Hub.app"
    make_stub_recording defaults "" 0

    run run_hub_eval "
        HUB_APP_PATH='$HOME/Applications/Hub.app'
        HUB_APP_EXECUTABLE='Hub'
        HUB_APP_BUNDLE_ID='sh.hub.app'
        HUB_SKIP_LAUNCH_SERVICES=1
        pin_hub_dock_icon
    "

    [[ "$status" -eq 0 ]]
    assert_not_called "^defaults"
}

@test "pin_hub_dock_icon adds Hub.app when not already pinned" {
    write_hub_app_executable "$HOME/Applications/Hub.app"
    make_stub_recording defaults "" 0
    make_stub_recording killall "" 0

    run run_hub_eval "
        HUB_APP_PATH='$HOME/Applications/Hub.app'
        HUB_APP_EXECUTABLE='Hub'
        HUB_APP_BUNDLE_ID='sh.hub.app'
        pin_hub_dock_icon
    "

    [[ "$status" -eq 0 ]]
    assert_called "defaults read com.apple.dock persistent-apps"
    assert_called "defaults write com.apple.dock persistent-apps -array-add"
    assert_called "^killall Dock$"
}

@test "pin_hub_dock_icon does not match a bundle ID substring from another app" {
    write_hub_app_executable "$HOME/Applications/Hub.app"
    cat > "$STUB_BIN/defaults" <<'SH'
#!/usr/bin/env bash
echo "defaults $*" >> "${STUB_CALLS:-/tmp/stub_calls_$$}"
if [[ "$1" = "read" ]]; then
    # Bundle ID that would false-positive match "sh.hub.app" as a regex
    # (the '.' wildcards) but is not a literal match.
    echo 'shxhubxapp'
fi
exit 0
SH
    chmod +x "$STUB_BIN/defaults"
    make_stub_recording killall "" 0

    run run_hub_eval "
        HUB_APP_PATH='$HOME/Applications/Hub.app'
        HUB_APP_EXECUTABLE='Hub'
        HUB_APP_BUNDLE_ID='sh.hub.app'
        pin_hub_dock_icon
    "

    [[ "$status" -eq 0 ]]
    assert_called "defaults write com.apple.dock persistent-apps -array-add"
}

@test "pin_hub_dock_icon is a no-op when already pinned" {
    write_hub_app_executable "$HOME/Applications/Hub.app"
    cat > "$STUB_BIN/defaults" <<'SH'
#!/usr/bin/env bash
echo "defaults $*" >> "${STUB_CALLS:-/tmp/stub_calls_$$}"
if [[ "$1" = "read" ]]; then
    echo 'sh.hub.app'
fi
exit 0
SH
    chmod +x "$STUB_BIN/defaults"

    run run_hub_eval "
        HUB_APP_PATH='$HOME/Applications/Hub.app'
        HUB_APP_EXECUTABLE='Hub'
        HUB_APP_BUNDLE_ID='sh.hub.app'
        pin_hub_dock_icon
    "

    [[ "$status" -eq 0 ]]
    assert_called "defaults read com.apple.dock persistent-apps"
    assert_not_called "array-add"
    assert_not_called "^killall Dock$"
}
