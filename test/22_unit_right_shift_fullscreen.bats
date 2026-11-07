#!/usr/bin/env bats

@test "fullscreen gestures run AeroSpace fullscreen on a bounded worker" {
    local source_file="$BATS_TEST_DIRNAME/../lib/hub_hotkeyd.swift"

    grep -Fq 'process.arguments = ["fullscreen"]' "$source_file"
    grep -Fq 'fullscreenGate.wait(timeout: .now())' "$source_file"
    grep -Fq 'exited.wait(timeout: .now() + 2)' "$source_file"
    ! grep -Fq 'triggerFullscreenToggle' "$BATS_TEST_DIRNAME/../lib/hub_bar.swift"
}
