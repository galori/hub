#!/usr/bin/env bats
# Tests for directory-safe prompt templates and exact installed-template migration.

load helpers/stubs

REPO_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
HUB="$REPO_DIR/scripts/hub"

setup() {
    setup_stubs
    export APPS_FILE="$HOME/.config/hub/apps.json"
    export APP_PRESETS_FILE="$HOME/.config/hub/app_presets.json"
    export WORKSPACES_FILE="$HOME/.config/hub/workspaces.json"
}

teardown() {
    teardown_stubs
}

@test "shipped terminal prompt templates do not embed an unescaped workspace cd" {
    run jq -r '.[] | .prompt_launch // empty' "$REPO_DIR/config/app_presets.json"
    [[ "$status" -eq 0 ]]
    [[ "$output" != *'cd {path} && {prompt_cmd}'* ]]
    [[ "$output" != *'--working-directory="{path}"'* ]]
    [[ "$output" != *'--cwd {path} -- {prompt_cmd}'* ]]
    [[ "$output" == *'{prompt_cmd}'* ]]
}

@test "deploy migrates exact old terminal templates and preserves custom commands" {
    mkdir -p "$(dirname "$APPS_FILE")"
    local old_iterm old_terminal old_ghostty old_wezterm
    old_iterm="$(jq -r '.[] | select(.name == "iTerm2") | .prompt_launch' "$REPO_DIR/config/app_presets.json" | sed 's#write text "{prompt_cmd}"#write text "cd {path} \&\& {prompt_cmd}"#')"
    old_terminal="$(jq -r '.[] | select(.name == "Terminal") | .prompt_launch' "$REPO_DIR/config/app_presets.json" | sed 's#do script "{prompt_cmd}"#do script "cd {path} \&\& {prompt_cmd}"#')"
    old_ghostty="$(jq -r '.[] | select(.name == "Ghostty") | .prompt_launch' "$REPO_DIR/config/app_presets.json" | sed 's#--quit-after-last-window-closed=false#--working-directory="{path}" --quit-after-last-window-closed=false#')"
    old_wezterm="$(jq -r '.[] | select(.name == "WezTerm") | .prompt_launch' "$REPO_DIR/config/app_presets.json" | sed 's#-- {prompt_cmd}#--cwd {path} -- {prompt_cmd}#')"
    jq -n --arg i "$old_iterm" --arg t "$old_terminal" --arg g "$old_ghostty" --arg w "$old_wezterm" '[
      {name:"iTerm2", prompt_launch:$i, launch:"keep"},
      {name:"Terminal", prompt_launch:$t, launch:"keep"},
      {name:"Ghostty", prompt_launch:$g, first_prompt_launch:$g, launch:"keep"},
      {name:"WezTerm", prompt_launch:$w, launch:"keep"},
      {name:"Custom", prompt_launch:"custom {path} {prompt_cmd}", launch:"custom launch"}
    ]' > "$APPS_FILE"
    run bash -c "
        export HOME='$HOME' HUB_HOME='$HOME' HUB_CONFIG_DIR='$HUB_CONFIG_DIR' HUB_RUNTIME_DIR='$HUB_RUNTIME_DIR' APPS_FILE='$APPS_FILE' APP_PRESETS_FILE='$APP_PRESETS_FILE'
        source '$HUB' >/dev/null 2>&1
        deploy_app_presets
        if jq -r '.[].prompt_launch // empty' '$APPS_FILE' | grep -q 'cd {path} && {prompt_cmd}'; then exit 11; fi
        if jq -r '.[].prompt_launch // empty' '$APPS_FILE' | grep -q -- '--working-directory=\"{path}\"'; then exit 12; fi
        if jq -r '.[].prompt_launch // empty' '$APPS_FILE' | grep -q -- '--cwd {path} -- {prompt_cmd}'; then exit 13; fi
        jq -e 'any(.[]; .name == \"Custom\" and .prompt_launch == \"custom {path} {prompt_cmd}\" and .launch == \"custom launch\")' '$APPS_FILE' >/dev/null
    "
    [[ "$status" -eq 0 ]]
}

@test "prompt wrapper owns a workspace path with spaces and apostrophes" {
    local workspace
    workspace="$(printf '%s/work space\047s' "$HOME")"
    mkdir -p "$workspace"
    cat > "$APPS_FILE" <<'JSON'
[{"name":"Terminal","prompt_launch":"{prompt_cmd}"}]
JSON
    printf '[{"name":"Main","path":"%s","workspace_id":"A","uid":"u"}]\n' "$workspace" > "$WORKSPACES_FILE"
    run env \
        HOME="$HOME" HUB_HOME="$HOME" HUB_CONFIG_DIR="$HUB_CONFIG_DIR" HUB_RUNTIME_DIR="$HUB_RUNTIME_DIR" \
        APPS_FILE="$APPS_FILE" WORKSPACES_FILE="$WORKSPACES_FILE" \
        TEST_WORKSPACE="$workspace" HUB_SCRIPT="$HUB" \
        bash -c '
        source "$HUB_SCRIPT" >/dev/null 2>&1
        wrapper="$(_build_prompt_cmd prompt 1 false A "$TEST_WORKSPACE")"
        grep -q "cd --" "$wrapper"
        zsh -n "$wrapper"
    '
    [[ "$status" -eq 0 ]]
}
