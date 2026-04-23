# Shared stub setup for hub tests.
# Source this file in bats setup() to get a fully-isolated environment.

setup_stubs() {
    # Isolated config dir so tests never touch real ~/.config/hub
    export HUB_TEST_DIR
    HUB_TEST_DIR="$(mktemp -d)"
    export HOME="$HUB_TEST_DIR"
    mkdir -p "$HOME/.config/hub"

    # Stub bin dir (prepended to PATH so stubs shadow real tools)
    export STUB_BIN="$HUB_TEST_DIR/stubs"
    mkdir -p "$STUB_BIN"
    export PATH="$STUB_BIN:$PATH"

    # Install no-op stubs for all external tools hub calls
    make_stub aerospace   ""  0
    make_stub sketchybar  ""  0
    make_stub borders     ""  0
    make_stub jq          ""  0  # real jq still in PATH after stubs dir; overridden only when needed
    make_stub osascript   ""  0
    make_stub defaults    ""  0
    make_stub killall     ""  0
    make_stub open        ""  0
    make_stub pgrep       ""  1  # default: "not running"
    make_stub pkill       ""  0
    make_stub swiftc      ""  0
    make_stub brew        ""  0
    make_stub git         ""  0

    # Use real jq (remove the stub so the real one is used for workspace JSON)
    rm -f "$STUB_BIN/jq"
}

teardown_stubs() {
    [[ -n "${HUB_TEST_DIR:-}" ]] && rm -rf "$HUB_TEST_DIR"
}

# make_stub <name> <stdout> <exit_code>
make_stub() {
    local name="$1" output="$2" code="$3"
    cat > "$STUB_BIN/$name" <<STUB
#!/usr/bin/env bash
${output:+echo "$output"}
exit $code
STUB
    chmod +x "$STUB_BIN/$name"
}

# make_stub_recording <name>
# Creates a stub that appends "name arg1 arg2 ..." to $STUB_CALLS file
make_stub_recording() {
    local name="$1" output="${2:-}" code="${3:-0}"
    cat > "$STUB_BIN/$name" <<STUB
#!/usr/bin/env bash
echo "$name \$*" >> "\${STUB_CALLS:-/tmp/stub_calls_$$}"
${output:+echo "$output"}
exit $code
STUB
    chmod +x "$STUB_BIN/$name"
}

# Source the hub script with functions only (skip the main dispatch at bottom)
# by setting BATS_HUB_SOURCED so callers can re-source selectively.
load_hub_functions() {
    local script="$BATS_TEST_DIRNAME/../scripts/hub"
    # We source the script but need to prevent the main case statement from
    # running. We do this by pre-setting $1 to a no-op sentinel that falls
    # through to the empty/help branch without side effects, then re-exporting
    # just the functions we need. The cleanest approach is to extract and eval
    # the function definitions only.
    #
    # Strategy: source with `set --` to clear positional params, then the
    # `case "$command"` at the bottom hits `''` → print_usage (harmless to
    # stdout in tests, which we redirect).
    (
        set --
        # shellcheck disable=SC1090
        source "$script" 2>/dev/null
    )
    # Actually we need the functions in the current shell. Source directly
    # with empty $1 so the bottom case hits '' → print_usage.
    # Suppress output.
    # shellcheck disable=SC1090
    source "$script" > /dev/null 2>&1 || true
}
