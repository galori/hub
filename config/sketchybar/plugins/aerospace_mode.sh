#!/usr/bin/env bash
# AeroSpace does not inject the current mode into exec-and-forget callbacks,
# so we track state with a toggle file: present = in service mode, absent = main.

SKETCHYBAR=/opt/homebrew/bin/sketchybar
[ -x "$SKETCHYBAR" ] || SKETCHYBAR=/usr/local/bin/sketchybar
STATE=/tmp/aerospace_in_service_mode

if [ -f "$STATE" ]; then
    rm "$STATE"
    "$SKETCHYBAR" --set aerospace_mode drawing=off
else
    touch "$STATE"
    "$SKETCHYBAR" --set aerospace_mode drawing=on label=S
fi
