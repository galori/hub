#!/usr/bin/env bats

load helpers/stubs
load helpers/fixtures

REPO_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

setup() {
    setup_stubs
    export STUB_CALLS="$HOME/stub_calls"
    unset HUB_SESSION_FILE
    source "$REPO_DIR/scripts/hub"
    HUB_BAR_BIN="$STUB_BIN/hub_bar"
    HUB_HOTKEYS_BIN="$STUB_BIN/hub_hotkeyd"
    HUB_HOTKEYS_PLIST="$HUB_TEST_DIR/launchd/sh.hub.hotkeys.plist"
    cat > "$HUB_BAR_BIN" <<SH
#!/usr/bin/env bash
echo "hub_bar" >> "$STUB_CALLS"
exit 0
SH
    : > "$HUB_HOTKEYS_BIN"
    chmod +x "$HUB_BAR_BIN" "$HUB_HOTKEYS_BIN"
    mkdir -p "$(dirname "$HUB_HOTKEYS_PLIST")"
    : > "$HUB_HOTKEYS_PLIST"
}

teardown() {
    if [[ "${UNRELATED_PID:-}" =~ ^[0-9]+$ ]]; then
        kill "$UNRELATED_PID" 2>/dev/null || true
        wait "$UNRELATED_PID" 2>/dev/null || true
    fi
    teardown_stubs
}

@test "bar receives the isolated default session-file path" {
    local child_session
    child_session="$(bash -c 'printf "%s" "$HUB_SESSION_FILE"')"

    [[ "$child_session" == "$HUB_CONFIG_DIR/hub-session" ]]
}

@test "session activation creates a custom session-file parent directory" {
    HUB_SESSION_FILE="$HUB_TEST_DIR/nested/session/hub-session"

    hub_session_activate

    [[ -s "$HUB_SESSION_FILE" ]]
}

@test "bar-up creates a session and bootstraps hotkeys before starting the bar" {
    cat > "$STUB_BIN/launchctl" <<SH
#!/usr/bin/env bash
echo "launchctl \$*" >> "$STUB_CALLS"
if [[ "\$1" == "print" ]]; then exit 1; fi
exit 0
SH
    chmod +x "$STUB_BIN/launchctl"

    hub_environment_start_bar_stack

    [[ -s "$HUB_SESSION_FILE" ]]
    assert_called '^launchctl bootstrap gui/'
    local attempts=0
    while ! grep -q '^hub_bar$' "$STUB_CALLS" 2>/dev/null && [[ "$attempts" -lt 20 ]]; do
        sleep 0.05
        attempts=$((attempts + 1))
    done
    assert_called '^hub_bar$'
    [[ "$(grep -n '^launchctl bootstrap' "$STUB_CALLS" | cut -d: -f1)" -lt \
       "$(grep -n '^hub_bar$' "$STUB_CALLS" | cut -d: -f1)" ]]
}

@test "bar-only restart keeps the hotkey launch agent loaded" {
    cat > "$STUB_BIN/launchctl" <<SH
#!/usr/bin/env bash
echo "launchctl \$*" >> "$STUB_CALLS"
exit 0
SH
    chmod +x "$STUB_BIN/launchctl"
    cat > "$HUB_HOTKEYS_BIN" <<SH
#!/usr/bin/env bash
echo "hub_hotkeyd \$*" >> "$STUB_CALLS"
exit 0
SH
    chmod +x "$HUB_HOTKEYS_BIN"

    hub_bar_restart

    assert_called '^hub_hotkeyd --bar-restarting$'
    assert_not_called '^launchctl bootout .*sh.hub.hotkeys'
    assert_called '^hub_bar$'
}

@test "install reloads an active helper even when the bar has no pidfile" {
    make_stub_recording launchctl "" 0

    reload_running_services

    assert_called '^launchctl bootout gui/.*sh\.hub\.hotkeys$'
    assert_called '^launchctl bootstrap gui/.*sh\.hub\.hotkeys\.plist$'
    assert_not_called '^hub_bar$'
}

@test "bar-down ignores an unrelated process referenced by a stale pidfile" {
    sleep 30 &
    UNRELATED_PID=$!
    printf '%s\n' "$UNRELATED_PID" > "$HUB_BAR_PIDFILE"

    hub_bar_down || true

    kill -0 "$UNRELATED_PID" 2>/dev/null
    [[ ! -e "$HUB_BAR_PIDFILE" ]]
}

@test "shutdown clears the session before unloading hotkeys" {
    cat > "$STUB_BIN/launchctl" <<SH
#!/usr/bin/env bash
echo "launchctl \$*" >> "$STUB_CALLS"
if [[ "\$1" == "bootout" && -e "$HUB_SESSION_FILE" ]]; then exit 8; fi
if [[ "\$1" == "print" ]]; then exit 0; fi
exit 0
SH
    chmod +x "$STUB_BIN/launchctl"
    printf 'session-test\n' > "$HUB_SESSION_FILE"

    hub_environment_stop_bar_stack || [[ "$?" -eq 1 ]]

    [[ ! -e "$HUB_SESSION_FILE" ]]
    assert_called '^launchctl bootout gui/'
    assert_called '^launchctl remove sh.hub.hub_bar$'
}

@test "shutdown disables recovery before waiting for the lifecycle lock" {
    local recovery_owner recovery_observed_active="$HUB_TEST_DIR/recovery_observed_active"
    printf 'session-test\n' > "$HUB_SESSION_FILE"
    mkdir -p "$HUB_LIFECYCLE_LOCK_DIR"
    (
        sleep 0.2
        [[ -e "$HUB_SESSION_FILE" ]] && : > "$recovery_observed_active"
        rm -f "$HUB_LIFECYCLE_LOCK_DIR/owner"
        rmdir "$HUB_LIFECYCLE_LOCK_DIR" 2>/dev/null || true
    ) &
    recovery_owner=$!
    printf '%s\n' "$recovery_owner" > "$HUB_LIFECYCLE_LOCK_DIR/owner"

    hub_environment_stop_bar_stack || [[ "$?" -eq 1 ]]
    wait "$recovery_owner"

    [[ ! -e "$recovery_observed_active" ]]
    [[ ! -e "$HUB_SESSION_FILE" ]]
}

@test "recovery start requires the active session and lifecycle-lock owner" {
    printf 'session-test\n' > "$HUB_SESSION_FILE"
    mkdir -p "$HUB_LIFECYCLE_LOCK_DIR"
    printf '%s\n' "$$" > "$HUB_LIFECYCLE_LOCK_DIR/owner"
    make_stub_recording launchctl "" 0

    cmd_bar_recovery_start session-test "$$"
    assert_called '^hub_bar$'

    run cmd_bar_recovery_start stale-session "$$"
    [[ "$status" -ne 0 ]]
}

@test "bar startup fails when the bar executable is missing" {
    HUB_BAR_BIN="$STUB_BIN/missing_hub_bar"

    run hub_bar_start_locked

    [[ "$status" -ne 0 ]]
}

@test "delayed fullscreen bar restarts acquire locks from a fresh Hub process" {
    [[ "$(grep -Fc '(sleep 0.8; "$SCRIPT_DIR/hub" bar-restart)' "$REPO_DIR/scripts/hub")" -eq 2 ]]
}
