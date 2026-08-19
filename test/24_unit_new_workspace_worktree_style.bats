#!/usr/bin/env bats
# Unit tests for visual distinctions in the new-workspace worktree picker.

@test "root worktree row uses a distinct accent color" {
    local source_file="$BATS_TEST_DIRNAME/../lib/new_workspace_dialog.swift"
    local picker_body
    picker_body="$(<"$source_file")"

    [[ "$picker_body" == *'let rowColor = isRoot ? Theme.Color.accentBlue : Theme.Color.textPrimary'* ]]
    [[ "$picker_body" == *'.foregroundColor: rowColor'* ]]
}
