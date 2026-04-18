#!/usr/bin/env bash
# Handles hover and click visual feedback for app launcher slots

SKETCHYBAR=/opt/homebrew/bin/sketchybar
[ -x "$SKETCHYBAR" ] || SKETCHYBAR=/usr/local/bin/sketchybar

HOVER_BG=0x33ffffff
CLICK_BG=0x66ffffff

case "$SENDER" in
    mouse.entered)
        "$SKETCHYBAR" --set "$NAME" background.color=$HOVER_BG
        ;;
    mouse.exited)
        "$SKETCHYBAR" --set "$NAME" background.color=0x00000000
        ;;
    mouse.clicked)
        "$SKETCHYBAR" --set "$NAME" background.color=$CLICK_BG
        sleep 0.12
        "$SKETCHYBAR" --set "$NAME" background.color=0x00000000
        ;;
esac
