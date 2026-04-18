#!/usr/bin/env bash

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
done < <(python3 -c "
import json, sys
apps = json.load(open(sys.argv[1]))
for a in apps:
    print(a['name'])
" "$APPS_FILE" 2>/dev/null)

ARGS=()
for ((i=1; i<=5; i++)); do
    IDX=$((i-1))
    if [ "$IDX" -lt "${#APP_NAMES[@]}" ]; then
        if echo "$WS_APPS" | grep -qxF "${APP_NAMES[$IDX]}"; then
            ARGS+=(--set "app_slot.$i" background.image.scale=0.7)
        else
            ARGS+=(--set "app_slot.$i" background.image.scale=0.5)
        fi
    fi
done

if [ ${#ARGS[@]} -gt 0 ]; then
    "$SKETCHYBAR" "${ARGS[@]}"
fi
