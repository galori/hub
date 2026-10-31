#!/usr/bin/env bats
# Multi-monitor behavior: new workspaces open on the focused monitor and are
# pinned there, next/prev cycle within the focused monitor, and `hub monitor`
# moves windows/workspaces between monitors.

load helpers/stubs
load helpers/fixtures

REPO_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
HUB_SCRIPT="$REPO_DIR/scripts/hub"

setup() {
    setup_stubs
    export WORKSPACES_FILE="$HOME/.config/hub/workspaces.json"
    export RECENT_REPOS_FILE="$HOME/.config/hub/recent_repos.json"
    export STUB_CALLS="$HOME/stub_calls"
    : > "$STUB_CALLS"
}

teardown() {
    teardown_stubs
}

# mock_monitors <focused_id> <id:name:ws,ws,...>...
# Stateless aerospace stub describing which workspaces live on which monitor.
# The focused workspace is the first one listed on the focused monitor.
# Every call is recorded in $STUB_CALLS.
mock_monitors() {
    local focused="$1"; shift
    local mon_lines="" ws_cases="" focused_line="" focused_ws=""
    local spec id name list
    for spec in "$@"; do
        IFS=':' read -r id name list <<< "$spec"
        mon_lines+="$id|$name"$'\n'
        ws_cases+="    \"list-workspaces --monitor $id\") printf '%s\\n' ${list//,/ } ;;"$'\n'
        if [[ "$id" == "$focused" ]]; then
            focused_line="$id|$name"
            focused_ws="${list%%,*}"
            ws_cases+="    \"list-workspaces --monitor focused\") printf '%s\\n' ${list//,/ } ;;"$'\n'
        fi
    done
    cat > "$STUB_BIN/aerospace" <<SH
#!/usr/bin/env bash
echo "aerospace \$*" >> "$STUB_CALLS"
case "\$*" in
    "list-monitors --format %{monitor-id}|%{monitor-name}") printf '%s' "$mon_lines" ;;
    "list-monitors --focused --format %{monitor-id}|%{monitor-name}") echo "$focused_line" ;;
    "list-workspaces --focused") echo "$focused_ws" ;;
$ws_cases    *) exit 0 ;;
esac
SH
    chmod +x "$STUB_BIN/aerospace"
}

hub_fn() {
    bash -c '
        export HOME="$1" WORKSPACES_FILE="$2" RECENT_REPOS_FILE="$3"
        source "$4" >/dev/null 2>&1
        "${@:5}"
    ' _ "$HOME" "$WORKSPACES_FILE" "$RECENT_REPOS_FILE" "$HUB_SCRIPT" "$@"
}

create_scratch() {
    hub_fn _create_workspace "$1" "$HOME" "" "$2" "" "" "" true
}

# ── hub new ──────────────────────────────────────────────────────────────────

@test "new workspace moves to the focused secondary monitor before switching" {
    mock_monitors 2 "1:Built-in:1,2,A,Z" "2:DELL U2720Q:3"
    run create_scratch scratch A
    [[ "$status" -eq 0 ]]
    assert_called "aerospace move-workspace-to-monitor --workspace A 2"
    local move_line switch_line
    move_line="$(grep -n "move-workspace-to-monitor --workspace A" "$STUB_CALLS" | cut -d: -f1)"
    switch_line="$(grep -n "^aerospace workspace A$" "$STUB_CALLS" | cut -d: -f1)"
    [[ "$move_line" -lt "$switch_line" ]]
}

@test "new workspace records the monitor name it was created on" {
    mock_monitors 2 "1:Built-in:1,A,Z" "2:DELL U2720Q:3"
    run create_scratch scratch A
    [[ "$status" -eq 0 ]]
    run jq -r '.[] | select(.workspace_id == "A") | .monitor' "$WORKSPACES_FILE"
    [[ "$output" == "DELL U2720Q" ]]
}

@test "new workspace already on the focused monitor is not moved" {
    mock_monitors 1 "1:Built-in:1,A,Z" "2:DELL U2720Q:3"
    run create_scratch scratch A
    [[ "$status" -eq 0 ]]
    assert_not_called "move-workspace-to-monitor"
}

@test "new workspace with a single monitor does not move or record a monitor" {
    mock_monitors 1 "1:Built-in:1,A,Z"
    run create_scratch scratch A
    [[ "$status" -eq 0 ]]
    assert_not_called "move-workspace-to-monitor"
    run jq -r '.[] | select(.workspace_id == "A") | has("monitor")' "$WORKSPACES_FILE"
    [[ "$output" == "false" ]]
}

# ── hub next / prev ──────────────────────────────────────────────────────────

@test "next cycles only through workspaces on the focused monitor" {
    seed_workspaces "1:One:/tmp/1" "3:Three:/tmp/3" "4:Four:/tmp/4" "9:Nine:/tmp/9"
    mock_monitors 2 "1:Built-in:1,4" "2:DELL:3,9"
    run hub_fn cmd_next
    [[ "$status" -eq 0 ]]
    assert_called "^aerospace workspace 9$"
    assert_not_called "^aerospace workspace 4$"
}

@test "next wraps around within the focused monitor" {
    seed_workspaces "1:One:/tmp/1" "2:Two:/tmp/2" "3:Three:/tmp/3" "4:Four:/tmp/4"
    mock_monitors 2 "1:Built-in:1,2" "2:DELL:4,3"
    run hub_fn cmd_next
    [[ "$status" -eq 0 ]]
    assert_called "^aerospace workspace 3$"
    assert_not_called "^aerospace workspace 1$"
}

@test "next with a single monitor cycles through all workspaces" {
    seed_workspaces "1:One:/tmp/1" "2:Two:/tmp/2"
    mock_monitors 1 "1:Built-in:2,1"
    run hub_fn cmd_next
    [[ "$status" -eq 0 ]]
    assert_called "^aerospace workspace 1$"
}

# ── hub remove ───────────────────────────────────────────────────────────────

@test "after remove, focus stays on a workspace of the same monitor" {
    seed_workspaces "1:One:/tmp/1" "3:Three:/tmp/3" "9:Nine:/tmp/9" "Z:General:/tmp:"
    mock_monitors 2 "1:Built-in:1,Z" "2:DELL:3,9"
    run hub_fn _workspace_after_remove 3
    [[ "$output" == "9" ]]
}

@test "after remove with a single monitor, focus goes to General" {
    seed_workspaces "1:One:/tmp/1" "Z:General:/tmp:"
    mock_monitors 1 "1:Built-in:1,Z"
    run hub_fn _workspace_after_remove 1
    [[ "$output" == "Z" ]]
}

@test "after remove with no other workspace on the monitor, focus does not move" {
    seed_workspaces "1:One:/tmp/1" "3:Three:/tmp/3" "Z:General:/tmp:"
    mock_monitors 2 "1:Built-in:1,Z" "2:DELL:3"
    run hub_fn _workspace_after_remove 3
    [[ "$output" == "" ]]
}

# ── hub monitor ──────────────────────────────────────────────────────────────

@test "monitor move-window moves the focused window to the next monitor" {
    mock_monitors 1 "1:Built-in:1" "2:DELL:3"
    run hub_fn cmd_monitor move-window
    [[ "$status" -eq 0 ]]
    assert_called "aerospace move-node-to-monitor --focus-follows-window --wrap-around next"
}

@test "monitor move-window accepts prev" {
    mock_monitors 1 "1:Built-in:1" "2:DELL:3"
    run hub_fn cmd_monitor move-window prev
    [[ "$status" -eq 0 ]]
    assert_called "aerospace move-node-to-monitor --focus-follows-window --wrap-around prev"
}

@test "monitor rejects an unknown direction" {
    mock_monitors 1 "1:Built-in:1" "2:DELL:3"
    run hub_fn cmd_monitor move-window sideways
    [[ "$status" -ne 0 ]]
    assert_not_called "move-node-to-monitor"
}

@test "monitor move-workspace moves it and records the new monitor" {
    seed_workspaces "1:One:/tmp/1"
    # The stub reports the state after the move: workspace 1 is on monitor 2.
    mock_monitors 2 "1:Built-in:Z" "2:DELL:1,3"
    run hub_fn cmd_monitor move-workspace
    [[ "$status" -eq 0 ]]
    assert_called "aerospace move-workspace-to-monitor --wrap-around next"
    run jq -r '.[] | select(.workspace_id == "1") | .monitor' "$WORKSPACES_FILE"
    [[ "$output" == "DELL" ]]
}

@test "monitor restore moves pinned workspaces back to their monitor" {
    cat > "$WORKSPACES_FILE" <<'JSON'
[
  {"name":"One","path":"/tmp/1","root_repo":"","workspace_id":"1","monitor":"DELL"},
  {"name":"Two","path":"/tmp/2","root_repo":"","workspace_id":"2","monitor":"Built-in"},
  {"name":"Three","path":"/tmp/3","root_repo":"","workspace_id":"3","monitor":"Unplugged"},
  {"name":"Four","path":"/tmp/4","root_repo":"","workspace_id":"4"}
]
JSON
    mock_monitors 1 "1:Built-in:1,2,3,4" "2:DELL:5"
    run hub_fn cmd_monitor restore
    [[ "$status" -eq 0 ]]
    assert_called "aerospace move-workspace-to-monitor --workspace 1 2"
    assert_not_called "move-workspace-to-monitor --workspace 2"
    assert_not_called "move-workspace-to-monitor --workspace 3"
    assert_not_called "move-workspace-to-monitor --workspace 4"
}

# ── AeroSpace config ─────────────────────────────────────────────────────────

@test "aerospace config binds ctrl-alt-m to move the window to the next monitor" {
    grep -q "^ *ctrl-alt-m = 'move-node-to-monitor --focus-follows-window --wrap-around next'" \
        "$REPO_DIR/config/aerospace.toml"
}

@test "aerospace config routes alt-shift-tab through hub so the monitor is recorded" {
    grep -q "^ *alt-shift-tab = 'exec-and-forget __HUB_SCRIPT__ monitor move-workspace next'" \
        "$REPO_DIR/config/aerospace.toml"
}
