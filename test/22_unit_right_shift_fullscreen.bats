#!/usr/bin/env bats

@test "right-shift double-tap triggers AeroSpace fullscreen" {
    local source_file="$BATS_TEST_DIRNAME/../lib/hub_bar.swift"
    local trigger_body
    trigger_body="$(sed -n '/private func triggerFullscreenToggle()/,/^    }/p' "$source_file")"

    [[ "$trigger_body" == *'arguments: ["fullscreen"]'* ]]
    [[ "$trigger_body" != *'hubScriptPath()'* ]]
}
