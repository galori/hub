#!/usr/bin/env bats
# Integration test: cropped Hub Bar screenshots
#
# Verifies the crop helper does not leak desktop background pixels from the
# macOS menu-bar/desktop layer when Hub is not in fullscreen mode.

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
    command -v magick >/dev/null 2>&1 || skip "ImageMagick is required for screenshot pixel assertions"
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

greenish_pixel_count() {
    local image_path="$1"
    magick "$image_path" -alpha off -depth 8 txt:- \
        | awk -F'[(),]' '
            /: \(/ {
                r = $2 + 0
                g = $3 + 0
                b = $4 + 0
                if (g >= 150 && r <= 130 && b <= 130 && g - r >= 40 && g - b >= 40) {
                    count++
                }
            }
            END { print count + 0 }
        '
}

@test "screenshot-bar-cropped excludes green desktop background in normal mode" {
    local hub repo_dir green_wallpaper screenshot green_count
    hub="$(hub_bin)"
    repo_dir="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    green_wallpaper="$BATS_TEST_TMPDIR/green-desktop.png"
    screenshot="$BATS_TEST_TMPDIR/hub-bar-cropped.png"

    "$hub" testing-banner start "crop check" >/dev/null 2>&1 && BANNER_STARTED="1" || true

    magick -size 64x64 xc:'#00ff00' "$green_wallpaper"
    set_desktop_picture "$green_wallpaper"
    sleep 1

    run "$hub" fullscreen off
    echo "# status: $status" >&3
    echo "# output: $output" >&3
    [[ "$status" -eq 0 ]]

    wait_for 15 "fullscreen state file is removed" \
        "[[ ! -f '$HOME/.config/hub/fullscreen' ]]"
    wait_for 15 "menu bar is visible in normal mode" \
        "[[ \"\$(menu_bar_auto_hide_value)\" == \"Never\" ]]"

    run "$repo_dir/agents/bin/screenshot-bar-cropped" 30 50 31 70 "$screenshot"
    echo "# status: $status" >&3
    echo "# output: $output" >&3
    [[ "$status" -eq 0 ]]
    [[ -s "$screenshot" ]]

    green_count="$(greenish_pixel_count "$screenshot")"
    echo "# greenish pixels in crop: $green_count" >&3
    [[ "$green_count" -eq 0 ]]
}
