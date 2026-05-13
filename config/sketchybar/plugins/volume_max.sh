#!/bin/sh
# Jump to 100%, unmute if muted, play a preview tone.
osascript -e "set volume output muted false"
osascript -e "set volume output volume 100"
afplay /System/Library/Sounds/Pop.aiff >/dev/null 2>&1 &
