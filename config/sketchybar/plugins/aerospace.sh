#!/usr/bin/env bash

SKETCHYBAR=/opt/homebrew/bin/sketchybar
[ -x "$SKETCHYBAR" ] || SKETCHYBAR=/usr/local/bin/sketchybar

CURRENT="${AEROSPACE_FOCUSED_WORKSPACE:-$(aerospace list-workspaces --focused 2>/dev/null)}"
ACTIVE=$(aerospace list-workspaces --monitor all --empty no 2>/dev/null)
ACTIVE_LIST=" ${ACTIVE//$'\n'/ } ${CURRENT} "

MAXLEN_FILE="/tmp/helm_label_maxlen"
LABEL_MAXLEN=0
if [ -f "$MAXLEN_FILE" ]; then
    LABEL_MAXLEN=$(cat "$MAXLEN_FILE" 2>/dev/null || echo 0)
fi

WS_LABELS_FILE="/tmp/helm_sketchybar_labels"
LABELED_LIST=" "
declare -A WS_NAME
if [ -f "$WS_LABELS_FILE" ]; then
    while IFS=: read -r num name _; do
        LABELED_LIST+="$num "
        WS_NAME["$num"]="$name"
    done <"$WS_LABELS_FILE"
fi

truncate_label() {
    local ws="$1"
    local name="${WS_NAME[$ws]:-}"
    if [ -z "$name" ]; then
        echo "$ws"
        return
    fi
    if [ "$LABEL_MAXLEN" -gt 0 ] && [ "${#name}" -gt "$LABEL_MAXLEN" ]; then
        echo "$ws ${name:0:$LABEL_MAXLEN}…"
    else
        echo "$ws $name"
    fi
}

SLOT_COLORS=(
    "0xff1A73E8" "0xffFF7043" "0xff8E76D1" "0xff00C853" "0xffEC407A"
    "0xff00D1FF" "0xffF9A825" "0xff5C6BC0" "0xffEF5350" "0xff26C6DA"
    "0xffAEEA00" "0xff7E57C2" "0xfff39660" "0xff00A396" "0xffFFCA28"
    "0xffAB47BC" "0xff66BB6A" "0xffE05297" "0xff42A5F5" "0xff8D6E63"
    "0xff9CCC65" "0xffC62828" "0xff78909C" "0xffD4E157" "0xff4527A0"
    "0xffFFA726" "0xff00897B" "0xff6A1B9A" "0xff29B6F6" "0xff2E7D32"
    "0xff5C8AE6" "0xff1565C0" "0xff7889B3" "0xffFF6EC7" "0xff00838F"
)

slot_color() {
    local keys="1 2 3 4 5 6 7 8 9 A B C D E F G H I J K L M N O P Q R S T U V W X Y Z"
    local i=0
    for k in $keys; do
        if [ "$k" = "$1" ]; then
            echo "${SLOT_COLORS[$((i % ${#SLOT_COLORS[@]}))]}"
            return
        fi
        ((i++))
    done
    echo "${SLOT_COLORS[0]}"
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

ws_color() {
    local ws="$1"
    if [ -f "$WS_LABELS_FILE" ]; then
        local color_field
        color_field=$(grep "^${ws}:" "$WS_LABELS_FILE" 2>/dev/null | cut -d: -f3)
        if [ -n "$color_field" ]; then
            echo "0xff${color_field#\#}"
            return
        fi
    fi
    slot_color "$ws"
}

ARGS=()
for ws in 1 2 3 4 5 6 7 8 9 A B C D E F G H I J K L M N O P Q R S T U V W X Y Z; do
    lbl=$(truncate_label "$ws")
    if [[ $ACTIVE_LIST == *" $ws "* ]]; then
        if [ "$ws" = "$CURRENT" ]; then
            bg=$(ws_color "$ws")
            fg=$(label_color "$bg")
            ARGS+=(--set "space.$ws" drawing=on "label=$lbl"
                "label.color=$fg" label.font.size=13
                background.drawing=on "background.color=$bg"
                background.corner_radius=9 background.height=28
                background.border_width=2 "background.border_color=$BORDER_COLOR")
        else
            ARGS+=(--set "space.$ws" drawing=on "label=$lbl"
                label.color=0xaaffffff label.font.size=12
                background.drawing=on "background.color=$INACTIVE_BG"
                background.corner_radius=9 background.height=28
                background.border_width=1 "background.border_color=$BORDER_COLOR")
        fi
    elif [[ $LABELED_LIST == *" $ws "* ]]; then
        ARGS+=(--set "space.$ws" drawing=on "label=$lbl"
            label.color=0x55ffffff label.font.size=12
            background.drawing=on "background.color=$EMPTY_LABELED_BG"
            background.corner_radius=9 background.height=28
            background.border_width=0)
    else
        ARGS+=(--set "space.$ws" drawing=off)
    fi
done

"$SKETCHYBAR" "${ARGS[@]}"

"$(dirname "$0")/app_launcher.sh" &
