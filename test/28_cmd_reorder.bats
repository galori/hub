#!/usr/bin/env bats
# `hub reorder`: change a workspace's slot so it lands where the user drops it.

load helpers/stubs
load helpers/fixtures

REPO_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
HUB_SCRIPT="$REPO_DIR/scripts/hub"

setup() {
    setup_stubs
    export WORKSPACES_FILE="$HOME/.config/hub/workspaces.json"
    export RECENT_REPOS_FILE="$HOME/.config/hub/recent_repos.json"
    export STUB_CALLS="$HOME/stub_calls"
    export HUB_CLAUDE_STATE_DIR="$HOME/claude-state"
    mkdir -p "$HUB_CLAUDE_STATE_DIR"
    : > "$STUB_CALLS"
    # spatial_order stub: keep the given window order
    export SPATIAL_ORDER_BIN="$HOME/spatial_order"
    printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$@"\n' > "$SPATIAL_ORDER_BIN"
    chmod +x "$SPATIAL_ORDER_BIN"
}

teardown() {
    teardown_stubs
}

hub_fn() {
    bash -c '
        export HOME="$1" WORKSPACES_FILE="$2" RECENT_REPOS_FILE="$3"
        source "$4" >/dev/null 2>&1
        "${@:5}"
    ' _ "$HOME" "$WORKSPACES_FILE" "$RECENT_REPOS_FILE" "$HUB_SCRIPT" "$@"
}

# mock_aero <focused> <occupied ids...>: records calls; lists given workspaces as non-empty.
# Windows are named w<ID> and live on workspace <ID>.
mock_aero() {
    local focused="$1"; shift
    local occ="$*"
    cat > "$STUB_BIN/aerospace" <<SH
#!/usr/bin/env bash
echo "aerospace \$*" >> "$STUB_CALLS"
case "\$*" in
    "list-workspaces --focused") echo "$focused" ;;
    "list-workspaces --monitor all --empty no") printf '%s\n' $occ ;;
    list-windows\ --workspace\ *) ws="\$3"; case " $occ " in *" \$ws "*) echo "w\$ws" ;; esac ;;
    "list-monitors --format"*) echo "1|Built-in" ;;
esac
exit 0
SH
    chmod +x "$STUB_BIN/aerospace"
}

ids_by_name() { jq -r 'map("\(.workspace_id)=\(.name)") | join(",")' "$WORKSPACES_FILE"; }

# ── _reorder_plan (pure) ─────────────────────────────────────────────────────

plan() { hub_fn _reorder_plan "$1" "$2" "$3"; }

@test "plan: moving right shifts neighbours up to the first free slot" {
    run plan 2 4 $'1\n2\n3\n4\n5\n6\n8'
    [[ "$status" -eq 0 ]]
    [[ "$output" == $'6 7\n5 6\n2 5' ]]
}

@test "plan: moving left shifts the slots in between up" {
    run plan 6 2 $'1\n2\n3\n4\n5\n6'
    [[ "$output" == $'5 6\n4 5\n3 4\n6 3' ]]
}

@test "plan: a free target slot needs no shift" {
    run plan 2 4 $'1\n2\n4'
    [[ "$output" == "2 5" ]]
}

@test "plan: dropping in place is a no-op" {
    run plan 2 1 $'1\n2\n3'
    [[ "$status" -eq 0 && -z "$output" ]]
    run plan 2 2 $'1\n2\n3'
    [[ "$status" -eq 0 && -z "$output" ]]
}

@test "plan: empty AFTER means the first slot" {
    run plan 3 "" $'1\n2\n3'
    [[ "$output" == $'2 3\n1 2\n3 1' ]]
}

@test "plan: skips H, J, K, L and never touches Z" {
    run plan 1 G $'1\nG\nI\nZ'
    [[ "$output" == $'I M\n1 I' ]]
    [[ "$output" != *Z* ]]
}

@test "plan: dropping after the last slot fails and never uses Z" {
    used="$(printf '%s\n' 1 2 3 4 5 6 7 8 9 A B C D E F G I M N O P Q R S T U V W X Y Z)"
    run plan 1 Y "$used"
    [[ "$status" -eq 1 ]]
}

# ── hub reorder ──────────────────────────────────────────────────────────────

@test "reorder: example from the request renames IDs and moves windows" {
    seed_workspaces "1:a:/tmp/1" "2:Kiro:/tmp/2" "3:b:/tmp/3" "4:dgsu:/tmp/4" "5:toka:/tmp/5" "6:c:/tmp/6"
    mock_aero 2 1 2 3 4 5 6
    run hub_fn cmd_reorder 2 --after 4
    [[ "$status" -eq 0 ]]
    [[ "$(ids_by_name)" == "1=a,5=Kiro,3=b,4=dgsu,6=toka,7=c" ]]
    run grep -c "move-node-to-workspace --window-id w6 7" "$STUB_CALLS"
    [[ "$output" == "1" ]]
    run grep -c "move-node-to-workspace --window-id w5 6" "$STUB_CALLS"
    [[ "$output" == "1" ]]
}

@test "reorder: focus follows the focused workspace to its new ID" {
    seed_workspaces "1:a:/tmp/1" "2:Kiro:/tmp/2" "3:b:/tmp/3" "4:c:/tmp/4"
    mock_aero 2 1 2 3 4
    run hub_fn cmd_reorder 2 --after 4
    [[ "$status" -eq 0 ]]
    grep -q "^aerospace workspace 5$" "$STUB_CALLS"
}

@test "reorder: --before lands in the slot of the target" {
    seed_workspaces "1:a:/tmp/1" "2:b:/tmp/2" "3:c:/tmp/3"
    mock_aero 1 1 2 3
    run hub_fn cmd_reorder 3 --before 2
    [[ "$status" -eq 0 ]]
    [[ "$(ids_by_name)" == "1=a,3=b,2=c" ]]
}

@test "reorder: --first puts the workspace in slot 1" {
    seed_workspaces "1:a:/tmp/1" "2:b:/tmp/2" "3:c:/tmp/3"
    mock_aero 1 1 2 3
    run hub_fn cmd_reorder 3 --first
    [[ "$status" -eq 0 ]]
    [[ "$(ids_by_name)" == "2=a,3=b,1=c" ]]
}

@test "reorder: Claude status files follow the rename" {
    seed_workspaces "1:a:/tmp/1" "2:b:/tmp/2" "3:c:/tmp/3"
    mock_aero 1 1 2 3
    touch "$HUB_CLAUDE_STATE_DIR/hub_claude_alert_1" "$HUB_CLAUDE_STATE_DIR/hub_claude_active_3"
    run hub_fn cmd_reorder 1 --after 2
    [[ "$status" -eq 0 ]]
    [[ -e "$HUB_CLAUDE_STATE_DIR/hub_claude_alert_3" ]]
    [[ -e "$HUB_CLAUDE_STATE_DIR/hub_claude_active_4" ]]
    [[ ! -e "$HUB_CLAUDE_STATE_DIR/hub_claude_alert_1" ]]
    [[ ! -e "$HUB_CLAUDE_STATE_DIR/hub_claude_active_3" ]]
}

@test "reorder: a full bar fails and leaves workspaces.json unchanged" {
    local specs=() id
    for id in 1 2 3 4 5 6 7 8 9 A B C D E F G I M N O P Q R S T U V W X Y; do
        specs+=("$id:ws$id:/tmp/$id")
    done
    seed_workspaces "${specs[@]}" "Z:General:/tmp/Z"
    mock_aero 1 1
    cp "$WORKSPACES_FILE" "$HOME/before.json"
    run hub_fn cmd_reorder 1 --after Y
    [[ "$status" -ne 0 ]]
    run cmp "$WORKSPACES_FILE" "$HOME/before.json"
    [[ "$status" -eq 0 ]]
}

@test "reorder: an unknown workspace fails" {
    seed_workspaces "1:a:/tmp/1"
    mock_aero 1 1
    run hub_fn cmd_reorder 5 --first
    [[ "$status" -ne 0 ]]
}

@test "reorder: --monitor records the monitor and moves the workspace" {
    seed_workspaces "1:a:/tmp/1" "2:b:/tmp/2"
    cat > "$STUB_BIN/aerospace" <<SH
#!/usr/bin/env bash
echo "aerospace \$*" >> "$STUB_CALLS"
case "\$*" in
    "list-workspaces --focused") echo 1 ;;
    "list-workspaces --monitor all --empty no") printf '1\n2\n' ;;
    "list-monitors --format"*) printf '1|Built-in\n2|DELL\n' ;;
    "list-workspaces --monitor 1") printf '1\n2\n' ;;
esac
exit 0
SH
    chmod +x "$STUB_BIN/aerospace"
    run hub_fn cmd_reorder 2 --after 2 --monitor DELL
    [[ "$status" -eq 0 ]]
    run jq -r '.[] | select(.name == "b") | .monitor' "$WORKSPACES_FILE"
    [[ "$output" == "DELL" ]]
    grep -q "move-workspace-to-monitor --workspace 2 2" "$STUB_CALLS"
}

# ── notify hook after a reorder ──────────────────────────────────────────────

run_notify() {
    # $1 = env assignments, cwd in $2
    echo "{\"cwd\": \"$2\"}" | env HOME="$HOME" HUB_CLAUDE_STATE_DIR="$HUB_CLAUDE_STATE_DIR" \
        HUB_CLAUDE_NOTIFY_SOUND=0 $1 bash "$REPO_DIR/scripts/hooks/notify.sh"
}

@test "notify hook: HUB_WORKSPACE_UID finds the workspace after its ID changed" {
    mkdir -p "$HOME/.config/hub"
    echo '[{"name":"Kiro","path":"/p/kiro","workspace_id":"5","uid":"u-kiro"},{"name":"toka","path":"/p/toka","workspace_id":"2","uid":"u-toka"}]' > "$HOME/.config/hub/workspaces.json"
    # Terminal started when Kiro was workspace 2; cwd is outside every workspace.
    run run_notify "HUB_WORKSPACE_ID=2 HUB_WORKSPACE_UID=u-kiro" "/elsewhere"
    [[ -e "$HUB_CLAUDE_STATE_DIR/hub_claude_alert_5" ]]
    [[ ! -e "$HUB_CLAUDE_STATE_DIR/hub_claude_alert_2" ]]
}

@test "notify hook: a stale HUB_WORKSPACE_ID without a matching path falls back to cwd" {
    mkdir -p "$HOME/.config/hub"
    echo '[{"name":"Kiro","path":"/p/kiro","workspace_id":"5","uid":"u-kiro"},{"name":"toka","path":"/p/toka","workspace_id":"2","uid":"u-toka"}]' > "$HOME/.config/hub/workspaces.json"
    run run_notify "HUB_WORKSPACE_ID=2" "/p/kiro/src"
    [[ -e "$HUB_CLAUDE_STATE_DIR/hub_claude_alert_5" ]]
    [[ ! -e "$HUB_CLAUDE_STATE_DIR/hub_claude_alert_2" ]]
}

@test "notify hook: legacy entries without uid still match by HUB_WORKSPACE_ID" {
    mkdir -p "$HOME/.config/hub"
    echo '[{"name":"Kiro","path":"/p/kiro","workspace_id":"2"}]' > "$HOME/.config/hub/workspaces.json"
    run run_notify "HUB_WORKSPACE_ID=2" "/elsewhere"
    [[ -e "$HUB_CLAUDE_STATE_DIR/hub_claude_alert_2" ]]
}

@test "hub new stores a uid and the prompt wrapper exports it" {
    mkdir -p "$HOME/.config/hub"
    echo '[]' > "$HOME/.config/hub/workspaces.json"
    export WORKSPACES_FILE="$HOME/.config/hub/workspaces.json"
    run hub_fn _create_workspace scratch "$HOME" "" A "" "" "" true
    [[ "$status" -eq 0 ]]
    run jq -r '.[0].uid // empty' "$WORKSPACES_FILE"
    [[ -n "$output" ]]
}
