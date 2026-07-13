#!/usr/bin/env bats
# Unit tests for the cluster overlay hot-edge hover zone and hide delay.

@test "cluster overlay hot-edge zone spans all rows, not just row 0" {
    local source_file="$BATS_TEST_DIRNAME/../lib/hub_bar.swift"
    local hot_edge_body
    hot_edge_body="$(sed -n '/let hotEdge = HotEdgeView()/,/^        ])$/p' "$source_file")"

    [[ -n "$hot_edge_body" ]]
    # The bottom anchor must scale with the number of rows actually displayed,
    # otherwise hovering rows 1+ never reveals the overlay.
    [[ "$hot_edge_body" == *'hotEdge.bottomAnchor.constraint(equalTo: cv.topAnchor, constant: rowH * CGFloat(rows))'* ]]
}

@test "cluster overlay hide delay is 15 seconds" {
    local source_file="$BATS_TEST_DIRNAME/../lib/hub_bar.swift"
    local schedule_hide_body
    schedule_hide_body="$(sed -n '/func scheduleHideClusterOverlay()/,/^    }$/p' "$source_file")"

    [[ -n "$schedule_hide_body" ]]
    [[ "$schedule_hide_body" == *'withTimeInterval: 15.0'* ]]
}

@test "cluster overlay uses its own always-on-top tooltip presenter" {
    local source_file="$BATS_TEST_DIRNAME/../lib/hub_bar.swift"

    grep -q 'class OverlayTooltipPresenter' "$source_file"
    grep -q 'level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 2)' "$source_file"
    grep -q 'options: \[.mouseEnteredAndExited, .activeAlways, .inVisibleRect\]' "$source_file"
}

@test "cluster overlay routes every mini control tooltip through presenter" {
    local source_file="$BATS_TEST_DIRNAME/../lib/hub_bar.swift"
    local overlay_body
    overlay_body="$(sed -n '/class ClusterOverlayWindow: NSWindow/,/MARK: – Volume slider target/p' "$source_file")"

    [[ -n "$overlay_body" ]]
    [[ "$overlay_body" != *'.toolTip ='* ]]

    local install_count
    install_count="$(grep -c 'installTooltip(on:' <<<"$overlay_body")"
    [[ "$install_count" -ge 9 ]]
    grep -q 'installTooltip(on: click, text: targetMode == .shrink ? "Switch to compact bar" : "Switch to expanded bar")' <<<"$overlay_body"
}
