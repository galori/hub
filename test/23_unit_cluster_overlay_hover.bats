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
