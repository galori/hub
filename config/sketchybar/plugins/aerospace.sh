#!/usr/bin/env bash

SKETCHYBAR=/opt/homebrew/bin/sketchybar
[ -x "$SKETCHYBAR" ] || SKETCHYBAR=/usr/local/bin/sketchybar
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

CURRENT="${AEROSPACE_FOCUSED_WORKSPACE:-$(aerospace list-workspaces --focused 2>/dev/null)}"
ACTIVE=$(aerospace list-workspaces --monitor all --empty no 2>/dev/null)
ACTIVE_LIST=" ${ACTIVE//$'\n'/ } ${CURRENT} "

MAXLEN_FILE="/tmp/helm_label_maxlen"
LABEL_MAXLEN=-1
if [ -f "$MAXLEN_FILE" ]; then
    LABEL_MAXLEN=$(cat "$MAXLEN_FILE" 2>/dev/null || echo -1)
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
    local short="${2:-false}"
    local name="${WS_NAME[$ws]:-}"
    if [ -z "$name" ] || [ "$short" = "true" ]; then
        echo "$ws"
        return
    fi
    # LABEL_MAXLEN: -1 = unlimited, 0 = code only, N>0 = truncate at N chars
    if [ "$LABEL_MAXLEN" -eq 0 ]; then
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

# Ordered list of visible workspaces (left to right)
VISIBLE_WS=()
for ws in 1 2 3 4 5 6 7 8 9 A B C D E F G H I J K L M N O P Q R S T U V W X Y Z; do
    if [[ $ACTIVE_LIST == *" $ws "* ]] || [[ $LABELED_LIST == *" $ws "* ]]; then
        VISIBLE_WS+=("$ws")
    fi
done

# WS_SHORT["ws"]=true means render that workspace ID-only (no name)
declare -A WS_SHORT

render_workspaces() {
    local ARGS=()
    for ws in 1 2 3 4 5 6 7 8 9 A B C D E F G H I J K L M N O P Q R S T U V W X Y Z; do
        local lbl
        lbl=$(truncate_label "$ws" "${WS_SHORT[$ws]:-false}")
        if [[ $ACTIVE_LIST == *" $ws "* ]]; then
            if [ "$ws" = "$CURRENT" ]; then
                local bg fg
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
}

render_workspaces

# --- Overflow detection ---
# Query the right edge of a sketchybar item (returns -1 if hidden/missing)
item_right_edge() {
    "$SKETCHYBAR" --query "$1" 2>/dev/null | python3 -c "
import sys, json
d = json.load(sys.stdin)
rects = d.get('bounding_rects', {})
if rects:
    print(int(max(v['origin'][0] + v['size'][0] for v in rects.values())))
else:
    print(-1)
" 2>/dev/null || echo -1
}

item_left_edge() {
    "$SKETCHYBAR" --query "$1" 2>/dev/null | python3 -c "
import sys, json
d = json.load(sys.stdin)
rects = d.get('bounding_rects', {})
if rects:
    print(int(min(v['origin'][0] for v in rects.values())))
else:
    print(-1)
" 2>/dev/null || echo -1
}

# Only run overflow check if there are named workspaces that could be shortened
if [ "${#VISIBLE_WS[@]}" -eq 0 ]; then
    "$SCRIPT_DIR/app_launcher.sh" &
    exit 0
fi

# Find the rightmost visible workspace
RIGHTMOST_WS="${VISIBLE_WS[${#VISIBLE_WS[@]}-1]}"

# Right-side boundary = left edge of the leftmost visible right-side item.
# When the dynamic ws_win block is showing, pad_ws_win is its left spacer and
# is leftmost. When it's hidden, fall back to pad_r5 (left of static launcher).
BOUNDARY=$(item_left_edge "pad_ws_win")
if [ "$BOUNDARY" -le 0 ]; then
    BOUNDARY=$(item_left_edge "pad_r5")
fi
if [ "$BOUNDARY" -le 0 ]; then
    "$SCRIPT_DIR/app_launcher.sh" &
    exit 0
fi

WS_RIGHT=$(item_right_edge "space.$RIGHTMOST_WS")
if [ "$WS_RIGHT" -le 0 ] || [ "$WS_RIGHT" -le "$BOUNDARY" ]; then
    "$SCRIPT_DIR/app_launcher.sh" &
    exit 0
fi

# Overflow: shorten labels from rightmost inward until the row fits
for ((idx=${#VISIBLE_WS[@]}-1; idx>=0; idx--)); do
    ws="${VISIBLE_WS[$idx]}"
    # Skip workspaces that are already ID-only (no name to remove)
    if [ -z "${WS_NAME[$ws]:-}" ]; then
        continue
    fi
    WS_SHORT["$ws"]=true
    render_workspaces
    sleep 0.05
    WS_RIGHT=$(item_right_edge "space.$RIGHTMOST_WS")
    if [ "$WS_RIGHT" -le 0 ] || [ "$WS_RIGHT" -le "$BOUNDARY" ]; then
        break
    fi
done

"$SCRIPT_DIR/app_launcher.sh" &
