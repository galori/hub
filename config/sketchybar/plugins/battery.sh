#!/usr/bin/env bash

PERCENTAGE="$(pmset -g batt | grep -Eo "\d+%" | cut -d% -f1)"
CHARGING="$(pmset -g batt | grep 'AC Power')"

if [ "$PERCENTAGE" = "" ]; then
    exit 0
fi

GREEN=0xff9ed072
ORANGE=0xfff39660
RED=0xfffc5d7c
BLUE=0xff76cce0

case "${PERCENTAGE}" in
9[0-9] | 100) ICON=󰁹; COLOR=$GREEN  ;;
[7-8][0-9])   ICON=󰂀; COLOR=$GREEN  ;;
[5-6][0-9])   ICON=󰁾; COLOR=$GREEN  ;;
[3-4][0-9])   ICON=󰁼; COLOR=$ORANGE ;;
[1-2][0-9])   ICON=󰁺; COLOR=$RED    ;;
*)            ICON=󰂃; COLOR=$RED    ;;
esac

if [[ $CHARGING != "" ]]; then
    COLOR=$BLUE
fi

sketchybar --set "$NAME" icon="$ICON" icon.color="$COLOR" label="${PERCENTAGE}%"
