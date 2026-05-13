#!/bin/sh
# Set output volume to the clicked slider percentage, then play a short preview tone.
osascript -e "set volume output volume $PERCENTAGE"
afplay /System/Library/Sounds/Pop.aiff >/dev/null 2>&1 &
