#!/usr/bin/env bats
# Integration test: hub install + hub up
#
# Verifies that a full hub install → up cycle leaves sketchybar running with
# hub's config and the clock widget producing a live date/time label.
#
# IMPORTANT: This test WILL:
#   - rm -rf ~/.config/sketchybar and redeploy it
#   - overwrite ~/.aerospace.toml
#   - append an alias to your shell rc (idempotent — guarded by grep)
#   - update ~/.config/hub/hub_path and deploy ~/.config/hub/app_presets.json
#   - reload the running sketchybar and aerospace instances
#   - compile Swift binaries into ~/.config/hub/
#   - copy commands/*.md into ~/.claude/commands/
#   - (hub up) swap the system default browser to HubHTTPHandler
#
# Only run this on a DEDICATED / ISOLATED macOS session (e.g. a test user or
# a standalone test machine). See test/integration/README.md.

# shellcheck disable=SC2034
BATS_TEST_DIRNAME="${BATS_TEST_DIRNAME:-$(dirname "$0")}"
load helpers

setup() {
    require_live_session
}

# No teardown needed: install/up are the normal desired state of the machine.

# ---------------------------------------------------------------------------
@test "hub install exits 0 in non-interactive mode" {
    run env HUB_NONINTERACTIVE=1 "$(hub_bin)" install
    echo "# status: $status" >&3
    echo "# output: $output" >&3
    [[ "$status" -eq 0 ]]
}

# ---------------------------------------------------------------------------
@test "hub up exits 0" {
    run "$(hub_bin)" up
    echo "# status: $status" >&3
    echo "# output: $output" >&3
    [[ "$status" -eq 0 ]]
}

# ---------------------------------------------------------------------------
@test "sketchybar process is running after hub up" {
    pgrep -x sketchybar
}

# ---------------------------------------------------------------------------
@test "sketchybar is configured with hub's config (space items exist)" {
    # Items space.1 through space.9 and space.A are created only by hub's
    # sketchybarrc (the for-loop at ~line 423). Their presence proves
    # sketchybar loaded hub's config, not some foreign config.
    local query
    query="$(sketchybar --query space.1 2>/dev/null)"
    [[ -n "$query" ]]
    # The query result must be valid JSON
    echo "$query" | jq empty
}

# ---------------------------------------------------------------------------
@test "sketchybar clock widget exists" {
    # The clock item is defined in hub's sketchybarrc. Its presence confirms
    # hub's config is loaded.
    local query
    query="$(sketchybar --query clock 2>/dev/null)"
    [[ -n "$query" ]]
    echo "$query" | jq empty
}

# ---------------------------------------------------------------------------
@test "sketchybar clock label contains a live date/time value" {
    # The clock plugin runs every 10s (update_freq=10). After a fresh reload we
    # may need to wait up to one full tick for the label to populate.
    # Format: "Wed 10 Jun 14:30"
    local date_re='^[A-Z][a-z]{2} [0-9]{1,2} [A-Z][a-z]{2} [0-9]{2}:[0-9]{2}$'

    wait_for 20 "clock label is date-like" \
        '[[ "$(sketchybar_label clock)" =~ ^[A-Z][a-z]{2}\ [0-9]{1,2}\ [A-Z][a-z]{2}\ [0-9]{2}:[0-9]{2}$ ]]'

    local lbl
    lbl="$(sketchybar_label clock)"
    echo "# clock label: '$lbl'" >&3
    [[ "$lbl" =~ $date_re ]]
}
