#!/usr/bin/env bats
# Unit tests for the per-app launch lock used by the window snapshot/corral path.

load helpers/stubs

REPO_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
HUB="$REPO_DIR/scripts/hub"

setup() {
    setup_stubs
    export HUB_APP_LAUNCH_LOCK_TIMEOUT=1
    export HUB_OPEN_POLL_ATTEMPTS=1
    export HUB_OPEN_POLL_INTERVAL=0.01
    export HUB_LOG_FILE="$HOME/.config/hub/hub.log"
}

teardown() {
    teardown_stubs
}

@test "same-app launch lock blocks a second owner and releases only its owner" {
    run bash -c "
        export HOME='$HOME' HUB_HOME='$HOME' HUB_CONFIG_DIR='$HUB_CONFIG_DIR' HUB_RUNTIME_DIR='$HUB_RUNTIME_DIR' HUB_APP_LAUNCH_LOCK_TIMEOUT=1
        source '$HUB' >/dev/null 2>&1
        _app_launch_lock_acquire Terminal
        first=\"\$APP_LAUNCH_LOCK_DIR_CURRENT\"
        if _app_launch_lock_acquire Terminal; then
            exit 11
        fi
        [[ -L \"\$first\" ]]
        _app_launch_lock_release \"\$first\"
        [[ ! -e \"\$first\" ]]
    "
    [[ "$status" -eq 0 ]]
}

@test "stale app lock owner is recovered" {
    run bash -c "
        export HOME='$HOME' HUB_HOME='$HOME' HUB_CONFIG_DIR='$HUB_CONFIG_DIR' HUB_RUNTIME_DIR='$HUB_RUNTIME_DIR'
        source '$HUB' >/dev/null 2>&1
        mkdir -p \"\$HUB_APP_LAUNCH_LOCK_DIR\"
        key=\"\$(_app_launch_lock_key Terminal)\"
        ln -s 999999 \"\$HUB_APP_LAUNCH_LOCK_DIR/\$key.lock\"
        _app_launch_lock_acquire Terminal
        _app_launch_lock_release \"\$APP_LAUNCH_LOCK_DIR_CURRENT\"
    "
    [[ "$status" -eq 0 ]]
}

@test "different apps use independent locks" {
    run bash -c "
        export HOME='$HOME' HUB_HOME='$HOME' HUB_CONFIG_DIR='$HUB_CONFIG_DIR' HUB_RUNTIME_DIR='$HUB_RUNTIME_DIR'
        source '$HUB' >/dev/null 2>&1
        _app_launch_lock_acquire Terminal
        first=\"\$APP_LAUNCH_LOCK_DIR_CURRENT\"
        _app_launch_lock_acquire Browser
        second=\"\$APP_LAUNCH_LOCK_DIR_CURRENT\"
        [[ \"\$first\" != \"\$second\" ]]
        _app_launch_lock_release \"\$second\"
        _app_launch_lock_release \"\$first\"
    "
    [[ "$status" -eq 0 ]]
}

@test "strict launch failure removes the app lock and per-launch diagnostics" {
    run bash -c "
        export HOME='$HOME' HUB_HOME='$HOME' HUB_CONFIG_DIR='$HUB_CONFIG_DIR' HUB_RUNTIME_DIR='$HUB_RUNTIME_DIR' HUB_OPEN_POLL_ATTEMPTS=1 HUB_OPEN_POLL_INTERVAL=0.01
        source '$HUB' >/dev/null 2>&1
        progress_step() { :; }
        set +e
        _launch_and_corral Terminal true A '$HOME' '' true
        rc=\$?
        set -e
        [[ \"\$rc\" -ne 0 ]]
        [[ -z \"\$(find \"\$HUB_APP_LAUNCH_LOCK_DIR\" -type l -print -quit 2>/dev/null)\" ]]
        [[ -z \"\$(find \"\$HUB_RUNTIME_DIR\" -name 'open-err.*' -print -quit 2>/dev/null)\" ]]
    "
    [[ "$status" -eq 0 ]]
}
