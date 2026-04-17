#!/usr/bin/env bash

ICON_CONNECTED=󰤨
ICON_DISCONNECTED=󰤭

GREEN=0xff9ed072
RED=0xfffc5d7c

WIFI_IF=$(networksetup -listallhardwareports 2>/dev/null | awk '/Wi-Fi/{getline; print $2}')
CONNECTED=$([ -n "$WIFI_IF" ] && ipconfig getifaddr "$WIFI_IF" 2>/dev/null)

if [ -n "$CONNECTED" ]; then
    sketchybar --set "$NAME" icon="$ICON_CONNECTED" icon.color="$GREEN" label.drawing=off
else
    sketchybar --set "$NAME" icon="$ICON_DISCONNECTED" icon.color="$RED" label.drawing=off
fi
