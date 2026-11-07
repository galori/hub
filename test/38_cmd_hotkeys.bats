#!/usr/bin/env bats

load helpers/stubs
load helpers/fixtures

REPO_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

setup() {
    setup_stubs
    export STUB_CALLS="$HOME/stub_calls"
    source "$REPO_DIR/scripts/hub"
}

teardown() {
    teardown_stubs
}

@test "hotkeys status prints the daemon snapshot as JSON" {
    cat > "$HUB_RUNTIME_DIR/hub-hotkeyd-status.json" <<'JSON'
{"tapHealth":"healthy","inputMonitoringPermission":"granted","listenerHeartbeatAge":0.2,"barHeartbeatAge":0.7,"barHeartbeatResponseLatency":0.1,"slowBarHeartbeatCount":1,"fullscreenActionFailureCount":2,"recoveryHistory":[]}
JSON

    run cmd_hotkeys status --json

    [[ "$status" -eq 0 ]]
    [[ "$(printf '%s' "$output" | jq -r '.tapHealth')" == "healthy" ]]
    [[ "$(printf '%s' "$output" | jq -r '.slowBarHeartbeatCount')" == "1" ]]
    [[ "$(printf '%s' "$output" | jq -r '.launchdLoaded')" == "false" ]]
}

@test "hotkeys status reports an absent daemon as valid JSON" {
    run cmd_hotkeys status --json

    [[ "$status" -eq 0 ]]
    [[ "$(printf '%s' "$output" | jq -r '.running')" == "false" ]]
    [[ "$(printf '%s' "$output" | jq -r '.launchdLoaded')" == "false" ]]
}

@test "hotkeys status prints recent recovery and action diagnostics" {
    cat > "$HUB_RUNTIME_DIR/hub-hotkeyd-status.json" <<'JSON'
{"updatedAt":9999999999,"tapHealth":"healthy","inputMonitoringPermission":"granted","fullscreenActionFailureCount":1,"lastFullscreenActionError":"aerospace unavailable","lastRecoveryError":"restart failed","lastRecoverySample":"/tmp/bar.sample","recoveryHistory":[{"result":"restarted"}]}
JSON

    run cmd_hotkeys status

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Last fullscreen action error: aerospace unavailable"* ]]
    [[ "$output" == *"Last recovery event: restarted"* ]]
    [[ "$output" == *"Last recovery error: restart failed"* ]]
    [[ "$output" == *"Last stack sample: /tmp/bar.sample"* ]]
}

@test "cluster show and hide send coalescible overlay requests" {
    make_stub_recording hub_hotkeyd "" 0
    HUB_HOTKEYS_BIN="$STUB_BIN/hub_hotkeyd"

    cmd_cluster show
    cmd_cluster hide

    assert_called '^hub_hotkeyd --overlay show$'
    assert_called '^hub_hotkeyd --overlay hide$'
}

@test "launch agent uses the bundled helper with KeepAlive and restart throttling" {
    mkdir -p "$(dirname "$HUB_HOTKEYS_BIN")"
    : > "$HUB_HOTKEYS_BIN"
    chmod +x "$HUB_HOTKEYS_BIN"
    deploy_hotkeys_launch_agent

    [[ -f "$HUB_HOTKEYS_PLIST" ]]
    grep -Fq '<string>sh.hub.hotkeys</string>' "$HUB_HOTKEYS_PLIST"
    grep -Fq '<key>KeepAlive</key>' "$HUB_HOTKEYS_PLIST"
    grep -Fq '<integer>10</integer>' "$HUB_HOTKEYS_PLIST"
    grep -Fq "$HUB_CONFIG_DIR" "$HUB_HOTKEYS_PLIST"
    grep -Fq "$HUB_LIFECYCLE_LOCK_DIR" "$HUB_HOTKEYS_PLIST"
    plutil -lint "$HUB_HOTKEYS_PLIST" >/dev/null
}

@test "helper app bundle declares its identity and Input Monitoring purpose" {
    mkdir -p "$(dirname "$HUB_HOTKEYS_BIN")"
    printf 'stub\n' > "$HUB_HOTKEYS_BIN"
    chmod +x "$HUB_HOTKEYS_BIN"
    HUB_SKIP_LAUNCH_SERVICES=1

    build_hotkeys_app

    grep -Fq '<string>sh.hub.hotkeys</string>' "$HUB_HOTKEYS_APP_PATH/Contents/Info.plist"
    grep -Fq '<key>NSInputMonitoringUsageDescription</key>' "$HUB_HOTKEYS_APP_PATH/Contents/Info.plist"
    plutil -lint "$HUB_HOTKEYS_APP_PATH/Contents/Info.plist" >/dev/null
}

@test "hotkeys restart bootstraps the launch agent under the lifecycle lock" {
    make_stub_recording launchctl "" 0
    mkdir -p "$(dirname "$HUB_HOTKEYS_BIN")"
    : > "$HUB_HOTKEYS_BIN"
    chmod +x "$HUB_HOTKEYS_BIN"
    mkdir -p "$(dirname "$HUB_HOTKEYS_PLIST")"
    : > "$HUB_HOTKEYS_PLIST"

    cmd_hotkeys restart

    assert_called '^launchctl bootout gui/'
    assert_called '^launchctl bootstrap gui/'
    [[ ! -e "$HUB_LIFECYCLE_LOCK_DIR" ]]
}

@test "hotkeys request-access sends the helper permission request" {
    make_stub_recording launchctl "" 0
    make_stub_recording hub_hotkeyd "" 0
    HUB_HOTKEYS_BIN="$STUB_BIN/hub_hotkeyd"
    mkdir -p "$(dirname "$HUB_HOTKEYS_PLIST")"
    : > "$HUB_HOTKEYS_PLIST"

    cmd_hotkeys request-access

    assert_called '^hub_hotkeyd --request-access$'
}

@test "hotkeys rejects unknown actions" {
    run cmd_hotkeys unknown

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"Usage:"* ]]
}
