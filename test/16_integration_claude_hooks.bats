#!/usr/bin/env bats
# Integration tests: Claude hook installation.

load helpers/stubs

REPO_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
HUB_SCRIPT="$REPO_DIR/scripts/hub"

setup() {
    setup_stubs
}

teardown() {
    teardown_stubs
}

@test "claude-hooks install registers StopFailure notification hook" {
    run "$HUB_SCRIPT" claude-hooks install

    [[ "$status" -eq 0 ]]
    [[ -L "$HOME/.claude/hooks/hub-notify.sh" ]]
    [[ -L "$HOME/.claude/hooks/hub-notify-clear.sh" ]]

    jq -e '
      .hooks.StopFailure
      | length == 1
      and .[0].hooks[0].type == "command"
      and .[0].hooks[0].command == "~/.claude/hooks/hub-notify.sh"
      and (.[0] | has("matcher") | not)
    ' "$HOME/.claude/settings.json" >/dev/null
}
