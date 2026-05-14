#!/usr/bin/env bash
# Hides the service-mode indicator. Called by sketchybarrc on startup to
# guarantee the indicator starts hidden regardless of prior state.

SKETCHYBAR=/opt/homebrew/bin/sketchybar
[ -x "$SKETCHYBAR" ] || SKETCHYBAR=/usr/local/bin/sketchybar

"$SKETCHYBAR" --set aerospace_mode drawing=off
