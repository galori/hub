#!/usr/bin/env bats
# Unit tests for floating-window nudge dispatch.

load helpers/stubs

REPO_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
HUB_SCRIPT="$REPO_DIR/scripts/hub"

setup() {
    setup_stubs
    export STUB_CALLS="$HOME/stub_calls"

    cat > "$STUB_BIN/aerospace" <<'SH'
#!/usr/bin/env bash
case "$*" in
    "list-windows --all --format %{window-id}|%{app-pid}") printf '42|1234\n' ;;
    *) exit 0 ;;
esac
SH
    chmod +x "$STUB_BIN/aerospace"

    cat > "$HOME/.config/hub/float_nudge" <<'SH'
#!/usr/bin/env bash
echo "$*" >> "$STUB_CALLS"
SH
    chmod +x "$HOME/.config/hub/float_nudge"

    echo 70 > "$HOME/.config/hub/hub_bar_outer_top"
}

teardown() {
    teardown_stubs
}

@test "nudge_float_window resolves PID and retries nudge" {
    bash -c "
        export HOME='$HOME'
        export PATH='$STUB_BIN':\"\$PATH\"
        export STUB_CALLS='$STUB_CALLS'
        source '$HUB_SCRIPT' >/dev/null 2>&1
        nudge_float_window 42
        wait
    "

    [[ "$(wc -l < "$STUB_CALLS")" -eq 5 ]]
    [[ "$(sort -u "$STUB_CALLS")" == "1234 85" ]]
}
