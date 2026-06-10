#!/usr/bin/env bash
# Integration test helpers for the hub live test suite.
#
# These helpers are NOT the stub sandbox (test/helpers/stubs.bash).
# They run against real services — aerospace, sketchybar, jq, git — and
# expect a real, logged-in macOS GUI session.
#
# REQUIRED macOS permissions for the terminal running the tests:
#   - Accessibility:  System Settings → Privacy & Security → Accessibility
#     (required for `aerospace` CLI to query/switch workspaces)
#   - Automation:     System Settings → Privacy & Security → Automation
#     (terminal must be allowed to control System Events / Finder if needed)
#   - A real GUI login session (not SSH headless) — sketchybar and aerospace
#     bind to the WindowServer / loginwindow, so a `loginwindow` session must
#     be active on the display.

# ---------------------------------------------------------------------------
# require_live_session
#
# Call at the top of every @test or setup(). Skips the test with a clear
# message unless HUB_RUN_INTEGRATION=1 AND all required binaries and services
# are present.
# ---------------------------------------------------------------------------
require_live_session() {
    if [[ "${HUB_RUN_INTEGRATION:-}" != "1" ]]; then
        skip "Integration tests are opt-in. Set HUB_RUN_INTEGRATION=1 or run: make test-integration"
    fi

    local missing_tools=()
    for tool in aerospace sketchybar jq git bats; do
        command -v "$tool" &>/dev/null || missing_tools+=("$tool")
    done
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        skip "Required tools not found: ${missing_tools[*]}. Install via brew."
    fi

    # Verify a real GUI session is present by checking that aerospace responds
    if ! aerospace list-workspaces --all &>/dev/null; then
        skip "aerospace is not responding. Ensure AeroSpace is running in a live GUI session."
    fi

    # Verify sketchybar is running
    if ! pgrep -x sketchybar &>/dev/null; then
        skip "sketchybar is not running. Run 'hub up' first."
    fi
}

# ---------------------------------------------------------------------------
# hub_bin
#
# Returns the absolute path to the hub script under this repo.
# ---------------------------------------------------------------------------
hub_bin() {
    local repo_dir
    repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
    echo "$repo_dir/scripts/hub"
}

# ---------------------------------------------------------------------------
# unique_ws_name
#
# Emits a workspace name that is unique per test run to prevent collisions on
# repeated runs: ittest-<epoch>-<random>
# ---------------------------------------------------------------------------
unique_ws_name() {
    echo "ittest-$(date +%s)-${RANDOM}"
}

# ---------------------------------------------------------------------------
# make_fixture_repo <dir> [--with-setup]
#
# Initialises a minimal git repo at <dir> suitable for use with hub new.
#
#   --with-setup   Also write .superset/config.json pointing to a
#                  hub-test-setup.sh script that drops a marker file
#                  (.hub-test-marker) into the worktree's cwd when run.
#
# Git config (name/email) is set locally so we never touch the global config.
# ---------------------------------------------------------------------------
make_fixture_repo() {
    local dir="$1"; shift
    local with_setup=false
    for arg in "$@"; do
        [[ "$arg" == "--with-setup" ]] && with_setup=true
    done

    mkdir -p "$dir"
    git -C "$dir" init -b main
    git -C "$dir" config user.name  "hub-integration-test"
    git -C "$dir" config user.email "hub-integration-test@localhost"

    # Need at least one commit so worktrees can be created off the branch
    echo "# hub integration test fixture" > "$dir/README.md"
    git -C "$dir" add README.md
    git -C "$dir" commit -m "init: hub integration test fixture" --no-gpg-sign

    if [[ "$with_setup" == "true" ]]; then
        mkdir -p "$dir/.superset"
        # setup key must be a relative path from the repo root
        printf '{"setup":["hub-test-setup.sh"]}\n' > "$dir/.superset/config.json"

        # The setup script runs with cwd = the new worktree path.
        # It writes a marker file there so tests can assert it ran.
        cat > "$dir/hub-test-setup.sh" <<'SETUP_EOF'
#!/usr/bin/env bash
# hub integration test post-setup script.
# Runs inside the new worktree (cwd = worktree path).
touch "$PWD/.hub-test-marker"
SETUP_EOF
        chmod +x "$dir/hub-test-setup.sh"

        git -C "$dir" add .superset/config.json hub-test-setup.sh
        git -C "$dir" commit -m "chore: add hub integration test setup hook" --no-gpg-sign
    fi
}

# ---------------------------------------------------------------------------
# ws_id_for_name <name>
#
# Looks up the workspace id assigned to a given workspace name in
# ~/.config/hub/workspaces.json. Exits non-zero if not found.
# ---------------------------------------------------------------------------
ws_id_for_name() {
    local name="$1"
    local wsfile="$HOME/.config/hub/workspaces.json"
    [[ -f "$wsfile" ]] || return 1
    local id
    id="$(jq -r --arg n "$name" '.[] | select(.name == $n) | .workspace_id' "$wsfile" 2>/dev/null)"
    [[ -n "$id" ]] || return 1
    echo "$id"
}

# ---------------------------------------------------------------------------
# sketchybar_label <item>
#
# Returns the current label value for a sketchybar item.
# e.g. sketchybar_label "space.5"  →  "5 my-branch"
#      sketchybar_label "clock"    →  "Wed 10 Jun 14:30"
# ---------------------------------------------------------------------------
sketchybar_label() {
    local item="$1"
    sketchybar --query "$item" 2>/dev/null | jq -r '.label.value // empty'
}

# ---------------------------------------------------------------------------
# sketchybar_drawing <item>
#
# Returns the drawing state ("on" or "off") for a sketchybar item.
# ---------------------------------------------------------------------------
sketchybar_drawing() {
    local item="$1"
    sketchybar --query "$item" 2>/dev/null | jq -r '.geometry.drawing // empty'
}

# ---------------------------------------------------------------------------
# wait_for <timeout_seconds> <description> <eval_expr>
#
# Polls eval_expr every 0.5s until it exits 0, or times out.
# eval_expr is passed to `eval` — keep it simple (a shell test or function call).
#
# Example:
#   wait_for 15 "clock label is date-like" \
#     '[[ "$(sketchybar_label clock)" =~ ^[A-Z][a-z]{2}\ [0-9]{2}\ [A-Z][a-z]{2}\ [0-9]{2}:[0-9]{2}$ ]]'
# ---------------------------------------------------------------------------
wait_for() {
    local timeout="$1"
    local description="$2"
    local expr="$3"
    local elapsed=0

    while [[ "$elapsed" -lt "$timeout" ]]; do
        if eval "$expr" 2>/dev/null; then
            return 0
        fi
        sleep 0.5
        elapsed=$(( elapsed + 1 ))
    done

    echo "wait_for: timed out after ${timeout}s waiting for: ${description}" >&2
    return 1
}

# ---------------------------------------------------------------------------
# cleanup_workspace <id>
#
# Removes a hub workspace by ID using 'hub remove <id> -y'.
# Best-effort: never fails teardown if the workspace was already gone.
# Also performs a direct worktree prune so the git repo is left clean.
# ---------------------------------------------------------------------------
cleanup_workspace() {
    local ws_id="$1"
    [[ -z "$ws_id" ]] && return 0

    local hub
    hub="$(hub_bin)"

    # Look up path before removing (for worktree prune)
    local wsfile="$HOME/.config/hub/workspaces.json"
    local ws_path ws_root
    if [[ -f "$wsfile" ]]; then
        ws_path="$(jq -r --arg id "$ws_id" '.[] | select(.workspace_id == $id) | .path'    "$wsfile" 2>/dev/null || true)"
        ws_root="$(jq -r --arg id "$ws_id" '.[] | select(.workspace_id == $id) | .root_repo' "$wsfile" 2>/dev/null || true)"
    fi

    # hub remove handles json cleanup, sketchybar label reset, and background worktree removal
    "$hub" remove "$ws_id" -y 2>/dev/null || true

    # Give the background worktree removal a moment, then prune to be sure
    if [[ -n "$ws_root" && -d "$ws_root" ]]; then
        sleep 1
        git -C "$ws_root" worktree prune 2>/dev/null || true
        # If the worktree dir is still there (e.g. OUTPUT_WINDOW_BIN not compiled),
        # remove it directly so the fixture temp dir is fully clean.
        if [[ -n "$ws_path" && -d "$ws_path" ]]; then
            git -C "$ws_root" worktree remove "$ws_path" --force 2>/dev/null || true
        fi
    fi
}
