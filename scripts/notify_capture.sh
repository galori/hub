#!/usr/bin/env bash
set -euo pipefail

# Config
MSG="hub test"
OUT_DIR="/private/tmp"
TS="$(date +%Y%m%d_%H%M%S)"
FULL_IMG="${OUT_DIR}/hub_notify_full_${TS}.png"
CROPPED_IMG="${OUT_DIR}/hub_notify_${TS}.png"

# 1) Trigger notification
osascript -e "display notification \"${MSG}\""

# 2) Wait briefly so it's visible
sleep 1

# 3) Full screenshot
screencapture -x "${FULL_IMG}"

# 4) Read dimensions
WIDTH="$(sips -g pixelWidth "${FULL_IMG}" | awk '/pixelWidth:/ {print $2}')"
HEIGHT="$(sips -g pixelHeight "${FULL_IMG}" | awk '/pixelHeight:/ {print $2}')"

# 5) Crop: remove top 10% and right 30%
# Keep left 70% width and bottom 90% height, starting at y=10%, x=0.
CROP_W=$((WIDTH * 70 / 100))
CROP_H=$((HEIGHT * 90 / 100))
OFFSET_Y=$((HEIGHT * 10 / 100))
OFFSET_X=0

sips --cropOffset "${OFFSET_Y}" "${OFFSET_X}" \
  --cropToHeightWidth "${CROP_H}" "${CROP_W}" \
  "${FULL_IMG}" --out "${CROPPED_IMG}" >/dev/null

# Optional: remove full screenshot
rm -f "${FULL_IMG}"

# 6) Open and print final path
open "${CROPPED_IMG}"
echo "${CROPPED_IMG}"
