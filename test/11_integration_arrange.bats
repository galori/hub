#!/usr/bin/env bats
# Integration tests for arrange_after_open and arrange_workspace_windows.
# Uses recording aerospace stubs and a scripted spatial_order stub to assert
# on the exact command sequence issued to AeroSpace — no real windows needed.

load helpers/stubs
load helpers/fixtures

REPO_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
HUB_SCRIPT="$REPO_DIR/scripts/hub"

setup() {
    setup_stubs
    export STUB_CALLS="$HOME/stub_calls"
    export WORKSPACES_FILE="$HOME/.config/hub/workspaces.json"
    seed_workspaces "7:Test:/tmp/test"
    mkdir -p "$HOME/.config/sketchybar/plugins"
    printf '#!/usr/bin/env bash\nexit 0\n' > "$HOME/.config/sketchybar/plugins/app_launcher.sh"
    chmod +x "$HOME/.config/sketchybar/plugins/app_launcher.sh"
}

teardown() {
    teardown_stubs
}

# Install an aerospace stub that records every call and returns a fixed
# set of window IDs for the given workspace.
setup_aerospace_stub() {
    local ws_id="$1"; shift
    local wid_lines
    wid_lines="$(printf '%s\n' "$@")"
    cat > "$STUB_BIN/aerospace" <<STUB
#!/usr/bin/env bash
echo "aerospace \$*" >> "\$STUB_CALLS"
case "\$*" in
    "list-windows --workspace $ws_id --format %{window-id}") printf '%s\n' $(printf '"%s" ' "$@") ;;
    *) exit 0 ;;
esac
STUB
    chmod +x "$STUB_BIN/aerospace"
}

# Write a wrapper script that sources hub and calls the given function.
# This avoids quoting issues with bash -c "..." for complex argument lists.
make_runner() {
    local func="$1"; shift
    local runner="$HOME/runner.sh"
    {
        echo "#!/usr/bin/env bash"
        echo "export HOME='$HOME'"
        echo "export SPATIAL_ORDER_BIN='$HOME/.config/hub/spatial_order'"
        echo "export STUB_CALLS='$STUB_CALLS'"
        echo "export WORKSPACES_FILE='$WORKSPACES_FILE'"
        echo "export PATH='$STUB_BIN':\"\$PATH\""
        echo "source '$HUB_SCRIPT' >/dev/null 2>&1"
        printf '%s' "$func"
        for arg in "$@"; do printf ' %q' "$arg"; done
        echo
    } > "$runner"
    chmod +x "$runner"
    echo "$runner"
}

run_arrange_after_open() {
    local ws_id="$1"; shift
    local list_wids=() spatial_wids=()
    local in_spatial=false
    for arg in "$@"; do
        [[ "$arg" == "--" ]] && { in_spatial=true; continue; }
        $in_spatial && spatial_wids+=("$arg") || list_wids+=("$arg")
    done
    setup_aerospace_stub "$ws_id" "${list_wids[@]}"
    mock_spatial_order "${spatial_wids[@]}"
    local runner
    runner="$(make_runner arrange_after_open "$ws_id")"
    bash "$runner" 2>/dev/null
}

run_arrange_workspace_windows() {
    local ws_id="$1"; shift
    local wids=() spatial_wids=()
    local in_spatial=false
    for arg in "$@"; do
        [[ "$arg" == "--" ]] && { in_spatial=true; continue; }
        $in_spatial && spatial_wids+=("$arg") || wids+=("$arg")
    done
    # arrange_workspace_windows calls spatial_order_ltr internally, which calls
    # list-windows again. Give the stub the spatial order so it returns it directly.
    setup_aerospace_stub "$ws_id" "${spatial_wids[@]}"
    mock_spatial_order "${spatial_wids[@]}"
    local runner
    runner="$(make_runner arrange_workspace_windows "$ws_id" "${wids[@]}")"
    bash "$runner" 2>/dev/null
}

# ---------------------------------------------------------------------------
# arrange_after_open: out-of-range cases
# ---------------------------------------------------------------------------

@test "arrange_after_open: n=1 does nothing" {
    run_arrange_after_open 7 100 -- 100
    assert_not_called "flatten-workspace-tree"
}

@test "arrange_after_open: n=5 does nothing" {
    run_arrange_after_open 7 100 200 300 400 500 -- 100 200 300 400 500
    assert_not_called "flatten-workspace-tree"
}

# ---------------------------------------------------------------------------
# arrange_after_open: 2 windows
# ---------------------------------------------------------------------------

@test "arrange_after_open: n=2 flattens and sets h_tiles" {
    run_arrange_after_open 7 100 200 -- 100 200
    assert_called "flatten-workspace-tree"
    assert_called "layout h_tiles"
    assert_not_called "join-with"
}

@test "arrange_after_open: n=2 newest already rightmost — no move right" {
    run_arrange_after_open 7 100 200 -- 100 200
    assert_not_called "move right"
}

@test "arrange_after_open: n=2 newest not rightmost — moves right once" {
    run_arrange_after_open 7 200 100 -- 200 100
    count="$(count_calls "move right")"
    [[ "$count" -eq 1 ]]
}

# ---------------------------------------------------------------------------
# arrange_after_open: 3 windows
# ---------------------------------------------------------------------------

@test "arrange_after_open: n=3 newest rightmost — no move right, calls join-with left" {
    run_arrange_after_open 7 100 200 300 -- 100 200 300
    assert_not_called "move right"
    assert_called "join-with left"
    assert_called "layout v_tiles"
}

@test "arrange_after_open: n=3 newest in middle — moves right 1 time" {
    # 300 is newest, spatial index 1 of [100, 300, 200] → needs 1 move
    run_arrange_after_open 7 100 300 200 -- 100 300 200
    count="$(count_calls "move right")"
    [[ "$count" -eq 1 ]]
}

@test "arrange_after_open: n=3 newest at left — moves right 2 times" {
    # 300 is newest at spatial index 0 of [300, 100, 200] → needs 2 moves
    run_arrange_after_open 7 300 100 200 -- 300 100 200
    count="$(count_calls "move right")"
    [[ "$count" -eq 2 ]]
}

# ---------------------------------------------------------------------------
# arrange_workspace_windows: correct join-with targets
# ---------------------------------------------------------------------------

@test "arrange_workspace_windows: n=2 sets h_tiles, no join-with" {
    run_arrange_workspace_windows 7 100 200 -- 100 200
    assert_called "layout h_tiles"
    assert_not_called "join-with"
}

@test "arrange_workspace_windows: n=3 calls join-with left once" {
    run_arrange_workspace_windows 7 100 200 300 -- 100 200 300
    count="$(count_calls "join-with left")"
    [[ "$count" -eq 1 ]]
}

@test "arrange_workspace_windows: n=3 focuses rightmost window before join-with" {
    run_arrange_workspace_windows 7 100 200 300 -- 100 200 300
    assert_called "focus --window-id 300"
}

@test "arrange_workspace_windows: n=4 calls join-with left twice" {
    run_arrange_workspace_windows 7 100 200 300 400 -- 100 200 300 400
    count="$(count_calls "join-with left")"
    [[ "$count" -eq 2 ]]
}

@test "arrange_workspace_windows: n=4 focuses W2 and W4 for two-column layout" {
    run_arrange_workspace_windows 7 100 200 300 400 -- 100 200 300 400
    assert_called "focus --window-id 200"
    assert_called "focus --window-id 400"
}

@test "arrange_workspace_windows: n=4 sets layout v_tiles twice" {
    run_arrange_workspace_windows 7 100 200 300 400 -- 100 200 300 400
    count="$(count_calls "layout v_tiles")"
    [[ "$count" -eq 2 ]]
}

@test "arrange_workspace_windows: final focus returns to leftmost window" {
    run_arrange_workspace_windows 7 100 200 300 -- 100 200 300
    last_focus="$(grep "focus --window-id" "$STUB_CALLS" | tail -1)"
    [[ "$last_focus" == *"100"* ]]
}
