#!/usr/bin/env bash
# Handles hover, click feedback, and magnify for app launcher slots

SKETCHYBAR=/opt/homebrew/bin/sketchybar
[ -x "$SKETCHYBAR" ] || SKETCHYBAR=/usr/local/bin/sketchybar

HOVER_BG=0x22ffffff
CLICK_BG=0x55ffffff
NORMAL_SCALE=0.8
HOVER_SCALE=0.9

case "$SENDER" in
    mouse.entered)
        "$SKETCHYBAR" --set "$NAME" \
            background.color=$HOVER_BG \
            background.image.scale=$HOVER_SCALE
        ;;
    mouse.exited)
        "$SKETCHYBAR" --set "$NAME" \
            background.color=0x00000000 \
            background.image.scale=$NORMAL_SCALE
        ;;
    mouse.clicked)
        # Rapid 3x flash for immediate feedback
        for _ in 1 2 3; do
            "$SKETCHYBAR" --set "$NAME" background.color=$CLICK_BG
            sleep 0.06
            "$SKETCHYBAR" --set "$NAME" background.color=0x00000000
            sleep 0.06
        done
        "$SKETCHYBAR" --set "$NAME" \
            background.color=$HOVER_BG \
            background.image.scale=$NORMAL_SCALE
        ;;
esac
