#!/usr/bin/env bats
# Integration test: cropped Hub Bar screenshots
#
# Verifies the crop helper does not leak a sliver of desktop wallpaper
# between the macOS menu bar and the Hub Bar when Hub is not in fullscreen
# mode. The crop region should show only the solid-ish Hub Bar/menu-bar
# strips, never the colorful (unblurred) wallpaper peeking through.

# shellcheck disable=SC2034
BATS_TEST_DIRNAME="${BATS_TEST_DIRNAME:-$(dirname "$0")}"
load helpers

ORIGINAL_FULLSCREEN_STATE=""
ORIGINAL_DESKTOP_PICTURES=""
BANNER_STARTED="0"

setup() {
    require_live_session
    require_macos_sequoia
    require_imagemagick

    ORIGINAL_DESKTOP_PICTURES="$BATS_TEST_TMPDIR/original_desktop_pictures.txt"
    save_desktop_pictures "$ORIGINAL_DESKTOP_PICTURES"

    if [[ -f "$HOME/.config/hub/fullscreen" ]]; then
        ORIGINAL_FULLSCREEN_STATE="on"
    else
        ORIGINAL_FULLSCREEN_STATE="off"
    fi
}

teardown() {
    local hub
    hub="$(hub_bin)"

    if [[ "$BANNER_STARTED" == "1" ]]; then
        "$hub" testing-banner stop >/dev/null 2>&1 || true
    fi

    if [[ -n "$ORIGINAL_DESKTOP_PICTURES" && -f "$ORIGINAL_DESKTOP_PICTURES" ]]; then
        restore_desktop_pictures "$ORIGINAL_DESKTOP_PICTURES" || true
    fi

    if [[ "$ORIGINAL_FULLSCREEN_STATE" == "on" ]]; then
        "$hub" fullscreen on >/dev/null 2>&1 || true
    elif [[ "$ORIGINAL_FULLSCREEN_STATE" == "off" ]]; then
        "$hub" fullscreen off >/dev/null 2>&1 || true
    fi
}

require_macos_sequoia() {
    local major
    major="$(sw_vers -productVersion | awk -F. '{print $1}')"
    [[ "$major" == "15" ]] || skip "This screenshot-background assertion only applies to macOS Sequoia"
}

require_imagemagick() {
    if ! command -v magick >/dev/null 2>&1; then
        echo "ImageMagick is required for screenshot pixel assertions" >&2
        return 1
    fi
}

save_desktop_pictures() {
    local out="$1"
    osascript <<'APPLESCRIPT' > "$out"
set oldDelimiters to AppleScript's text item delimiters
set AppleScript's text item delimiters to linefeed
set paths to {}
tell application "System Events"
    repeat with i from 1 to count of desktops
        set p to ""
        try
            set p to picture of desktop i as text
        end try
        set end of paths to p
    end repeat
end tell
set joinedPaths to paths as text
set AppleScript's text item delimiters to oldDelimiters
return joinedPaths
APPLESCRIPT
}

restore_desktop_pictures() {
    local source_file="$1"
    osascript - "$source_file" <<'APPLESCRIPT'
on run argv
    set sourceFile to POSIX file (item 1 of argv)
    set rawPaths to read sourceFile
    set oldDelimiters to AppleScript's text item delimiters
    set AppleScript's text item delimiters to linefeed
    set paths to text items of rawPaths
    set AppleScript's text item delimiters to oldDelimiters

    tell application "System Events"
        repeat with i from 1 to count of desktops
            if i <= count of paths then
                set p to item i of paths
                if p is not "" then
                    try
                        set picture of desktop i to p
                    end try
                end if
            end if
        end repeat
    end tell
end run
APPLESCRIPT
}

set_desktop_picture() {
    local image_path="$1"
    osascript - "$image_path" <<'APPLESCRIPT'
on run argv
    set imagePath to item 1 of argv
    tell application "System Events"
        repeat with i from 1 to count of desktops
            set picture of desktop i to imagePath
        end repeat
    end tell
end run
APPLESCRIPT
}

non_solid_pixel_count() {
    local image_path="$1"
    magick "$image_path" -alpha off -depth 8 txt:- \
        | awk -F'[(),]' '
            BEGIN {
                # Expected solid-ish strip colors sampled with Digital Color
                # Meter against the Hub Bar over the Sequoia Sunrise wallpaper:
                # #4A4F44, #333538, #1A1B20 (decimal; awk on macOS does not
                # reliably parse 0x hex literals in source).
                r1 = 74; g1 = 79; b1 = 68
                r2 = 51; g2 = 53; b2 = 56
                r3 = 26; g3 = 27; b3 = 32
                threshold = 45
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

@test "screenshot-bar-cropped shows only solid strips, no wallpaper sliver, over Sequoia Sunrise" {
    local hub repo_dir wallpaper screenshot non_solid_count
    hub="$(hub_bin)"
    repo_dir="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    wallpaper="/System/Library/Desktop Pictures/.wallpapers/Sequoia Sunrise/Sequoia Sunrise.heic"
    screenshot="$BATS_TEST_TMPDIR/hub-bar-cropped.png"

    [[ -f "$wallpaper" ]] || skip "Sequoia Sunrise wallpaper not present on this system"

    "$hub" testing-banner start "crop check" >/dev/null 2>&1 && BANNER_STARTED="1" || true

    set_desktop_picture "$wallpaper"
    sleep 1

    run "$hub" fullscreen off
    echo "# status: $status" >&3
    echo "# output: $output" >&3
    [[ "$status" -eq 0 ]]

    wait_for 15 "fullscreen state file is removed" \
        "[[ ! -f '$HOME/.config/hub/fullscreen' ]]"
    wait_for 15 "menu bar is visible in normal mode" \
        "[[ \"\$(menu_bar_auto_hide_value)\" == \"Never\" ]]"

    run "$repo_dir/agents/bin/screenshot-bar-cropped" 430 40 490 70 "$screenshot"
    echo "# status: $status" >&3
    echo "# output: $output" >&3
    [[ "$status" -eq 0 ]]
    [[ -s "$screenshot" ]]

    non_solid_count="$(non_solid_pixel_count "$screenshot")"
    echo "# non-solid (wallpaper sliver) pixels in crop: $non_solid_count" >&3
    [[ "$non_solid_count" -eq 0 ]]
}
