#!/usr/bin/env bats
# Integration test: mini status bar tooltips
#
# Exercises the deployed Hub Bar in a real GUI session. It opens the cluster
# overlay, hovers the layout toggle while another app remains frontmost, and
# verifies the app-owned tooltip panel appears above the overlay and hides when
# the pointer leaves.

# shellcheck disable=SC2034
BATS_TEST_DIRNAME="${BATS_TEST_DIRNAME:-$(dirname "$0")}"
load helpers

BANNER_STARTED="0"

setup() {
    require_live_session
}

teardown() {
    move_cursor_to_main_display_center >/dev/null 2>&1 || true

    if [[ "$BANNER_STARTED" == "1" ]]; then
        "$(hub_bin)" testing-banner stop >/dev/null 2>&1 || true
    fi
}

hub_bar_windows() {
    swift -e 'import Cocoa
let pidPath = NSHomeDirectory() + "/.config/hub/hub_bar.pid"
guard let rawPID = try? String(contentsOfFile: pidPath, encoding: .utf8),
      let hubPID = Int(rawPID.trimmingCharacters(in: .whitespacesAndNewlines)) else { exit(1) }
let options: CGWindowListOption = [.excludeDesktopElements, .optionOnScreenOnly]
let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
for window in windows {
    guard (window[kCGWindowOwnerPID as String] as? NSNumber)?.intValue == hubPID,
          let layer = window[kCGWindowLayer as String] as? NSNumber,
          let bounds = window[kCGWindowBounds as String] as? NSDictionary,
          let x = bounds["X"] as? NSNumber,
          let y = bounds["Y"] as? NSNumber,
          let width = bounds["Width"] as? NSNumber,
          let height = bounds["Height"] as? NSNumber else { continue }
    print("\(layer.intValue) \(Int(x.doubleValue)) \(Int(y.doubleValue)) \(Int(width.doubleValue)) \(Int(height.doubleValue))")
}'
}

cluster_overlay_window() {
    hub_bar_windows | awk '$5 >= 50 && $5 <= 54 { print; exit }'
}

primary_hub_bar_window() {
    hub_bar_windows | awk '$5 >= 35 && $5 <= 200 && $4 > widest { widest = $4; primary = $0 } END { print primary }'
}

tooltip_window() {
    hub_bar_windows | awk '$4 >= 35 && $4 <= 316 && $5 >= 20 && $5 <= 35 { print; exit }'
}

frontmost_app_is_not_hub_bar() {
    swift -e 'import Cocoa
let pidPath = NSHomeDirectory() + "/.config/hub/hub_bar.pid"
guard let rawPID = try? String(contentsOfFile: pidPath, encoding: .utf8),
      let hubPID = Int32(rawPID.trimmingCharacters(in: .whitespacesAndNewlines)),
      let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier else { exit(1) }
exit(frontPID == hubPID ? 1 : 0)'
}

warp_cursor() {
    local x="$1"
    local y="$2"
    swift -e 'import CoreGraphics
import Darwin
guard CommandLine.arguments.count == 3,
      let x = Double(CommandLine.arguments[1]),
      let y = Double(CommandLine.arguments[2]) else { exit(2) }
let error = CGWarpMouseCursorPosition(CGPoint(x: x, y: y))
CGAssociateMouseAndMouseCursorPosition(1)
exit(error == .success ? 0 : 1)' "$x" "$y"
}

@test "mini status bar shows an always-on-top tooltip without activating Hub Bar" {
    local hub bar overlay tooltip overlay_layer overlay_x overlay_y overlay_width
    local tooltip_layer hover_x hover_y
    hub="$(hub_bin)"

    "$hub" testing-banner start "tooltip check" >/dev/null 2>&1 && BANNER_STARTED="1" || true
    osascript -e 'tell application "Finder" to activate'
    wait_for 5 "another app is frontmost before tooltip hover" \
        'frontmost_app_is_not_hub_bar'
    move_cursor_to_main_display_center

    wait_for 5 "no stale Hub Bar tooltip panel is visible" \
        '[[ -z "$(tooltip_window)" ]]'

    bar="$(primary_hub_bar_window)"
    echo "# primary Hub Bar: $bar" >&3
    read -r _ _bar_x _bar_y _bar_width _bar_height <<<"$bar"
    [[ -n "$_bar_width" ]]
    warp_cursor "$((_bar_x + _bar_width - 3))" "$((_bar_y + _bar_height / 2))"

    wait_for 5 "mini status bar cluster overlay appears" \
        '[[ -n "$(cluster_overlay_window)" ]]'

    overlay="$(cluster_overlay_window)"
    echo "# cluster overlay: $overlay" >&3
    read -r overlay_layer overlay_x overlay_y overlay_width _ <<<"$overlay"

    # The layout toggle is the leftmost control in the overlay, safely clear of
    # the top-right testing banner. Quartz bounds and cursor warping both use
    # top-left screen coordinates.
    hover_x=$((overlay_x + 14))
    hover_y=$((overlay_y + 26))
    warp_cursor "$hover_x" "$hover_y"

    wait_for 5 "layout-toggle tooltip panel appears" \
        '[[ -n "$(tooltip_window)" ]]'
    tooltip="$(tooltip_window)"
    echo "# tooltip panel: $tooltip" >&3
    read -r tooltip_layer _ <<<"$tooltip"

    [[ "$tooltip_layer" -gt "$overlay_layer" ]]
    frontmost_app_is_not_hub_bar

    move_cursor_to_main_display_center
    wait_for 5 "tooltip panel hides after pointer exits" \
        '[[ -z "$(tooltip_window)" ]]'

    # Dismiss the cluster overlay so later integration tests start cleanly.
    warp_cursor "$((overlay_x + overlay_width - 13))" "$((overlay_y + 13))"
    swift -e 'import CoreGraphics
let source = CGEventSource(stateID: .hidSystemState)
guard CommandLine.arguments.count == 3,
      let x = Double(CommandLine.arguments[1]),
      let y = Double(CommandLine.arguments[2]) else { exit(2) }
let point = CGPoint(x: x, y: y)
CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)' \
        "$((overlay_x + overlay_width - 13))" "$((overlay_y + 13))"
    wait_for 5 "mini status bar cluster overlay dismisses" \
        '[[ -z "$(cluster_overlay_window)" ]]'
}
