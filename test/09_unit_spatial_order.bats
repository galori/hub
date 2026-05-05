#!/usr/bin/env bats
# Unit tests for the spatial_order_ltr bash helper in scripts/hub.
# Uses a stubbed SPATIAL_ORDER_BIN and stubbed aerospace so no real windows
# or CGWindowList access is needed.

load helpers/stubs
load helpers/fixtures

REPO_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
HUB_SCRIPT="$REPO_DIR/scripts/hub"

setup() {
    setup_stubs
    export STUB_CALLS="$HOME/stub_calls"
    export WORKSPACES_FILE="$HOME/.config/hub/workspaces.json"
    seed_workspaces "1:Main:/tmp/main"
}

teardown() {
    teardown_stubs
}

# Run spatial_order_ltr via a wrapper script to avoid bash -c quoting pitfalls.
run_spatial_order_ltr() {
    local ws_id="$1"
    local runner="$HOME/runner_sol.sh"
    {
        echo "#!/usr/bin/env bash"
        echo "export HOME='$HOME'"
        echo "export SPATIAL_ORDER_BIN='$HOME/.config/hub/spatial_order'"
        echo "export PATH='$STUB_BIN':\"\$PATH\""
        echo "source '$HUB_SCRIPT' >/dev/null 2>&1"
        echo "spatial_order_ltr '$ws_id'"
    } > "$runner"
    chmod +x "$runner"
    bash "$runner" 2>/dev/null
}

@test "spatial_order_ltr returns binary output for workspace windows" {
    mock_aerospace_windows 1 100 200 300
    mock_spatial_order 100 200 300
    result="$(run_spatial_order_ltr 1)"
    [[ "$result" == $'100\n200\n300' ]]
}

@test "spatial_order_ltr passes all window IDs to the binary" {
    mock_aerospace_windows 1 42 99 7
    # Use a recording spatial_order stub to verify the IDs forwarded
    cat > "$HOME/.config/hub/spatial_order" <<'SH'
#!/usr/bin/env bash
echo "$*" > "$HOME/spatial_order_args"
printf '%s\n' "$@"
SH
    chmod +x "$HOME/.config/hub/spatial_order"
    run_spatial_order_ltr 1 >/dev/null
    args="$(cat "$HOME/spatial_order_args" 2>/dev/null)"
    [[ "$args" == *"42"* ]]
    [[ "$args" == *"99"* ]]
    [[ "$args" == *"7"* ]]
}

@test "spatial_order_ltr returns empty for workspace with no windows" {
    mock_aerospace_windows 1  # no wids
    mock_spatial_order        # nothing to return
    result="$(run_spatial_order_ltr 1)"
    [[ -z "$result" ]]
}

@test "spatial_order_ltr returns spatial order from binary (not list-windows order)" {
    # aerospace returns [300, 100, 200] (not spatial), binary returns [100, 200, 300]
    mock_aerospace_windows 1 300 100 200
    mock_spatial_order 100 200 300
    result="$(run_spatial_order_ltr 1)"
    first="$(echo "$result" | head -1)"
    [[ "$first" == "100" ]]
}
