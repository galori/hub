#!/usr/bin/env bash
# Handles hover and click visual feedback for app launcher slots

SKETCHYBAR=/opt/homebrew/bin/sketchybar
[ -x "$SKETCHYBAR" ] || SKETCHYBAR=/usr/local/bin/sketchybar

HOVER_BG=0x33ffffff
CLICK_BG=0x55ffffff

case "$SENDER" in
    mouse.entered)
        "$SKETCHYBAR" --set "$NAME" background.color=$HOVER_BG
        ;;
    mouse.exited)
        "$SKETCHYBAR" --set "$NAME" background.color=0x00000000
        ;;
    mouse.clicked)
        # Instant feedback: bright flash + spinning label while ws2 open loads
        "$SKETCHYBAR" --set "$NAME" \
            background.color=$CLICK_BG \
            label="⋯" \
            label.drawing=on \
            label.font="Hack Nerd Font:Bold:11.0" \
            label.color=0xffffffff \
            label.padding_left=2 \
            label.padding_right=2
        # Reset after a moment (ws2 open will also reset via overlay; this is a fallback)
        sleep 3
        "$SKETCHYBAR" --set "$NAME" \
            background.color=0x00000000 \
            label.drawing=off
        ;;
esac
