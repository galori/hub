#!/usr/bin/env bats
# Integration test: fullscreen revealed menu-bar visual spacing
#
# Verifies the Hub Bar's own top padding remains visible when the auto-hidden
# macOS menu bar is revealed in Hub fullscreen mode. This catches cases where
# AeroSpace padding is correct but the native menu bar still overlaps the Hub Bar.

# shellcheck disable=SC2034
BATS_TEST_DIRNAME="${BATS_TEST_DIRNAME:-$(dirname "$0")}"
load helpers

ORIGINAL_FULLSCREEN_STATE=""
BANNER_STARTED="0"

setup() {
    require_live_session
    require_macos_tahoe_or_newer
    require_imagemagick

    if [[ -f "$HOME/.config/hub/fullscreen" ]]; then
        ORIGINAL_FULLSCREEN_STATE="on"
    else
        ORIGINAL_FULLSCREEN_STATE="off"
    fi
}

teardown() {
    local hub
    hub="$(hub_bin)"

    move_cursor_to_main_display_center >/dev/null 2>&1 || true

    if [[ "$BANNER_STARTED" == "1" ]]; then
        "$hub" testing-banner stop >/dev/null 2>&1 || true
    fi

    if [[ "$ORIGINAL_FULLSCREEN_STATE" == "on" ]]; then
        "$hub" fullscreen on >/dev/null 2>&1 || true
    elif [[ "$ORIGINAL_FULLSCREEN_STATE" == "off" ]]; then
        "$hub" fullscreen off >/dev/null 2>&1 || true
    fi
}

require_macos_tahoe_or_newer() {
    local major
    major="$(sw_vers -productVersion | awk -F. '{print $1}')"
    [[ "$major" -ge 26 ]] || skip "This revealed-menu-bar screenshot assertion is Tahoe-only"
}

require_imagemagick() {
    if ! command -v magick >/dev/null 2>&1; then
        echo "ImageMagick is required for screenshot pixel assertions" >&2
        return 1
    fi
}

non_hub_bar_dark_pixel_count() {
    local image_path="$1"
    magick "$image_path" -alpha off -depth 8 txt:- \
        | awk -F'[(),]' '
            BEGIN {
                # Hub Bar top strip colors from lib/hub_bar.swift:
                # gradient top #1A1C22, gradient bottom #15171C, cluster bg #181A20.
                r1 = 26; g1 = 28; b1 = 34
                r2 = 21; g2 = 23; b2 = 28
                r3 = 24; g3 = 26; b3 = 32
                threshold = 28
            }
            /: \(/ {
                r = $3 + 0
                g = $4 + 0
                b = $5 + 0
                d1 = sqrt((r - r1) ^ 2 + (g - g1) ^ 2 + (b - b1) ^ 2)
                d2 = sqrt((r - r2) ^ 2 + (g - g2) ^ 2 + (b - b2) ^ 2)
                d3 = sqrt((r - r3) ^ 2 + (g - g3) ^ 2 + (b - b3) ^ 2)
                if (d1 > threshold && d2 > threshold && d3 > threshold) {
                    count++
                }
            }
            END { print count + 0 }
        '
}

image_pixel_count() {
    local image_path="$1"
    magick "$image_path" -format '%[fx:w*h]\n' info:
}

fullscreen_revealed_hub_bar_top_y() {
    swift -e 'import Cocoa
let revealedMenuBarHubGap: CGFloat = 4
let tahoeRevealedMenuBarHubGap: CGFloat = 8
let osMajorVersion = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
let effectiveGap = osMajorVersion >= 26 ? tahoeRevealedMenuBarHubGap : revealedMenuBarHubGap
guard let screen = NSScreen.screens.first else { exit(1) }
let sf = screen.frame
let vf = screen.visibleFrame
let visibleInset = sf.maxY - vf.maxY
let inset: CGFloat
if visibleInset > 1 {
    inset = visibleInset
} else if #available(macOS 12.0, *), let left = screen.auxiliaryTopLeftArea, left.height > 1 {
    inset = left.height
} else if #available(macOS 12.0, *), let right = screen.auxiliaryTopRightArea, right.height > 1 {
    inset = right.height
} else {
    let statusBarInset = NSStatusBar.system.thickness
    inset = statusBarInset > 1 ? statusBarInset : 24
}
print(Int(ceil(inset + effectiveGap)))'
}

revealed_hub_bar_top_strip_is_dark() {
    local repo_dir="$1"
    local crop_y1="$2"
    local crop_y2="$3"
    local screenshot="$4"
    local non_dark_count total_count

    "$repo_dir/agents/bin/screenshot-bar-cropped" 320 "$crop_y1" 380 "$crop_y2" "$screenshot" >/dev/null || return 1
    non_dark_count="$(non_hub_bar_dark_pixel_count "$screenshot")"
    total_count="$(image_pixel_count "$screenshot")"
    [[ "$non_dark_count" =~ ^[0-9]+$ && "$total_count" =~ ^[0-9]+$ ]]
    [[ $((non_dark_count * 3)) -le "$total_count" ]]
}

@test "hub-full-screen keeps the Hub Bar top strip visible below the revealed macOS menu bar" {
    local hub repo_dir hub_top crop_y1 crop_y2 screenshot non_dark_count total_count transient_metric
    hub="$(hub_bin)"
    repo_dir="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    screenshot="$BATS_TEST_TMPDIR/revealed-menu-bar-hub-top.png"

    "$hub" testing-banner start "menu spacing" >/dev/null 2>&1 && BANNER_STARTED="1" || true

    move_cursor_to_main_display_center

    run "$hub" fullscreen on
    echo "# status: $status" >&3
    echo "# output: $output" >&3
    [[ "$status" -eq 0 ]]

    wait_for 15 "fullscreen state file exists" \
        "[[ -f '$HOME/.config/hub/fullscreen' ]]"
    wait_for 15 "menu bar auto-hide is enabled" \
        "[[ \"\$(menu_bar_auto_hide_value)\" == \"Always\" ]]"

    move_cursor_to_main_display_top_edge
    wait_for 5 "cursor reaches main display top edge" \
        'cursor_is_at_main_display_top_edge'
    wait_for 15 "Hub Bar has applied revealed menu-bar transient padding" \
        'transient="$(cat "$HOME/.config/hub/hub_bar_height_transient" 2>/dev/null || true)"; [[ "$transient" =~ ^[0-9]+$ && "$transient" -gt 40 ]]'

    hub_top="$(fullscreen_revealed_hub_bar_top_y)"
    transient_metric="$(cat "$HOME/.config/hub/hub_bar_height_transient" 2>/dev/null || true)"
    echo "# expected revealed Hub Bar top=$hub_top transient=$transient_metric" >&3
    [[ "$hub_top" =~ ^[0-9]+$ ]]

    # Sample only the top padding of the Hub Bar. Workspace pills begin lower
    # inside the 40pt row, so this strip should be the dark Hub Bar background.
    crop_y1="$hub_top"
    crop_y2=$((hub_top + 3))

    wait_for 15 "Hub Bar top strip screenshot shows dark background" \
        "revealed_hub_bar_top_strip_is_dark '$repo_dir' '$crop_y1' '$crop_y2' '$screenshot'"

    run "$repo_dir/agents/bin/screenshot-bar-cropped" 320 "$crop_y1" 380 "$crop_y2" "$screenshot"
    echo "# status: $status" >&3
    echo "# output: $output" >&3
    [[ "$status" -eq 0 ]]
    [[ -s "$screenshot" ]]

    non_dark_count="$(non_hub_bar_dark_pixel_count "$screenshot")"
    total_count="$(image_pixel_count "$screenshot")"
    echo "# non-Hub-Bar-dark pixels in top strip: $non_dark_count of $total_count" >&3
    [[ "$non_dark_count" =~ ^[0-9]+$ && "$total_count" =~ ^[0-9]+$ ]]
    [[ $((non_dark_count * 3)) -le "$total_count" ]]
}
