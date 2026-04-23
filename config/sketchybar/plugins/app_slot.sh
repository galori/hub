#!/usr/bin/env bash
# Handles hover, click feedback, and magnify for app launcher slots

SKETCHYBAR=/opt/homebrew/bin/sketchybar
[ -x "$SKETCHYBAR" ] || SKETCHYBAR=/usr/local/bin/sketchybar

HOVER_BG=0x33ffffff
CLICK_BG=0xff76cce0

case "$SENDER" in
    mouse.entered)
        "$SKETCHYBAR" --animate sin 10 --set "$NAME" \
            background.color=$HOVER_BG \
            background.border_color=0x55ffffff \
            background.border_width=1
        ;;
    mouse.exited)
        "$SKETCHYBAR" --animate sin 10 --set "$NAME" \
            background.color=0x00000000 \
            background.border_width=0
        ;;
    mouse.clicked)
        "$SKETCHYBAR" --set "$NAME" \
            background.color=$CLICK_BG \
            background.border_color=0xffffffff \
            background.border_width=2
        # Slot index from "app_slot.N"
        SLOT="${NAME##*.}"
        # Shift-click forces new window; plain click is smart focus-or-launch.
        # MODIFIER is set by sketchybar: "shift", "cmd", "alt", "ctrl" (or combos).
        if [[ "$MODIFIER" == *shift* ]]; then
            __HUB_SCRIPT__ open "$SLOT" --force &
        else
            __HUB_SCRIPT__ open "$SLOT" &
        fi
        sleep 0.12
        "$SKETCHYBAR" --animate tanh 12 --set "$NAME" \
            background.color=$HOVER_BG \
            background.border_color=0x55ffffff \
            background.border_width=1
        ;;
esac
