#!/bin/bash
# Claude hook: track active/working state and clear alert state after user activity.
# Triggered by: UserPromptSubmit, PreToolUse, PostToolUse, PostToolUseFailure, SessionStart
#
# UserPromptSubmit / PreToolUse: set active state flag (Hub Bar pulse animation runs in Swift).
# PostToolUse / PostToolUseFailure: do nothing — Claude is still mid-turn.
# SessionStart: reset all state flags.
# UserPromptSubmit with ".", "dismiss", or "clear": reset all state, block the prompt.

set -euo pipefail

INPUT=$(timeout 10 cat 2>/dev/null || true)

# Skip non-interactive invocations (e.g. claude -p from scripts)
is_non_interactive() {
    local pid=$$
    while [ "$pid" -gt 1 ]; do
        local cmd
        cmd=$(ps -p "$pid" -o args= 2>/dev/null)
        if echo "$cmd" | grep -qE '(^|/)claude[^ ]* ' && echo "$cmd" | grep -qE '(^| )(-p|--print)( |$)'; then
            return 0
        fi
        pid=$(ps -p "$pid" -o ppid= 2>/dev/null | tr -d ' ')
        [ -z "$pid" ] && break
    done
    return 1
}

if is_non_interactive; then
    exit 0
fi

HOOK_EVENT=$(echo "$INPUT" | jq -r '.hook_event_name // ""' 2>/dev/null)

# --- Dismiss detection (UserPromptSubmit only) ---
DISMISS=false
if [ "$HOOK_EVENT" = "UserPromptSubmit" ]; then
    PROMPT=$(echo "$INPUT" | jq -r '.prompt // ""' 2>/dev/null)
    TRIMMED=$(echo "$PROMPT" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    case "$TRIMMED" in
        . | dismiss | clear) DISMISS=true ;;
    esac
fi

CWD=$(echo "$INPUT" | jq -r '.cwd // ""')

WORKSPACES_FILE="$HOME/.config/hub/workspaces.json"
WS_ID=""

# Prefer the env var set by hub's prompt wrapper when launching any terminal
# with a prompt — it's exact and works even when two workspaces share the same
# directory. Fall back to longest-prefix cwd match otherwise.
if [ -n "${HUB_WORKSPACE_ID:-}" ] && [ -f "$WORKSPACES_FILE" ]; then
    _MATCH=$(jq -r --arg id "$HUB_WORKSPACE_ID" '.[] | select(.workspace_id == $id) | .workspace_id' "$WORKSPACES_FILE" 2>/dev/null | head -1)
    [ -n "$_MATCH" ] && WS_ID="$_MATCH"
fi

if [ -z "$WS_ID" ] && [ -n "$CWD" ] && [ -f "$WORKSPACES_FILE" ]; then
    _BEST_LEN=0
    while IFS=$'\t' read -r id name path; do
        [ -z "$path" ] && continue
        if [[ "$CWD" == "$path"* ]] && [ "${#path}" -gt "$_BEST_LEN" ]; then
            WS_ID="$id"
            _BEST_LEN="${#path}"
        fi
    done < <(jq -r '.[] | [.workspace_id, .name, .path] | @tsv' "$WORKSPACES_FILE" 2>/dev/null)
fi

HUB_PATH_FILE="$HOME/.config/hub/hub_path"
HUB_SCRIPT=""
[ -f "$HUB_PATH_FILE" ] && HUB_SCRIPT="$(cat "$HUB_PATH_FILE" 2>/dev/null || true)"

ALERT_FILE="/tmp/hub_claude_alert_${WS_ID}"
ACTIVE_FILE="/tmp/hub_claude_active_${WS_ID}"

start_active() {
    rm -f "$ALERT_FILE"
    touch "$ACTIVE_FILE"
    [ -n "$HUB_SCRIPT" ] && "$HUB_SCRIPT" bar-refresh 2>/dev/null &
}

clear_active() {
    rm -f "$ACTIVE_FILE" "$ALERT_FILE"
    [ -n "$HUB_SCRIPT" ] && "$HUB_SCRIPT" bar-refresh 2>/dev/null &
}

if [ "${HUB_CLAUDE_NOTIFY_COLOR:-1}" != "0" ] && [ -n "$WS_ID" ]; then
    case "$HOOK_EVENT" in
        UserPromptSubmit)
            if [ "$DISMISS" = "true" ]; then
                clear_active
            else
                start_active
            fi
            ;;
        PreToolUse)
            start_active
            ;;
        PostToolUse|PostToolUseFailure)
            # Claude is still mid-turn — leave state as-is.
            ;;
        SessionStart)
            clear_active
            ;;
    esac
fi

# --- Block prompt if this was a dismiss keyword ---
if [ "$DISMISS" = "true" ]; then
    printf '{"decision":"block","reason":"Notification dismissed."}\n'
fi
