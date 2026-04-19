#!/usr/bin/env bash
# Click handler for dynamic ws_win slots — focuses a window of the app in this slot.

SKETCHYBAR=/opt/homebrew/bin/sketchybar
[ -x "$SKETCHYBAR" ] || SKETCHYBAR=/usr/local/bin/sketchybar

# Read stored app name from label
APP_NAME="$("$SKETCHYBAR" --query "$NAME" 2>/dev/null | jq -r '.label.value // empty')"
[ -n "$APP_NAME" ] || exit 0

CURRENT="$(aerospace list-workspaces --focused 2>/dev/null)"
[ -n "$CURRENT" ] || exit 0

# Find windows of this app in the current workspace, focus the first (or next after focused)
WIN_IDS="$(aerospace list-windows --workspace "$CURRENT" --format '%{window-id}|%{app-name}' 2>/dev/null \
    | grep "|${APP_NAME}$" | cut -d'|' -f1)"
[ -n "$WIN_IDS" ] || exit 0

FOCUSED="$(aerospace list-windows --focused --format '%{window-id}' 2>/dev/null || echo "")"
TARGET="" FIRST="" TAKE_NEXT=false
while IFS= read -r wid; do
    [ -z "$wid" ] && continue
    [ -z "$FIRST" ] && FIRST="$wid"
    if "$TAKE_NEXT"; then TARGET="$wid"; break; fi
    [ "$wid" = "$FOCUSED" ] && TAKE_NEXT=true
done <<< "$WIN_IDS"
[ -z "$TARGET" ] && TARGET="$FIRST"

aerospace focus --window-id "$TARGET" 2>/dev/null || true
