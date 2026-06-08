#!/bin/bash
# Claude hook: alert when Claude needs attention — amber workspace pill, sound.
# Triggered by: Stop (Claude finished responding)
#               PermissionRequest (permission dialog appears)
#
# Toggles (all enabled by default; set to "0" to skip):
#   HUB_CLAUDE_NOTIFY_COLOR — amber border on the workspace pill in sketchybar
#   HUB_CLAUDE_NOTIFY_SOUND — play alert sound (set to a file path for custom sound)

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

# Prefer the env var set by hub's prompt wrapper when launching any terminal
# with a prompt — it's exact and works even when two workspaces share the same
# directory. Fall back to longest-prefix cwd match otherwise.
if [ -n "${HUB_WORKSPACE_ID:-}" ] && [ -f "$WORKSPACES_FILE" ]; then
    _MATCH=$(jq -r --arg id "$HUB_WORKSPACE_ID" '.[] | select(.workspace_id == $id) | [.workspace_id, .name] | @tsv' "$WORKSPACES_FILE" 2>/dev/null | head -1)
    if [ -n "$_MATCH" ]; then
        IFS=$'\t' read -r WS_ID WS_NAME <<< "$_MATCH"
    fi
fi

if [ -z "$WS_ID" ] && [ -n "$CWD" ] && [ -f "$WORKSPACES_FILE" ]; then
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

# --- Amber workspace pill (stop pulse, clear active state, set attention state) ---
if [ "${HUB_CLAUDE_NOTIFY_COLOR:-1}" != "0" ] && [ -n "$WS_ID" ] && command -v "$SKETCHYBAR" &>/dev/null; then
    PULSE_PID_FILE="/tmp/hub_claude_pulse_${WS_ID}.pid"
    if [ -f "$PULSE_PID_FILE" ]; then
        kill "$(cat "$PULSE_PID_FILE" 2>/dev/null)" 2>/dev/null || true
        rm -f "$PULSE_PID_FILE"
    fi
    rm -f "/tmp/hub_claude_active_${WS_ID}"
    touch "/tmp/hub_claude_alert_${WS_ID}"
    "$SKETCHYBAR" --set "space.${WS_ID}" \
        background.border_color=0xffF9A825 \
        background.border_width=3 2>/dev/null || true
fi

# --- Sound ---
# Detach stdio so the hook pipe closes immediately — otherwise afplay holds
# stdout/stderr open and Claude Code stalls until the sound finishes.
if [ "${HUB_CLAUDE_NOTIFY_SOUND:-1}" != "0" ]; then
    if [ -n "${HUB_CLAUDE_NOTIFY_SOUND:-}" ] && [ "${HUB_CLAUDE_NOTIFY_SOUND}" != "1" ] && [ -f "${HUB_CLAUDE_NOTIFY_SOUND}" ]; then
        afplay "${HUB_CLAUDE_NOTIFY_SOUND}" </dev/null >/dev/null 2>&1 &
    else
        afplay /System/Library/Sounds/Funk.aiff </dev/null >/dev/null 2>&1 &
    fi
fi
