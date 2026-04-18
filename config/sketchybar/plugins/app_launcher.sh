#!/usr/bin/env bash
# Called on workspace change — updates open-app indicator dots

SKETCHYBAR=/opt/homebrew/bin/sketchybar
[ -x "$SKETCHYBAR" ] || SKETCHYBAR=/usr/local/bin/sketchybar

APPS_FILE="$HOME/.config/ws2/apps.json"
[ -f "$APPS_FILE" ] || exit 0

CURRENT="${AEROSPACE_FOCUSED_WORKSPACE:-$(aerospace list-workspaces --focused 2>/dev/null)}"
[ -n "$CURRENT" ] || exit 0

WS_APPS="$(aerospace list-windows --workspace "$CURRENT" --format '%{app-name}' 2>/dev/null || echo "")"

APP_NAMES=()
while IFS= read -r line; do
    [ -n "$line" ] && APP_NAMES+=("$line")
done < <(jq -r '.[].name' "$APPS_FILE" 2>/dev/null)

ARGS=()
for ((i=1; i<=5; i++)); do
    IDX=$((i-1))
    if [ "$IDX" -lt "${#APP_NAMES[@]}" ]; then
        if echo "$WS_APPS" | grep -qxF "${APP_NAMES[$IDX]}"; then
            ARGS+=(--set "app_slot.$i" label.drawing=on)
        else
            ARGS+=(--set "app_slot.$i" label.drawing=off)
        fi
    fi
done

if [ ${#ARGS[@]} -gt 0 ]; then
    "$SKETCHYBAR" "${ARGS[@]}"
fi
