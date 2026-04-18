#!/usr/bin/env bash
# Handles hover, click feedback, and magnify for app launcher slots

SKETCHYBAR=/opt/homebrew/bin/sketchybar
[ -x "$SKETCHYBAR" ] || SKETCHYBAR=/usr/local/bin/sketchybar

HOVER_BG=0x22ffffff
CLICK_BG=0x55ffffff

NORMAL_SCALE=0.80
HOVER_SCALE=1.05

SLOT_WIDTH=34

case "$SENDER" in
    mouse.entered)
        "$SKETCHYBAR" --animate sin 12 --set "$NAME" \
            width=$SLOT_WIDTH \
            background.color=$HOVER_BG \
            background.image.scale=$HOVER_SCALE
        ;;
    mouse.exited)
        "$SKETCHYBAR" --animate sin 12 --set "$NAME" \
            width=$SLOT_WIDTH \
            background.color=0x00000000 \
            background.image.scale=$NORMAL_SCALE
        ;;
    mouse.clicked)
        "$SKETCHYBAR" --animate tanh 6 --set "$NAME" background.color=$CLICK_BG
        sleep 0.08
        "$SKETCHYBAR" --animate tanh 10 --set "$NAME" \
            width=$SLOT_WIDTH \
            background.color=$HOVER_BG \
            background.image.scale=$HOVER_SCALE
        ;;
esac
