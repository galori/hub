#!/usr/bin/env bats
# Unit tests for the opaque terminal command request transport and zsh runner.

load helpers/stubs

REPO_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
RUNNER="$REPO_DIR/scripts/lib/terminal_command_runner.zsh"
HUB="$REPO_DIR/scripts/hub"

setup() {
    setup_stubs
    export TERMINAL_TEST_DIR="$HUB_TEST_DIR/terminal"
    export HUB_RUNTIME_DIR="$TERMINAL_TEST_DIR/runtime"
    export HUB_TERMINAL_REQUEST_DIR="$HUB_RUNTIME_DIR/terminal-commands"
    mkdir -p "$HUB_TERMINAL_REQUEST_DIR"
    chmod 700 "$HUB_TERMINAL_REQUEST_DIR"
    : > "$HUB_TERMINAL_REQUEST_DIR/.hub-terminal-command-dir"
    chmod 600 "$HUB_TERMINAL_REQUEST_DIR/.hub-terminal-command-dir"
}

teardown() {
    teardown_stubs
}

@test "runner preserves exact argv, including empty values and newlines" {
    local workspace="$TERMINAL_TEST_DIR/work space"
    mkdir -p "$workspace"
    local record="$TERMINAL_TEST_DIR/argv.bin"
    local cwd_record="$TERMINAL_TEST_DIR/cwd"
    local shell_record="$TERMINAL_TEST_DIR/shell"
    local executable="$TERMINAL_TEST_DIR/record-command"
    local shell_stub="$TERMINAL_TEST_DIR/record-shell"

    cat > "$executable" <<'SH'
#!/bin/sh
printf '%s\0' "$0" "$@" > "$ARGV_RECORD"
pwd > "$CWD_RECORD"
exit 0
SH
    chmod +x "$executable"
    cat > "$shell_stub" <<'SH'
#!/bin/sh
printf '%s\n' "$*" > "$SHELL_RECORD"
exit 0
SH
    chmod +x "$shell_stub"

    local request="$HUB_TERMINAL_REQUEST_DIR/request.test"
    local ack="$HUB_TERMINAL_REQUEST_DIR/request.test.ack"
    printf '%s\0%s\0%s\0%s\0%s\0' "$workspace" "$executable" "" 'two words' $'line\nnext' > "$request"
    chmod 600 "$request"

    run env HOME="$TERMINAL_TEST_DIR/home" SHELL="$shell_stub" \
        ARGV_RECORD="$record" CWD_RECORD="$cwd_record" SHELL_RECORD="$shell_record" \
        "$RUNNER" "$request" "$ack"
    [[ "$status" -eq 0 ]]
    [[ "$(cat "$cwd_record")" == "$workspace" ]]
    [[ "$(cat "$shell_record")" == "-il" ]]
    printf '%s\0%s\0%s\0%s\0' "$executable" "" 'two words' $'line\nnext' > "$TERMINAL_TEST_DIR/expected.bin"
    cmp -s "$TERMINAL_TEST_DIR/expected.bin" "$record"
    [[ "$(cat "$ack")" == "READY" ]]
    [[ ! -e "$request" ]]
    [[ ! -e "$request.claimed" ]]
}

@test "runner reports decode and cd errors without copying command data" {
    local executable="$TERMINAL_TEST_DIR/should-not-run"
    local secret='secret-command-value'
    local request="$HUB_TERMINAL_REQUEST_DIR/request.bad"
    local ack="$HUB_TERMINAL_REQUEST_DIR/request.bad.ack"
    cat > "$executable" <<SH
#!/bin/sh
printf '%s\n' '$secret' > "$TERMINAL_TEST_DIR/executed"
SH
    chmod +x "$executable"
    printf '%s\0%s\0' "$TERMINAL_TEST_DIR/missing" "$executable" > "$request"
    chmod 600 "$request"

    run env HOME="$TERMINAL_TEST_DIR/home" SHELL=/bin/sh "$RUNNER" "$request" "$ack"
    [[ "$status" -ne 0 ]]
    [[ "$(cat "$ack")" == ERROR* ]]
    [[ "$(cat "$ack")" != *"$secret"* ]]
    [[ ! -e "$TERMINAL_TEST_DIR/executed" ]]
    [[ ! -e "$request" ]]
}

@test "request helper writes a private nul-delimited payload and cleanup is safe" {
    local workspace="$TERMINAL_TEST_DIR/workspace"
    mkdir -p "$workspace"
    run bash -c "
        export HOME='$HOME'
        export HUB_HOME='$HOME'
        export HUB_CONFIG_DIR='$HUB_CONFIG_DIR'
        export HUB_RUNTIME_DIR='$HUB_RUNTIME_DIR'
        export HUB_TERMINAL_REQUEST_DIR='$HUB_TERMINAL_REQUEST_DIR'
        export APPS_FILE='$APPS_FILE'
        source '$HUB' >/dev/null 2>&1
        _terminal_command_request_create '$workspace' 'cmd' '' 'line
next'
        printf '%s\\n' \"\$TERMINAL_COMMAND_REQUEST_PATH\" \"\$TERMINAL_COMMAND_ACK_PATH\"
    "
    [[ "$status" -eq 0 ]]
    local request ack
    request="$(printf '%s\n' "$output" | sed -n '1p')"
    ack="$(printf '%s\n' "$output" | sed -n '2p')"
    [[ -f "$request" ]]
    [[ "$(stat -f '%Lp' "$request")" == "600" ]]
    [[ "$(stat -f '%Lp' "$HUB_TERMINAL_REQUEST_DIR")" == "700" ]]
    [[ ! -e "$ack" ]]
    run bash -c "
        export HOME='$HOME' HUB_HOME='$HOME' HUB_CONFIG_DIR='$HUB_CONFIG_DIR' HUB_RUNTIME_DIR='$HUB_RUNTIME_DIR' HUB_TERMINAL_REQUEST_DIR='$HUB_TERMINAL_REQUEST_DIR'
        source '$HUB' >/dev/null 2>&1
        TERMINAL_COMMAND_REQUEST_PATH='$request' TERMINAL_COMMAND_ACK_PATH='$ack' _terminal_command_request_cleanup
    "
    [[ "$status" -eq 0 ]]
    [[ ! -e "$request" ]]
    [[ ! -e "$ack" ]]
}

@test "runner prints a short nonzero status and then starts the interactive shell" {
    local executable="$TERMINAL_TEST_DIR/fails"
    local shell_stub="$TERMINAL_TEST_DIR/shell"
    local shell_record="$TERMINAL_TEST_DIR/shell-record"
    cat > "$executable" <<'SH'
#!/bin/sh
exit 17
SH
    chmod +x "$executable"
    cat > "$shell_stub" <<'SH'
#!/bin/sh
printf '%s\n' "$*" > "$SHELL_RECORD"
exit 0
SH
    chmod +x "$shell_stub"
    local request="$HUB_TERMINAL_REQUEST_DIR/request.fail"
    local ack="$HUB_TERMINAL_REQUEST_DIR/request.fail.ack"
    printf '%s\0%s\0' "$TERMINAL_TEST_DIR" "$executable" > "$request"
    chmod 600 "$request"

    run env HOME="$TERMINAL_TEST_DIR/home" SHELL="$shell_stub" SHELL_RECORD="$shell_record" \
        "$RUNNER" "$request" "$ack"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"17"* ]]
    [[ "$(cat "$shell_record")" == "-il" ]]
    [[ "$(cat "$ack")" == "READY" ]]
}


@test "runner rejects a replaced symlink request without touching the target" {
    local target="$HUB_TERMINAL_REQUEST_DIR/real-payload"
    local request="$HUB_TERMINAL_REQUEST_DIR/request.replaced"
    local ack="$request.ack"
    printf '%s\0%s\0' "$TERMINAL_TEST_DIR" /bin/true > "$target"
    chmod 600 "$target"
    ln -s "$target" "$request"

    run env HOME="$TERMINAL_TEST_DIR/home" SHELL=/bin/sh "$RUNNER" "$request" "$ack"
    [[ "$status" -ne 0 ]]
    [[ "$(cat "$ack")" == ERROR* ]]
    [[ -L "$request" ]]
    [[ -f "$target" ]]
}
