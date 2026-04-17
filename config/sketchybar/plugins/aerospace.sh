#!/usr/bin/env bash

SKETCHYBAR=/opt/homebrew/bin/sketchybar
[ -x "$SKETCHYBAR" ] || SKETCHYBAR=/usr/local/bin/sketchybar

CURRENT="${AEROSPACE_FOCUSED_WORKSPACE:-$(aerospace list-workspaces --focused 2>/dev/null)}"
ACTIVE=$(aerospace list-workspaces --monitor all --empty no 2>/dev/null)
ACTIVE_LIST=" ${ACTIVE//$'\n'/ } ${CURRENT} "

WS_LABELS_FILE="/tmp/ws2_sketchybar_labels"
LABELED_LIST=" "
if [ -f "$WS_LABELS_FILE" ]; then
    while IFS=: read -r num _; do
        LABELED_LIST+="$num "
    done <"$WS_LABELS_FILE"
fi

slot_color() {
    case "$1" in
    1) echo "0xff1A73E8" ;;
    2) echo "0xff00D1FF" ;;
    3) echo "0xff00A396" ;;
    4) echo "0xff00C853" ;;
    5) echo "0xffAEEA00" ;;
    6) echo "0xff8E76D1" ;;
    7) echo "0xff7889B3" ;;
    *) echo "0xfff39660" ;;
    esac
}

label_color() {
    local hex="${1#0xff}"
    local r=$((16#${hex:0:2}))
    local g=$((16#${hex:2:2}))
    local b=$((16#${hex:4:2}))
    local lum=$(( (r * 299 + g * 587 + b * 114) / 1000 ))
    ((lum > 160)) && echo "0xff000000" || echo "0xffffffff"
}

INACTIVE_BG=0x40363944
EMPTY_LABELED_BG=0x20363944
BORDER_COLOR=0xff414550

ARGS=()
for ws in 1 2 3 4 5 6 7 8 9 A B C D E F G H I J K L M N O P Q R S T U V W X Y Z; do
    if [[ $ACTIVE_LIST == *" $ws "* ]]; then
        if [ "$ws" = "$CURRENT" ]; then
            bg=$(slot_color "$ws")
            fg=$(label_color "$bg")
            ARGS+=(--set "space.$ws" drawing=on
                "label.color=$fg" label.font.size=13
                background.drawing=on "background.color=$bg"
                background.corner_radius=9 background.height=28
                background.border_width=2 "background.border_color=$BORDER_COLOR")
        else
            ARGS+=(--set "space.$ws" drawing=on
                label.color=0xaaffffff label.font.size=12
                background.drawing=on "background.color=$INACTIVE_BG"
                background.corner_radius=9 background.height=28
                background.border_width=1 "background.border_color=$BORDER_COLOR")
        fi
    elif [[ $LABELED_LIST == *" $ws "* ]]; then
        ARGS+=(--set "space.$ws" drawing=on
            label.color=0x55ffffff label.font.size=12
            background.drawing=on "background.color=$EMPTY_LABELED_BG"
            background.corner_radius=9 background.height=28
            background.border_width=0)
    else
        ARGS+=(--set "space.$ws" drawing=off)
    fi
done

"$SKETCHYBAR" "${ARGS[@]}"
