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
    grep -q 'class OverlayTooltipAttachment: NSResponder' "$source_file"
    grep -q 'level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 2)' "$source_file"
    grep -q 'options: \[.mouseEnteredAndExited, .activeAlways, .inVisibleRect\]' "$source_file"
}

@test "click views preserve tooltip-owned tracking areas during layout" {
    local hub_source="$BATS_TEST_DIRNAME/../lib/hub_bar.swift"
    local theme_source="$BATS_TEST_DIRNAME/../lib/theme.swift"
    local hub_click_body theme_click_body

    hub_click_body="$(sed -n '/class HubBarClickView: NSView/,/MARK: – OverlayTooltipPresenter/p' "$hub_source")"
    theme_click_body="$(sed -n '/class ClickView: NSView/,/^}/p' "$theme_source")"

    [[ "$hub_click_body" == *'private var hoverTrackingArea: NSTrackingArea?'* ]]
    [[ "$theme_click_body" == *'private var hoverTrackingArea: NSTrackingArea?'* ]]
    [[ "$hub_click_body" != *'trackingAreas.forEach'* ]]
    [[ "$theme_click_body" != *'trackingAreas.forEach'* ]]
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
    grep -q 'installTooltip(on: click, text: useful' <<<"$overlay_body"
}

@test "mini status uses native symbols and resource-pressure thresholds" {
    local source_file="$BATS_TEST_DIRNAME/../lib/hub_bar.swift"

    grep -q 'makeSymbolImageView(systemName:' "$source_file"
    grep -q 'fileURLWithPath: "/usr/bin/memory_pressure"' "$source_file"
    grep -q 'process.arguments = \["-Q"\]' "$source_file"
    grep -q 'func cpuResourceColor(pct: Int)' "$source_file"
    grep -q 'func memoryResourceColor(pct: Int)' "$source_file"
    ! grep -q 'labelWithString: "󰆚"' "$source_file"
    ! grep -q 'labelWithString: "󰍛"' "$source_file"
}

@test "mini status includes available disk space next to memory" {
    local source_file="$BATS_TEST_DIRNAME/../lib/hub_bar.swift"
    local build_body
    build_body="$(sed -n '/buildCPUInto(stack)/,/buildVolumeInto(stack)/p' "$source_file")"

    [[ "$build_body" == *'buildCPUInto(stack)'* ]]
    [[ "$build_body" == *'buildMemInto(stack)'* ]]
    [[ "$build_body" == *'buildDiskInto(stack)'* ]]
    grep -q 'systemName: "internaldrive"' "$source_file"
    grep -q 'text: "Available disk space"' "$source_file"
    grep -q 'func availableDiskSpace()' "$source_file"
    grep -Fq 'diskLabel?.stringValue = "\(disk.text) (\(disk.percent)%)"' "$source_file"
}

@test "action controls and layout toggle use available overlay space" {
    local source_file="$BATS_TEST_DIRNAME/../lib/hub_bar.swift"
    local action_body toggle_body
    action_body="$(sed -n '/class ActionSlotView:/,/MARK: – WsWinSlotView/p' "$source_file")"
    toggle_body="$(sed -n '/Layout mode toggle/,/App icon group/p' "$source_file")"

    [[ "$action_body" != *'min(width, 58)'* ]]
    [[ "$toggle_body" == *'click.layer?.borderWidth = 1'* ]]
    [[ "$toggle_body" == *'layoutToggleIsUseful'* ]]
}
