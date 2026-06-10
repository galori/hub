#!/bin/bash
# Claude hook: track active/working state and clear alert state after user activity.
# Triggered by: UserPromptSubmit, PreToolUse, PostToolUse, PostToolUseFailure, SessionStart
#
# UserPromptSubmit / PreToolUse: start/maintain pulsing blue border (Claude is working).
# PostToolUse / PostToolUseFailure: do nothing — Claude is still mid-turn, keep pulsing.
# SessionStart: reset all state, restore normal border.
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

SKETCHYBAR=/opt/homebrew/bin/sketchybar
[ -x "$SKETCHYBAR" ] || SKETCHYBAR=/usr/local/bin/sketchybar

ALERT_FILE="/tmp/hub_claude_alert_${WS_ID}"
ACTIVE_FILE="/tmp/hub_claude_active_${WS_ID}"
PULSE_PID_FILE="/tmp/hub_claude_pulse_${WS_ID}.pid"

pulse_loop() {
    local ws="$1" sb="$2" active_file="$3" pid_file="$4"
    local bright=0xff76cce0 dim=0x3076cce0
    local phase=0
    while [ -f "$active_file" ]; do
        if [ "$phase" -eq 0 ]; then
            "$sb" --animate sin 45 --set "space.${ws}" background.border_color="$dim" 2>/dev/null || true
            phase=1
        else
            "$sb" --animate sin 45 --set "space.${ws}" background.border_color="$bright" 2>/dev/null || true
            phase=0
        fi
        sleep 0.75
    done
    rm -f "$pid_file"
}

start_active() {
    rm -f "$ALERT_FILE"
    touch "$ACTIVE_FILE"
    FOCUSED=$(aerospace list-workspaces --focused 2>/dev/null || echo "")
    if [ "$WS_ID" != "$FOCUSED" ]; then
        "$SKETCHYBAR" --set "space.${WS_ID}" \
            background.border_color=0xff76cce0 \
            background.border_width=3 2>/dev/null || true
        # Detach stdio so the hook pipe closes immediately — long-running loop
        # would otherwise hold it open and stall Claude Code.
        if [ ! -f "$PULSE_PID_FILE" ] || ! kill -0 "$(cat "$PULSE_PID_FILE" 2>/dev/null)" 2>/dev/null; then
            pulse_loop "$WS_ID" "$SKETCHYBAR" "$ACTIVE_FILE" "$PULSE_PID_FILE" </dev/null >/dev/null 2>&1 &
            echo $! > "$PULSE_PID_FILE"
            disown
        fi
    fi
}

clear_active() {
    rm -f "$ACTIVE_FILE" "$ALERT_FILE"
    if [ -f "$PULSE_PID_FILE" ]; then
        kill "$(cat "$PULSE_PID_FILE" 2>/dev/null)" 2>/dev/null || true
        rm -f "$PULSE_PID_FILE"
    fi
    FOCUSED=$(aerospace list-workspaces --focused 2>/dev/null || echo "")
    if [ "$WS_ID" != "$FOCUSED" ]; then
        "$SKETCHYBAR" --set "space.${WS_ID}" \
            background.border_color=0xff414550 \
            background.border_width=1 2>/dev/null || true
    fi
}

if [ "${HUB_CLAUDE_NOTIFY_COLOR:-1}" != "0" ] && [ -n "$WS_ID" ] && command -v "$SKETCHYBAR" &>/dev/null; then
    case "$HOOK_EVENT" in
        UserPromptSubmit)
            if [ "$DISMISS" = "true" ]; then
                clear_active
            else
                start_active
            fi
            ;;
        PreToolUse)
            # Ensure active state is set — pulse should already be running but
            # start it if it somehow died mid-turn.
            start_active
            ;;
        PostToolUse|PostToolUseFailure)
            # Claude is still mid-turn — leave the pulse running.
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
