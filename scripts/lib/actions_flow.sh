#!/usr/bin/env bash
# Helpers for custom actions and the `hub actions` CLI.
# Sourced by scripts/hub; relies on its env (ACTIONS_FILE, ACTION_PRESETS_FILE, HUB_CONFIG_DIR).

ACTIONS_FILE="${ACTIONS_FILE:-$HOME/.config/hub/actions.json}"
ACTION_PRESETS_FILE="${ACTION_PRESETS_FILE:-$HOME/.config/hub/action_presets.json}"

actions_validate_slug() {
    local slug="$1"
    if [[ ! "$slug" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]{0,20}$ ]]; then
        fail "Invalid action slug: $slug"
        return 1
    fi
}

actions_refresh() {
    if command -v hub_bar_refresh >/dev/null 2>&1; then
        hub_bar_refresh
    elif [ -f "$HOME/.config/hub/hub_bar.pid" ]; then
        local _pid
        _pid="$(cat "$HOME/.config/hub/hub_bar.pid" 2>/dev/null || true)"
        [ -n "$_pid" ] && kill -USR1 "$_pid" 2>/dev/null || true
    fi
}

actions_default_json() {
    if [[ ! -f "$ACTION_PRESETS_FILE" ]]; then
        echo "[]"
        return
    fi
    jq '[."pr", ."jira", ."web"] | map(select(. != null))' "$ACTION_PRESETS_FILE"
}

actions_ensure_file() {
    mkdir -p "$(dirname "$ACTIONS_FILE")"
    [[ -f "$ACTIONS_FILE" ]] || echo "[]" > "$ACTIONS_FILE"
}

actions_list() {
    if [[ ! -f "$ACTIONS_FILE" ]]; then
        warn "No actions.json yet. Run: hub actions reset --defaults"
        return
    fi
    local count
    count="$(jq 'length' "$ACTIONS_FILE" 2>/dev/null || echo 0)"
    if [[ "$count" -eq 0 ]]; then
        info "No actions configured. Add one with: hub actions add <slug> --command '<command>'"
        return
    fi
    echo -e "${bold}Configured actions (${count}):${reset}"
    jq -c '.[]' "$ACTIONS_FILE" | while IFS= read -r action; do
        local slug description command
        slug="$(printf '%s' "$action" | jq -r '.slug // ""')"
        description="$(printf '%s' "$action" | jq -r '.description // ""')"
        command="$(printf '%s' "$action" | jq -r '.command // ""')"
        [[ -z "$slug" ]] && continue
        printf "  ${bold}%s${reset}\n" "$slug"
        [[ -n "$description" ]] && printf "      %s\n" "$description"
        printf "      command: %s\n" "$command"
    done
}

actions_list_presets() {
    if [[ ! -f "$ACTION_PRESETS_FILE" ]]; then
        warn "No action preset database at $ACTION_PRESETS_FILE"
        info "Run 'hub install' to deploy the shipped presets."
        return 1
    fi
    local count
    count="$(jq 'length' "$ACTION_PRESETS_FILE" 2>/dev/null || echo 0)"
    echo -e "${bold}Available action presets (${count}):${reset}"
    echo "  Source: $ACTION_PRESETS_FILE"
    echo
    jq -c 'to_entries | sort_by(.key) | .[]' "$ACTION_PRESETS_FILE" | while IFS= read -r entry; do
        local slug description command
        slug="$(printf '%s' "$entry" | jq -r '.value.slug // .key')"
        description="$(printf '%s' "$entry" | jq -r '.value.description // ""')"
        command="$(printf '%s' "$entry" | jq -r '.value.command // ""')"
        printf "  ${bold}%s${reset}\n" "$slug"
        [[ -n "$description" ]] && printf "      %s\n" "$description"
        printf "      command: %s\n\n" "$command"
    done
}

actions_preset_json() {
    local slug="$1"
    [[ -f "$ACTION_PRESETS_FILE" ]] || return 1
    jq -c --arg slug "$slug" '.[$slug] // empty' "$ACTION_PRESETS_FILE"
}

actions_save() {
    local slug="$1" command="$2" description="${3:-}" assume_yes="${4:-false}"
    actions_validate_slug "$slug" || return 1
    [[ -n "$command" ]] || { fail "Action command is required"; return 1; }
    actions_ensure_file

    local exists
    exists="$(jq -r --arg slug "$slug" 'map(select(.slug == $slug)) | length' "$ACTIONS_FILE" 2>/dev/null || echo 0)"
    if [[ "$exists" -gt 0 && -z "$description" ]]; then
        description="$(jq -r --arg slug "$slug" '.[] | select(.slug == $slug) | .description // empty' "$ACTIONS_FILE" | head -1)"
    fi
    if [[ "$exists" -gt 0 && "$assume_yes" != "true" ]]; then
        local yn
        read -rp "Replace action '$slug'? [y/N] " yn
        [[ "$yn" =~ ^[Yy] ]] || { info "Cancelled."; return 0; }
    fi

    local tmp
    tmp="$(mktemp "${ACTIONS_FILE}.XXXXXX")"
    jq --arg slug "$slug" \
       --arg command "$command" \
       --arg description "$description" \
       '
       map(select(.slug != $slug))
       + [{
           slug: $slug,
           command: $command
         } + (if $description != "" then {description: $description} else {} end)]
       ' "$ACTIONS_FILE" > "$tmp" && mv "$tmp" "$ACTIONS_FILE" || { rm -f "$tmp"; return 1; }
    hub_log_if_available "INPUT" "save action $slug"
    hub_log_if_available "CMD" "action $slug command: $command"
    success "Saved action: $slug"
    actions_refresh
}

actions_add_from_preset() {
    local slug="$1" assume_yes="${2:-false}"
    actions_validate_slug "$slug" || return 1
    local preset command description
    preset="$(actions_preset_json "$slug")"
    [[ -n "$preset" ]] || { fail "No action preset named: $slug"; return 1; }
    command="$(printf '%s' "$preset" | jq -r '.command // ""')"
    description="$(printf '%s' "$preset" | jq -r '.description // ""')"
    actions_save "$slug" "$command" "$description" "$assume_yes"
}

actions_remove() {
    local slug="$1"
    actions_validate_slug "$slug" || return 1
    [[ -f "$ACTIONS_FILE" ]] || { warn "No actions.json"; return 1; }
    local tmp
    tmp="$(mktemp "${ACTIONS_FILE}.XXXXXX")"
    jq --arg slug "$slug" 'map(select(.slug != $slug))' "$ACTIONS_FILE" > "$tmp" && mv "$tmp" "$ACTIONS_FILE" || { rm -f "$tmp"; return 1; }
    hub_log_if_available "INPUT" "remove action $slug"
    success "Removed action: $slug"
    actions_refresh
}

actions_reset_empty() {
    mkdir -p "$(dirname "$ACTIONS_FILE")"
    echo "[]" > "$ACTIONS_FILE"
    hub_log_if_available "INPUT" "clear actions"
    success "Cleared all actions"
    actions_refresh
}

actions_reset_defaults() {
    mkdir -p "$(dirname "$ACTIONS_FILE")"
    actions_default_json > "$ACTIONS_FILE"
    hub_log_if_available "INPUT" "restore default actions"
    success "Restored default actions"
    actions_refresh
}

actions_get_command() {
    local slug="$1"
    [[ -f "$ACTIONS_FILE" ]] || return 1
    jq -r --arg slug "$slug" '.[] | select(.slug == $slug) | .command // empty' "$ACTIONS_FILE" | head -1
}

actions_run() {
    local slug="$1"
    actions_validate_slug "$slug" || return 1
    local action_cmd
    action_cmd="$(actions_get_command "$slug")"
    if [[ -z "$action_cmd" ]]; then
        fail "No action configured for slug: $slug"
        return 1
    fi

    local ws_id ws_path
    ws_id="$(aerospace list-workspaces --focused 2>/dev/null || echo "")"
    if [[ -n "$ws_id" ]] && command -v get_workspace_path >/dev/null 2>&1; then
        ws_path="$(get_workspace_path "$ws_id")"
    else
        ws_path=""
    fi
    [[ -n "$ws_path" && -d "$ws_path" ]] || ws_path="$PWD"

    action_cmd="${action_cmd//\{path\}/$ws_path}"
    action_cmd="${action_cmd//\{workspace\}/$ws_id}"

    hub_log_if_available "INPUT" "run action $slug on workspace ${ws_id:-unknown} path $ws_path"
    hub_log_if_available "CMD" "action $slug: $action_cmd"

    local rc
    if ( cd "$ws_path" && bash -c "$action_cmd" ); then
        hub_log_if_available "OUT" "action $slug completed with exit 0"
        return 0
    else
        rc=$?
        hub_log_if_available "ERR" "action $slug failed with exit $rc"
        return "$rc"
    fi
}
