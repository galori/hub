#!/usr/bin/env bash
# Called on workspace change and front_app_switched — updates open-app indicator dots
# and dynamic ws_win slots for apps not in the launcher.
SKETCHYBAR=/opt/homebrew/bin/sketchybar
[ -x "$SKETCHYBAR" ] || SKETCHYBAR=/usr/local/bin/sketchybar
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

APPS_FILE="$HOME/.config/hub/apps.json"
[ -f "$APPS_FILE" ] || exit 0

CURRENT="${AEROSPACE_FOCUSED_WORKSPACE:-$(aerospace list-workspaces --focused 2>/dev/null)}"
[ -n "$CURRENT" ] || exit 0

WS_APPS="$(aerospace list-windows --workspace "$CURRENT" --format '%{app-name}' 2>/dev/null || echo "")"

# --- Launcher dot indicators ---
APP_NAMES=()
while IFS= read -r line; do
    [ -n "$line" ] && APP_NAMES+=("$line")
done < <(jq -r '.[].name' "$APPS_FILE" 2>/dev/null)

ARGS=()
for ((i=1; i<=5; i++)); do
    IDX=$((i-1))
    if [ "$IDX" -lt "${#APP_NAMES[@]}" ]; then
        if echo "$WS_APPS" | grep -qxF "${APP_NAMES[$IDX]}"; then
            ARGS+=(--set "app_slot.$i" icon.drawing=on)
        else
            ARGS+=(--set "app_slot.$i" icon.drawing=off)
        fi
    fi
done

# --- Dynamic ws_win slots: apps in workspace not already in launcher ---
LAUNCHER_SET=()
for name in "${APP_NAMES[@]}"; do
    LAUNCHER_SET+=("$name")
done

EXTRA_APPS=()
while IFS= read -r app; do
    [ -z "$app" ] && continue
    # Skip if already in launcher
    found=false
    for l in "${LAUNCHER_SET[@]}"; do
        [ "$l" = "$app" ] && found=true && break
    done
    $found && continue
    # Deduplicate
    already=false
    for e in "${EXTRA_APPS[@]}"; do
        [ "$e" = "$app" ] && already=true && break
    done
    $already || EXTRA_APPS+=("$app")
done <<< "$WS_APPS"

WS_WIN_COUNT=8
for ((i=1; i<=WS_WIN_COUNT; i++)); do
    idx=$((i-1))
    if [ "$idx" -lt "${#EXTRA_APPS[@]}" ]; then
        app="${EXTRA_APPS[$idx]}"
        ARGS+=(--set "ws_win.$i" drawing=on "background.image=app.$app" "label=$app")
    else
        ARGS+=(--set "ws_win.$i" drawing=off)
    fi
done

# Show/hide bracket and spacers with the ws_win block
if [ "${#EXTRA_APPS[@]}" -gt 0 ]; then
    ARGS+=(--set ws_wins_bracket drawing=on --set pad_ws_app drawing=on --set pad_ws_win drawing=on)
else
    ARGS+=(--set ws_wins_bracket drawing=off --set pad_ws_app drawing=off --set pad_ws_win drawing=off)
fi

if [ ${#ARGS[@]} -gt 0 ]; then
    "$SKETCHYBAR" "${ARGS[@]}"
fi
