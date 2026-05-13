#!/bin/sh
# Toggle output mute. Works regardless of current mute state.
muted=$(osascript -e "output muted of (get volume settings)")
if [ "$muted" = "true" ]; then
    osascript -e "set volume output muted false"
else
    osascript -e "set volume output muted true"
fi
