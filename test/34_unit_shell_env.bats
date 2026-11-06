#!/usr/bin/env bats
# Unit tests for scripts/lib/shell_env.sh — deriving HUB_WORKSPACE_ID /
# HUB_WORKSPACE_UID from $PWD against workspaces.json so every hub-opened
# terminal gets the workspace env, regardless of launcher.

load helpers/stubs

REPO_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
HELPER="$REPO_DIR/scripts/lib/shell_env.sh"

setup() {
    setup_stubs
    export WORKSPACES_FILE="$HUB_CONFIG_DIR/workspaces.json"
    mkdir -p "$HUB_CONFIG_DIR"
}

teardown() {
    teardown_stubs
}

# write_workspaces <json> — write workspaces.json for this test.
write_workspaces() {
    printf '%s\n' "$1" > "$WORKSPACES_FILE"
}

# Run _hub_set_workspace_env in a clean bash with a given PWD, then print the
# resulting HUB_WORKSPACE_* vars. Only the function is defined (not the hooks),
# so startup/chpwd wiring does not run twice.
run_lookup() {
    local pwd_dir="$1"; shift
    run env -u HUB_WORKSPACE_ID -u HUB_WORKSPACE_UID -u HUB_WORKSPACE_ENV_AUTO \
        HOME="$HOME" HUB_CONFIG_DIR="$HUB_CONFIG_DIR" "$@" \
        bash -c "
            # define only the functions (skip the auto-run + hooks at file end)
            eval \"\$(sed '/^# Run once at shell startup\./,\$d' '$HELPER')\"
            cd -- '$pwd_dir' 2>/dev/null || exit 9
            _hub_set_workspace_env
            echo \"id=\${HUB_WORKSPACE_ID:-}\"
            echo \"uid=\${HUB_WORKSPACE_UID:-}\"
            echo \"auto=\${HUB_WORKSPACE_ENV_AUTO:-}\"
        "
}

@test "sets ID and UID when PWD equals a workspace path" {
    local ws="$HOME/proj"
    mkdir -p "$ws"
    write_workspaces "$(printf '[{"name":"P","path":"%s","workspace_id":"A","uid":"u-a"}]' "$ws")"
    run_lookup "$ws"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"id=A"* ]]
    [[ "$output" == *"uid=u-a"* ]]
    [[ "$output" == *"auto=1"* ]]
}

@test "sets env when PWD is a subdirectory of a workspace path" {
    local ws="$HOME/proj"
    mkdir -p "$ws/src/deep"
    write_workspaces "$(printf '[{"name":"P","path":"%s","workspace_id":"3","uid":"u3"}]' "$ws")"
    run_lookup "$ws/src/deep"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"id=3"* ]]
}

@test "does not match a sibling whose path is a string prefix" {
    local ws="$HOME/app"
    local sibling="$HOME/app2"
    mkdir -p "$ws" "$sibling"
    write_workspaces "$(printf '[{"name":"App","path":"%s","workspace_id":"A","uid":"ua"}]' "$ws")"
    run_lookup "$sibling"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"id="*$'\n'* ]]
    [[ "$output" != *"id=A"* ]]
}

@test "nested workspaces inner wins when inside inner" {
    local outer="$HOME/mono"
    local inner="$HOME/mono/pkg"
    mkdir -p "$inner"
    write_workspaces "$(printf '[{"name":"O","path":"%s","workspace_id":"O","uid":"uo"},{"name":"I","path":"%s","workspace_id":"I","uid":"ui"}]' "$outer" "$inner")"
    run_lookup "$inner"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"id=I"* ]]
    [[ "$output" == *"uid=ui"* ]]
}

@test "outer wins when in outer but not inner" {
    local outer="$HOME/mono"
    local inner="$HOME/mono/pkg"
    mkdir -p "$inner" "$outer/other"
    write_workspaces "$(printf '[{"name":"O","path":"%s","workspace_id":"O","uid":"uo"},{"name":"I","path":"%s","workspace_id":"I","uid":"ui"}]' "$outer" "$inner")"
    run_lookup "$outer/other"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"id=O"* ]]
}

@test "no match outside any workspace leaves env empty" {
    local ws="$HOME/proj"
    mkdir -p "$ws" "$HOME/elsewhere"
    write_workspaces "$(printf '[{"name":"P","path":"%s","workspace_id":"A","uid":"ua"}]' "$ws")"
    run_lookup "$HOME/elsewhere"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"id="$'\n'* ]]
    [[ "$output" != *"id=A"* ]]
}

@test "an explicit (non-auto) HUB_WORKSPACE_ID is never overwritten" {
    local ws="$HOME/proj"
    mkdir -p "$ws"
    write_workspaces "$(printf '[{"name":"P","path":"%s","workspace_id":"A","uid":"ua"}]' "$ws")"
    run env -u HUB_WORKSPACE_ENV_AUTO \
        HUB_WORKSPACE_ID=EXPLICIT HUB_WORKSPACE_UID=u-explicit \
        HOME="$HOME" HUB_CONFIG_DIR="$HUB_CONFIG_DIR" \
        bash -c "
            eval \"\$(sed '/^# Run once at shell startup\./,\$d' '$HELPER')\"
            cd -- '$ws'
            _hub_set_workspace_env
            echo \"id=\${HUB_WORKSPACE_ID:-}\"
        "
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"id=EXPLICIT"* ]]
}

@test "an auto-set value is cleared after cd'ing out of all workspaces" {
    local ws="$HOME/proj"
    mkdir -p "$ws" "$HOME/elsewhere"
    write_workspaces "$(printf '[{"name":"P","path":"%s","workspace_id":"A","uid":"ua"}]' "$ws")"
    run env -u HUB_WORKSPACE_ID -u HUB_WORKSPACE_UID -u HUB_WORKSPACE_ENV_AUTO \
        HOME="$HOME" HUB_CONFIG_DIR="$HUB_CONFIG_DIR" \
        bash -c "
            eval \"\$(sed '/^# Run once at shell startup\./,\$d' '$HELPER')\"
            cd -- '$ws'; _hub_set_workspace_env
            [ \"\$HUB_WORKSPACE_ID\" = A ] || { echo 'setup-failed'; exit 1; }
            cd -- '$HOME/elsewhere'; _hub_set_workspace_env
            echo \"id=\${HUB_WORKSPACE_ID:-EMPTY}\"
            echo \"auto=\${HUB_WORKSPACE_ENV_AUTO:-EMPTY}\"
        "
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"id=EMPTY"* ]]
    [[ "$output" == *"auto=EMPTY"* ]]
}

@test "missing workspaces.json is a no-op (no error)" {
    rm -f "$WORKSPACES_FILE"
    run_lookup "$HOME"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"id="$'\n'* ]]
}

@test "the generated shell-integration snippet sources the env helper" {
    run env HOME="$HOME" HUB_HOME="$HOME" HUB_CONFIG_DIR="$HUB_CONFIG_DIR" \
        SHELL=/bin/zsh REPO_DIR="$REPO_DIR" \
        bash -c "
            source '$REPO_DIR/scripts/hub' >/dev/null 2>&1
            install_shell_integration >/dev/null 2>&1
            cat '$REPO_DIR/.hub-shell-integration'
        "
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"shell_env.sh"* ]]
    [[ "$output" == *"alias hub="* ]]
}
