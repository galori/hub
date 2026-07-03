#!/usr/bin/env bats
# Integration test: hub install + hub up
#
# Verifies that a full hub install → up cycle leaves the native bar and
# AeroSpace running correctly.
#
# IMPORTANT: This test WILL:
#   - overwrite ~/.aerospace.toml
#   - append an alias to your shell rc (idempotent — guarded by grep)
#   - update ~/.config/hub/hub_path and deploy ~/.config/hub/app_presets.json
#   - reload the running bar and aerospace instances
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
@test "hub_bar process is running after hub up" {
    pgrep -f "hub_bar" >/dev/null
}

# ---------------------------------------------------------------------------
@test "hub_bar_labels file exists after hub up" {
    [[ -f "$(hub_bar_labels_file)" ]]
}
