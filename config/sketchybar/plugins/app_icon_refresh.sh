#!/usr/bin/env bash
# Re-applies app slot background images to recover from startup/wake icon loading races.
SKETCHYBAR=/opt/homebrew/bin/sketchybar
[ -x "$SKETCHYBAR" ] || SKETCHYBAR=/usr/local/bin/sketchybar
APPS_FILE="$HOME/.config/hub/apps.json"
[ -f "$APPS_FILE" ] || exit 0

APP_COUNT=$(jq 'length' "$APPS_FILE" 2>/dev/null || echo 0)
[ "$APP_COUNT" -eq 0 ] && exit 0

ICONS_DIR="$HOME/.config/hub/icons"

ARGS=()
for ((i=1; i<=APP_COUNT; i++)); do
    IDX=$((i-1))
    APP_ICON=$(jq -r --argjson i "$IDX" '.[$i] | .icon // .name' "$APPS_FILE" 2>/dev/null)
    [ -z "$APP_ICON" ] && continue
    ICON_PNG="$ICONS_DIR/${APP_ICON}.png"
    if [ -f "$ICON_PNG" ]; then
        ARGS+=(--set "app_slot.$i" "background.image=$ICON_PNG")
    else
        ARGS+=(--set "app_slot.$i" "background.image=app.$APP_ICON")
    fi
done

# After the one-shot startup run, disable periodic polling.
# system_woke subscription keeps future refreshes working without polling.
[ "$SENDER" != "system_woke" ] && ARGS+=(--set app_icon_init update_freq=0)

[ ${#ARGS[@]} -gt 0 ] && "$SKETCHYBAR" "${ARGS[@]}"
