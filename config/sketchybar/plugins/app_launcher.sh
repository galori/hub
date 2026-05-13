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

# System processes that produce icon-less modal windows (auth dialogs, agents, etc.)
SYSTEM_PROCS=(
    "SecurityAgent" "UserNotificationCenter" "ScreenSaverEngine"
    "System Preferences" "System Settings" "Finder"
    "universalaccessd" "loginwindow"
)

is_system_proc() {
    local name="$1"
    # Bundle-ID style names (contain dots) are background agents, not real apps
    [[ "$name" == *.* ]] && return 0
    for p in "${SYSTEM_PROCS[@]}"; do
        [ "$p" = "$name" ] && return 0
    done
    return 1
}

EXTRA_APPS=()
while IFS= read -r app; do
    [ -z "$app" ] && continue
    # Skip system processes with no useful icon
    is_system_proc "$app" && continue
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

ICONS_DIR="$HOME/.config/hub/icons"
mkdir -p "$ICONS_DIR"

# Extract a 36px PNG icon for an app on demand. Returns 0 if the cached file
# exists (or was just produced), nonzero otherwise.
ensure_icon_png() {
    local name="$1"
    local out="$ICONS_DIR/${name}.png"
    [ -f "$out" ] && return 0
    local app_path
    app_path=$(osascript -e "POSIX path of (path to application \"$name\")" 2>/dev/null || true)
    app_path="${app_path%$'\n'}"
    [ -z "$app_path" ] && return 1
    local icns_name icns
    icns_name=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIconFile" "${app_path}Contents/Info.plist" 2>/dev/null || true)
    [[ "$icns_name" != *.icns ]] && icns_name="${icns_name}.icns"
    icns="${app_path}Contents/Resources/${icns_name}"
    if [ ! -f "$icns" ]; then
        icns=$(find "${app_path}Contents/Resources" -maxdepth 1 -name "*.icns" 2>/dev/null | head -1)
    fi
    [ -z "$icns" ] && return 1
    sips -s format png "$icns" --out "$out" --resampleHeightWidthMax 36 &>/dev/null || return 1
    return 0
}

WS_WIN_COUNT=8
for ((i=1; i<=WS_WIN_COUNT; i++)); do
    idx=$((i-1))
    if [ "$idx" -lt "${#EXTRA_APPS[@]}" ]; then
        app="${EXTRA_APPS[$idx]}"
        # Prefer pre-extracted PNG (correct size); fall back to live app icon lookup
        if ensure_icon_png "$app"; then
            ARGS+=(--set "ws_win.$i" drawing=on "background.image=$ICONS_DIR/${app}.png" background.image.scale=1.0 "label=$app")
        else
            ARGS+=(--set "ws_win.$i" drawing=on "background.image=app.$app" background.image.scale=0.78 "label=$app")
        fi
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
