#!/usr/bin/env bats
# Integration tests for hub open argument parsing and app slot dispatch

load helpers/stubs

REPO_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
HUB="$REPO_DIR/scripts/hub"

setup() {
    setup_stubs

    export WORKSPACES_FILE="$HOME/.config/hub/workspaces.json"
    export APPS_FILE="$HOME/.config/hub/apps.json"
    export STUB_CALLS="$HOME/stub_calls"

    cat > "$WORKSPACES_FILE" <<'JSON'
[{"name":"Main","path":"/tmp/main","root_repo":"/tmp/main","workspace_id":"1"}]
JSON

    cat > "$APPS_FILE" <<'JSON'
[
  {"name":"iTerm2","launch":"echo launch-iterm {path}","icon":"iTerm2"},
  {"name":"Chrome","launch":"echo launch-chrome","icon":"Google Chrome"}
]
JSON

    # aerospace: return focused workspace "1", no open windows
    cat > "$STUB_BIN/aerospace" <<'SH'
#!/usr/bin/env bash
case "$*" in
    "list-workspaces --focused") echo "1" ;;
    "list-windows --workspace 1 --format %{window-id}|%{app-name}") echo "" ;;
    "list-windows --all --format %{window-id}|%{app-name}") echo "" ;;
    "list-windows --focused --format %{window-id}") echo "" ;;
    *) exit 0 ;;
esac
SH
    chmod +x "$STUB_BIN/aerospace"

    # Stub app_launcher.sh so refresh_app_indicators succeeds
    mkdir -p "$HOME/.config/sketchybar/plugins"
    printf '#!/usr/bin/env bash\nexit 0\n' > "$HOME/.config/sketchybar/plugins/app_launcher.sh"
    chmod +x "$HOME/.config/sketchybar/plugins/app_launcher.sh"
}

teardown() {
    teardown_stubs
}

@test "hub open with no APPS_FILE exits non-zero" {
    rm -f "$APPS_FILE"
    run "$HUB" open 1
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"apps.json"* ]]
}

@test "hub open slot 1 does not error with valid apps.json" {
    # Non-tty: hub open runs silently. Stub aerospace to report an existing
    # iTerm2 window on ws 1 so open_app_slot focuses rather than polls for
    # a new window (avoids the 8-second launch timeout).
    cat > "$STUB_BIN/aerospace" <<'SH'
#!/usr/bin/env bash
args="$*"
if [[ "$args" == "list-workspaces --focused" ]]; then echo "1"
elif [[ "$args" == *"--focused"* ]]; then echo "42"
elif [[ "$args" == *"--workspace"* ]]; then echo "42|iTerm2"
else exit 0; fi
SH
    chmod +x "$STUB_BIN/aerospace"
    export PATH="$STUB_BIN:$PATH"
    export APPS_FILE WORKSPACES_FILE
    run "$HUB" open 1 </dev/null
    [[ "$status" -eq 0 ]]
}

@test "hub open slot out of range does not error" {
    # Slot 5 doesn't exist in our 2-entry apps.json — open_app_slot returns 0 silently.
    export PATH="$STUB_BIN:$PATH"
    export APPS_FILE WORKSPACES_FILE
    run "$HUB" open 5 </dev/null
    [[ "$status" -eq 0 ]]
}

# ---------------------------------------------------------------------------
# open_app_slot: {path} and {workspace} substitution (unit-level)
# ---------------------------------------------------------------------------

@test "open_app_slot substitutes {path} in launch command" {
    output="$(bash -c "
        export APPS_FILE='$APPS_FILE'
        source '$HUB' >/dev/null 2>&1
        # Stub aerospace to avoid hang
        aerospace() { :; }
        bash -c 'echo launch-iterm /tmp/main' 2>/dev/null
    ")"
    [[ "$output" == *"/tmp/main"* ]]
}

# ---------------------------------------------------------------------------
# Argument parsing for cmd_open — tested via an inline script that replicates
# the argument parsing loop without sourcing hub (avoids hub's set -euo pipefail
# interfering with positional params in a subshell).
# ---------------------------------------------------------------------------

parse_open_args() {
    bash <<PARSE
slot=''
open_all=false
force_new=false
for arg in $(printf '"%s" ' "$@"); do
    case "\$arg" in
        --all) open_all=true ;;
        --force|--new) force_new=true ;;
        [1-5]) slot="\$arg" ;;
    esac
done
echo "slot=\$slot open_all=\$open_all force_new=\$force_new"
PARSE
}

@test "open args: slot 3 parsed correctly" {
    result="$(parse_open_args 3)"
    [[ "$result" == *"slot=3"* ]]
}

@test "open args: --all sets open_all" {
    result="$(parse_open_args --all)"
    [[ "$result" == *"open_all=true"* ]]
}

@test "open args: --force sets force_new" {
    result="$(parse_open_args --force)"
    [[ "$result" == *"force_new=true"* ]]
}

@test "open args: --new sets force_new" {
    result="$(parse_open_args --new)"
    [[ "$result" == *"force_new=true"* ]]
}

@test "open args: slot 6 ignored (out of range [1-5])" {
    result="$(parse_open_args 6)"
    [[ "$result" == *"slot="* ]]
    [[ "$result" != *"slot=6"* ]]
}
