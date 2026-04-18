#!/usr/bin/env bash

SKETCHYBAR=/opt/homebrew/bin/sketchybar
[ -x "$SKETCHYBAR" ] || SKETCHYBAR=/usr/local/bin/sketchybar

if [ "$AEROSPACE_MODE" = "service" ]; then
    "$SKETCHYBAR" --set aerospace_mode drawing=on label=S background.drawing=on
else
    "$SKETCHYBAR" --set aerospace_mode drawing=off
fi
