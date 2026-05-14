#!/bin/bash
# Claude hook: clear the workspace pill alert after user activity.
# Triggered by: UserPromptSubmit, PostToolUse, PostToolUseFailure, SessionStart
#
# Restores the normal workspace pill border and removes the alert state file.
# On UserPromptSubmit, the keywords ".", "dismiss", and "clear" block the prompt
# so Claude doesn't respond (clearing the alert without starting a new cycle).

set -euo pipefail

INPUT=$(cat)

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

# --- Dismiss detection (UserPromptSubmit only) ---
HOOK_EVENT=$(echo "$INPUT" | jq -r '.hook_event_name // ""' 2>/dev/null)
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

if [ -n "$CWD" ] && [ -f "$WORKSPACES_FILE" ]; then
    _BEST_LEN=0
    while IFS=$'\t' read -r id name path; do
        [ -z "$path" ] && continue
        if [[ "$CWD" == "$path"* ]] && [ "${#path}" -gt "$_BEST_LEN" ]; then
            WS_ID="$id"
            _BEST_LEN="${#path}"
        fi
    done < <(jq -r '.[] | [.workspace_id, .name, .path] | @tsv' "$WORKSPACES_FILE" 2>/dev/null)
fi

SKETCHYBAR=/opt/homebrew/bin/sketchybar
[ -x "$SKETCHYBAR" ] || SKETCHYBAR=/usr/local/bin/sketchybar

# --- Restore workspace pill ---
if [ "${HUB_CLAUDE_NOTIFY_COLOR:-1}" != "0" ] && [ -n "$WS_ID" ]; then
    ALERT_FILE="/tmp/hub_claude_alert_${WS_ID}"
    if [ -f "$ALERT_FILE" ] && command -v "$SKETCHYBAR" &>/dev/null; then
        rm -f "$ALERT_FILE"
        FOCUSED=$(aerospace list-workspaces --focused 2>/dev/null || echo "")
        if [ "$WS_ID" = "$FOCUSED" ]; then
            BORDER_WIDTH=2
        else
            BORDER_WIDTH=1
        fi
        "$SKETCHYBAR" --set "space.${WS_ID}" \
            background.border_color=0xff414550 \
            background.border_width="$BORDER_WIDTH" 2>/dev/null || true
    fi
fi

# --- Block prompt if this was a dismiss keyword ---
if [ "$DISMISS" = "true" ]; then
    printf '{"decision":"block","reason":"Notification dismissed."}\n'
fi
