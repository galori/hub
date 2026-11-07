#!/usr/bin/env bats

REPO_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
HUB_HOTKEYD_SRC="$REPO_DIR/lib/hub_hotkeyd.swift"
HUB_BAR_SRC="$REPO_DIR/lib/hub_bar.swift"

@test "independent listener observes modifier changes and key-down events" {
    grep -Fq 'eventsOfInterest: flagsChangedMask | keyDownMask' "$HUB_HOTKEYD_SRC"
    grep -Fq 'return Unmanaged.passUnretained(event)' "$HUB_HOTKEYD_SRC"
    ! grep -Fq 'CGEvent.tapCreate' "$HUB_BAR_SRC"
}

@test "listener re-enables disabled taps and retries failed creation with bounded backoff" {
    grep -Fq 'CGEvent.tapEnable(tap: tap, enable: true)' "$HUB_HOTKEYD_SRC"
    grep -Fq 'CFMachPortIsValid(tap)' "$HUB_HOTKEYD_SRC"
    grep -Fq 'min(tapRetryDelay * 2, 30)' "$HUB_HOTKEYD_SRC"
    grep -Fq 'resetGestureAndSynchronize()' "$HUB_HOTKEYD_SRC"
    grep -Fq 'statusSnapshot().tapHealth != "healthy"' "$HUB_HOTKEYD_SRC"
    grep -Fq '$0.tapHealth = "recreating"' "$HUB_HOTKEYD_SRC"
}

@test "sleep and session changes reset the listener grace period" {
    grep -Fq 'NSWorkspace.didWakeNotification' "$HUB_HOTKEYD_SRC"
    grep -Fq 'beginGracePeriod(reason: "wake")' "$HUB_HOTKEYD_SRC"
    grep -Fq 'NSWorkspace.sessionDidBecomeActiveNotification' "$HUB_HOTKEYD_SRC"
}

@test "bar heartbeat replies are scheduled on its main thread" {
    grep -Fq 'DispatchQueue.main.async { [weak self] in self?.applyPendingHotkeyMessages() }' "$HUB_BAR_SRC"
    grep -Fq 'HotkeyDatagram.send(reply, to: HotkeyPaths.hotkeysSocket)' "$HUB_BAR_SRC"
    grep -Fq 'message.senderPID == identity.pid' "$HUB_HOTKEYD_SRC"
}

@test "bar discards stale or future overlay requests before touching UI" {
    grep -Fq 'overlay.isFresh(maximumAge: 1)' "$HUB_BAR_SRC"
}

@test "overlay resynchronization respects pinned visibility" {
    grep -Fq 'sendOverlayState(snapshot.clusterOverlayVisible, immediate: snapshot.clusterOverlayVisible)' \
        "$HUB_HOTKEYD_SRC"
}

@test "automatic recovery resamples health before terminating the recorded process" {
    grep -Fq 'let stillStalledAfterSample = controlQueue.sync' "$HUB_HOTKEYD_SRC"
    grep -Fq 'readBarIdentity() == recordedIdentity' "$HUB_HOTKEYD_SRC"
    grep -Fq 'processIsUnchanged(identity)' "$HUB_HOTKEYD_SRC"
}

@test "automatic recovery rechecks the Hub session before terminating the bar" {
    local recovery_body sample_guard termination_call session_guard_line
    recovery_body="$(sed -n '/private func performAutomaticRecovery(sessionID: String)/,/^    }/p' \
        "$HUB_HOTKEYD_SRC")"
    sample_guard="$(printf '%s\n' "$recovery_body" \
        | grep -n -F 'guard stillStalledAfterSample else {' | cut -d: -f1)"
    termination_call="$(printf '%s\n' "$recovery_body" \
        | grep -n -F 'switch terminateBarIfUnchanged(oldIdentity)' | cut -d: -f1)"
    session_guard_line="$(printf '%s\n' "$recovery_body" \
        | awk -v sample="$sample_guard" -v termination="$termination_call" \
            'NR > sample && NR < termination && index($0, "guard activeSessionID() == sessionID else {") > 0 { print NR; exit }')"

    [[ -n "$sample_guard" ]]
    [[ -n "$termination_call" ]]
    [[ -n "$session_guard_line" ]]
}
