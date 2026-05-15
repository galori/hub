#!/usr/bin/env bash

SKETCHYBAR=/opt/homebrew/bin/sketchybar
[ -x "$SKETCHYBAR" ] || SKETCHYBAR=/usr/local/bin/sketchybar
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

CURRENT="${AEROSPACE_FOCUSED_WORKSPACE:-$(aerospace list-workspaces --focused 2>/dev/null)}"
ACTIVE=$(aerospace list-workspaces --monitor all --empty no 2>/dev/null)
ACTIVE_LIST=" ${ACTIVE//$'\n'/ } ${CURRENT} "

HUB_CONFIG_DIR="$HOME/.config/hub"
MAXLEN_FILE="$HUB_CONFIG_DIR/label_maxlen"
LABEL_MAXLEN=-1
if [ -f "$MAXLEN_FILE" ]; then
    LABEL_MAXLEN=$(cat "$MAXLEN_FILE" 2>/dev/null || echo -1)
fi
if ! [[ "$LABEL_MAXLEN" =~ ^-?[0-9]+$ ]]; then
    LABEL_MAXLEN=-1
fi

REPO_PREFIX_FILE="$HUB_CONFIG_DIR/repo_prefix"
REPO_PREFIX="off"
if [ -f "$REPO_PREFIX_FILE" ]; then
    REPO_PREFIX=$(cat "$REPO_PREFIX_FILE" 2>/dev/null || echo off)
fi

WS_LABELS_FILE="$HUB_CONFIG_DIR/sketchybar_labels"
LABELED_LIST=" "
declare -A WS_NAME_MAP WS_COLOR_MAP WS_REPO_MAP
if [ -f "$WS_LABELS_FILE" ]; then
    while IFS=: read -r num name color repo; do
        LABELED_LIST+="$num "
        [ -n "$name" ] && WS_NAME_MAP["$num"]="$name"
        [ -n "$color" ] && WS_COLOR_MAP["$num"]="0xff${color#\#}"
        [ -n "$repo" ] && WS_REPO_MAP["$num"]="$repo"
    done <"$WS_LABELS_FILE"
fi

SLOT_COLORS=(
    "0xff1A73E8" "0xffFF7043" "0xff8E76D1" "0xff00C853" "0xffEC407A"
    "0xff00D1FF" "0xffF9A825" "0xff5C6BC0" "0xffEF5350" "0xff26C6DA"
    "0xffAEEA00" "0xff7E57C2" "0xfff39660" "0xff00A396" "0xffFFCA28"
    "0xffAB47BC" "0xff66BB6A" "0xffE05297" "0xff42A5F5" "0xff8D6E63"
    "0xff9CCC65" "0xffC62828" "0xff78909C" "0xffD4E157" "0xff4527A0"
    "0xffFFA726" "0xff00897B" "0xff6A1B9A" "0xff29B6F6" "0xff2E7D32"
    "0xff5C8AE6" "0xff1565C0" "0xff7889B3" "0xffFF6EC7" "0xff00838F"
)

declare -A SLOT_COLOR_MAP
_i=0
for _k in 1 2 3 4 5 6 7 8 9 A B C D E F G H I J K L M N O P Q R S T U V W X Y Z; do
    SLOT_COLOR_MAP["$_k"]="${SLOT_COLORS[$((_i % ${#SLOT_COLORS[@]}))]}"
    ((_i++))
done

INACTIVE_BG=0x40363944
EMPTY_LABELED_BG=0x20363944
BORDER_COLOR=0xff414550

render_workspaces() {
    local ARGS=()
    for ws in 1 2 3 4 5 6 7 8 9 A B C D E F G H I J K L M N O P Q R S T U V W X Y Z; do
        local lbl="$ws"
        local name="${WS_NAME_MAP[$ws]}"
        local repo="${WS_REPO_MAP[$ws]}"
        # Prepend repo prefix when enabled and the name differs from the repo
        # (when name == repo it's the root checkout itself, just show the repo name)
        if [ "$REPO_PREFIX" = "on" ] && [ -n "$repo" ] && [ -n "$name" ] && [ "$name" != "$repo" ]; then
            name="${repo}:${name}"
        fi
        if [ -n "$name" ] && { [ "$LABEL_MAXLEN" -ne 0 ] || [ "$ws" = "$CURRENT" ]; }; then
            if [ "$LABEL_MAXLEN" -gt 0 ] && [ "${#name}" -gt "$LABEL_MAXLEN" ] && [ "$ws" != "$CURRENT" ]; then
                lbl="$ws ${name:0:$LABEL_MAXLEN}…"
            else
                lbl="$ws $name"
            fi
        fi

        # Auto-clear Claude alert/active state when the user visits the workspace
        local alert_file="/tmp/hub_claude_alert_${ws}"
        local active_file="/tmp/hub_claude_active_${ws}"
        local has_alert=false
        local has_active=false
        if [ "$ws" = "$CURRENT" ]; then
            rm -f "$alert_file" "$active_file"
        else
            [ -f "$alert_file" ] && has_alert=true
            [ -f "$active_file" ] && has_active=true
        fi

        if [[ $ACTIVE_LIST == *" $ws "* ]]; then
            if [ "$ws" = "$CURRENT" ]; then
                local bg="${WS_COLOR_MAP[$ws]:-${SLOT_COLOR_MAP[$ws]}}"
                local hex="${bg#0xff}"
                local r=$((16#${hex:0:2})) g=$((16#${hex:2:2})) b=$((16#${hex:4:2}))
                local lum=$(( (r * 299 + g * 587 + b * 114) / 1000 ))
                local fg; ((lum > 160)) && fg="0xff000000" || fg="0xffffffff"
                ARGS+=(--set "space.$ws" drawing=on "label=$lbl"
                    "label.color=$fg" label.font.size=13
                    background.drawing=on "background.color=$bg"
                    background.corner_radius=9 background.height=28
                    background.border_width=2 "background.border_color=$BORDER_COLOR")
            else
                local border_color="$BORDER_COLOR"
                local border_width=1
                if $has_active; then border_color=0xff76cce0; border_width=3;
                elif $has_alert; then border_color=0xffF9A825; border_width=3; fi
                ARGS+=(--set "space.$ws" drawing=on "label=$lbl"
                    label.color=0xaaffffff label.font.size=12
                    background.drawing=on "background.color=$INACTIVE_BG"
                    background.corner_radius=9 background.height=28
                    "background.border_width=$border_width" "background.border_color=$border_color")
            fi
        elif [[ $LABELED_LIST == *" $ws "* ]]; then
            local border_color2=0x00000000
            local border_width2=0
            if $has_active; then border_color2=0xff76cce0; border_width2=3;
            elif $has_alert; then border_color2=0xffF9A825; border_width2=3; fi
            ARGS+=(--set "space.$ws" drawing=on "label=$lbl"
                label.color=0x55ffffff label.font.size=12
                background.drawing=on "background.color=$EMPTY_LABELED_BG"
                background.corner_radius=9 background.height=28
                "background.border_width=$border_width2" "background.border_color=$border_color2")
        else
            ARGS+=(--set "space.$ws" drawing=off)
        fi
    done
    "$SKETCHYBAR" "${ARGS[@]}"
}

render_workspaces

"$SCRIPT_DIR/app_launcher.sh" >/dev/null 2>&1 &
