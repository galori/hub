#!/usr/bin/env bats

BATS_TEST_DIRNAME="${BATS_TEST_DIRNAME:-$(dirname "$0")}"
load helpers

setup() {
    require_live_session
    HUB_BIN="$(hub_bin)"
    HUB_BAR_BIN="$HOME/.config/hub/hub_bar"
    HUB_HOTKEYS_BIN="$HOME/Applications/Hub Hotkeys.app/Contents/MacOS/HubHotkeys"
    BAR_PID_FILE="$HOME/.config/hub/hub_bar.pid"
    BAR_IDENTITY_FILE="$HOME/.config/hub/hub_bar.identity"

    local status
    status="$("$HUB_BIN" hotkeys status --json)"
    if [[ "$(printf '%s' "$status" | jq -r '.running')" != "true" \
          || "$(printf '%s' "$status" | jq -r '.launchdLoaded')" != "true" ]]; then
        echo "Hub Hotkeys.app is not running as a launchd job. Start Hub with: $HUB_BIN up" >&3
        return 1
    fi
    if [[ "$(printf '%s' "$status" | jq -r '.tapHealth // "unknown"')" != "healthy" ]]; then
        echo "Hub Hotkeys event tap is not healthy. Enable Input Monitoring in System Settings, then run: $HUB_BIN hotkeys request-access" >&3
        return 1
    fi

    ORIGINAL_FULLSCREEN="$(aerospace list-windows --focused --format '%{window-is-fullscreen}' 2>/dev/null)"
    ORIGINAL_BAR_PID="$(cat "$BAR_PID_FILE" 2>/dev/null || true)"
    ORIGINAL_BAR_START="$(ps -p "$ORIGINAL_BAR_PID" -o lstart= 2>/dev/null | sed 's/^ *//;s/ *$//')"
    ORIGINAL_BAR_COMMAND="$(ps -p "$ORIGINAL_BAR_PID" -o command= 2>/dev/null)"
    ORIGINAL_BAR_IDENTITY="$(cat "$BAR_IDENTITY_FILE" 2>/dev/null || true)"
    ORIGINAL_BAR_START_TIME="$(printf '%s' "$ORIGINAL_BAR_IDENTITY" | jq -r '.startTime // empty')"
    if [[ "$ORIGINAL_BAR_COMMAND" != "$HUB_BAR_BIN"* ]] \
       || ! printf '%s' "$status" | jq -e \
            --argjson pid "$ORIGINAL_BAR_PID" \
            --argjson startTime "$ORIGINAL_BAR_START_TIME" \
            '.barPID == $pid and .barStartTime == $startTime and .barHeartbeatAge < 3' \
            >/dev/null; then
        echo "Hub Bar is not responding with a validated process identity. Start Hub with: $HUB_BIN up" >&3
        return 1
    fi
    BAR_SUSPENDED=0
    OVERLAY_REQUESTED=0
}

teardown() {
    if [[ "${OVERLAY_REQUESTED:-0}" == "1" ]]; then
        "$HUB_BIN" cluster hide >/dev/null 2>&1 || true
    fi

    if [[ "${BAR_SUSPENDED:-0}" == "1" && -n "${ORIGINAL_BAR_PID:-}" ]]; then
        local current_start current_command
        current_start="$(ps -p "$ORIGINAL_BAR_PID" -o lstart= 2>/dev/null | sed 's/^ *//;s/ *$//')"
        current_command="$(ps -p "$ORIGINAL_BAR_PID" -o command= 2>/dev/null)"
        if [[ "$current_start" == "${ORIGINAL_BAR_START:-}" \
              && "$current_command" == "${HUB_BAR_BIN:-}"* ]]; then
            kill -CONT "$ORIGINAL_BAR_PID" 2>/dev/null || true
        fi
    fi

    if [[ "${ORIGINAL_FULLSCREEN:-}" =~ ^(true|false)$ ]]; then
        local current
        current="$(aerospace list-windows --focused --format '%{window-is-fullscreen}' 2>/dev/null || true)"
        if [[ "$current" != "$ORIGINAL_FULLSCREEN" ]]; then
            aerospace fullscreen >/dev/null 2>&1 || true
        fi
    fi
}

window_is_fullscreen() {
    aerospace list-windows --focused --format '%{window-is-fullscreen}' 2>/dev/null
}

cluster_overlay_window() {
    swift -e 'import Cocoa
let pidPath = NSHomeDirectory() + "/.config/hub/hub_bar.pid"
guard let rawPID = try? String(contentsOfFile: pidPath, encoding: .utf8),
      let hubPID = Int(rawPID.trimmingCharacters(in: .whitespacesAndNewlines)) else { exit(1) }
let options: CGWindowListOption = [.excludeDesktopElements, .optionOnScreenOnly]
let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
for window in windows {
    guard (window[kCGWindowOwnerPID as String] as? NSNumber)?.intValue == hubPID,
          let bounds = window[kCGWindowBounds as String] as? NSDictionary,
          let height = bounds["Height"] as? NSNumber,
          height.intValue >= 50 && height.intValue <= 54 else { continue }
    print("visible")
    exit(0)
}
exit(1)'
}

double_tap_right_shift() {
    swift -e 'import CoreGraphics
import Darwin
let source = CGEventSource(stateID: .hidSystemState)
for _ in 0..<2 {
    CGEvent(keyboardEventSource: source, virtualKey: 60, keyDown: true)?.post(tap: .cghidEventTap)
    usleep(50_000)
    CGEvent(keyboardEventSource: source, virtualKey: 60, keyDown: false)?.post(tap: .cghidEventTap)
    usleep(100_000)
}'
}

@test "fullscreen gestures work while the bar is stopped and recovery restores IPC" {
    [[ "$ORIGINAL_FULLSCREEN" == "true" || "$ORIGINAL_FULLSCREEN" == "false" ]]
    [[ "$ORIGINAL_BAR_PID" =~ ^[0-9]+$ ]]
    [[ -n "$ORIGINAL_BAR_START" ]]
    [[ -n "$ORIGINAL_BAR_IDENTITY" ]]
    [[ -n "$ORIGINAL_BAR_START_TIME" ]]
    [[ "$ORIGINAL_BAR_COMMAND" == "$HUB_BAR_BIN"* ]]

    local expected
    if [[ "$ORIGINAL_FULLSCREEN" == "true" ]]; then expected=false; else expected=true; fi
    kill -STOP "$ORIGINAL_BAR_PID"
    BAR_SUSPENDED=1

    double_tap_right_shift
    wait_for 6 "fullscreen toggles while Hub Bar is stopped" \
        "[[ \"\$(window_is_fullscreen)\" == '$expected' ]]"
    double_tap_right_shift
    wait_for 6 "fullscreen returns while Hub Bar is stopped" \
        "[[ \"\$(window_is_fullscreen)\" == '$ORIGINAL_FULLSCREEN' ]]"

    wait_for 50 "watchdog replaces the stopped bar and restores its heartbeat" '
        status="$("$HUB_BIN" hotkeys status --json)" &&
        identity="$(cat "$BAR_IDENTITY_FILE" 2>/dev/null)" &&
        [[ "$(printf "%s" "$identity" | jq -r ".startTime")" != \
           "$(printf "%s" "$ORIGINAL_BAR_IDENTITY" | jq -r ".startTime")" ]] &&
        printf "%s" "$status" | jq -e \
            --argjson oldStartTime "$ORIGINAL_BAR_START_TIME" \
            ".barHeartbeatAge < 3 and .barStartTime != \$oldStartTime and (.recoveryHistory | last | .result) == \"restarted\"" \
            >/dev/null
    '

    OVERLAY_REQUESTED=1
    run "$HUB_BIN" cluster show
    [[ "$status" -eq 0 ]]
    wait_for 5 "overlay appears through the recovered bar socket" \
        '[[ -n "$(cluster_overlay_window)" ]]'
    run "$HUB_BIN" cluster hide
    [[ "$status" -eq 0 ]]
    wait_for 5 "overlay hides through the recovered bar socket" \
        '[[ -z "$(cluster_overlay_window)" ]]'
}

@test "launchd restarts the hotkey helper after a crash" {
    local status helper_pid helper_command
    status="$("$HUB_BIN" hotkeys status --json)"
    helper_pid="$(printf '%s' "$status" | jq -r '.helperPID // empty')"
    [[ "$helper_pid" =~ ^[0-9]+$ ]]
    helper_command="$(ps -p "$helper_pid" -o command= 2>/dev/null)"
    [[ "$helper_command" == "$HUB_HOTKEYS_BIN"* ]]

    kill -KILL "$helper_pid"
    wait_for 70 "launchd starts a healthy replacement helper" '
        status="$("$HUB_BIN" hotkeys status --json)" &&
        new_pid="$(printf "%s" "$status" | jq -r ".helperPID // empty")" &&
        [[ "$new_pid" =~ ^[0-9]+$ && "$new_pid" != "$helper_pid" ]] &&
        printf "%s" "$status" | jq -e \
            ".tapHealth == \"healthy\" and .listenerHeartbeatAge < 3 and .barHeartbeatAge < 3" \
            >/dev/null
    '
}
