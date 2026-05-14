#!/bin/bash
# Claude hook: alert when Claude needs attention — amber workspace pill, sound, speech.
# Triggered by: Stop (Claude finished responding)
#               PermissionRequest (permission dialog appears)
#
# Toggles (all enabled by default; set to "0" to skip):
#   HUB_CLAUDE_NOTIFY_COLOR — amber border on the workspace pill in sketchybar
#   HUB_CLAUDE_NOTIFY_SOUND — play alert sound (set to a file path for custom sound)
#   HUB_CLAUDE_NOTIFY_SPEAK — speak "<ws_id> <ws_name>" when iTerm is not focused
#                             (set to a custom phrase to speak that instead)

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

CWD=$(echo "$INPUT" | jq -r '.cwd // ""')

WORKSPACES_FILE="$HOME/.config/hub/workspaces.json"
WS_ID=""
WS_NAME=""

# Find the hub workspace whose path is a prefix of (or equals) the cwd.
# Pick the longest match so worktrees resolve to their workspace, not the root repo.
if [ -n "$CWD" ] && [ -f "$WORKSPACES_FILE" ]; then
    _BEST_LEN=0
    while IFS=$'\t' read -r id name path; do
        [ -z "$path" ] && continue
        if [[ "$CWD" == "$path"* ]] && [ "${#path}" -gt "$_BEST_LEN" ]; then
            WS_ID="$id"
            WS_NAME="$name"
            _BEST_LEN="${#path}"
        fi
    done < <(jq -r '.[] | [.workspace_id, .name, .path] | @tsv' "$WORKSPACES_FILE" 2>/dev/null)
fi

SKETCHYBAR=/opt/homebrew/bin/sketchybar
[ -x "$SKETCHYBAR" ] || SKETCHYBAR=/usr/local/bin/sketchybar

# --- Amber workspace pill ---
if [ "${HUB_CLAUDE_NOTIFY_COLOR:-1}" != "0" ] && [ -n "$WS_ID" ] && command -v "$SKETCHYBAR" &>/dev/null; then
    touch "/tmp/hub_claude_alert_${WS_ID}"
    "$SKETCHYBAR" --set "space.${WS_ID}" \
        background.border_color=0xffF9A825 \
        background.border_width=3 2>/dev/null || true
fi

# --- Sound ---
if [ "${HUB_CLAUDE_NOTIFY_SOUND:-1}" != "0" ]; then
    if [ -n "${HUB_CLAUDE_NOTIFY_SOUND:-}" ] && [ "${HUB_CLAUDE_NOTIFY_SOUND}" != "1" ] && [ -f "${HUB_CLAUDE_NOTIFY_SOUND}" ]; then
        afplay "${HUB_CLAUDE_NOTIFY_SOUND}" &
    else
        afplay /System/Library/Sounds/Funk.aiff &
    fi
fi

# --- Speak ---
if [ "${HUB_CLAUDE_NOTIFY_SPEAK:-1}" != "0" ]; then
    FRONTMOST=$(osascript -e 'tell application "System Events" to get name of first application process whose frontmost is true' 2>/dev/null || echo "")
    if [ "$FRONTMOST" != "iTerm2" ]; then
        if [ -n "${HUB_CLAUDE_NOTIFY_SPEAK:-}" ] && [ "${HUB_CLAUDE_NOTIFY_SPEAK}" != "1" ]; then
            say "${HUB_CLAUDE_NOTIFY_SPEAK}" &
        elif [ -n "$WS_ID" ]; then
            say "${WS_ID} ${WS_NAME}" &
        else
            say "$(basename "$CWD")" &
        fi
    fi
fi
