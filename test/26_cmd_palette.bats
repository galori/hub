#!/usr/bin/env bats
# Stubbed command tests for cmd_palette: the command palette modal reports a
# chosen workspace_id (or nothing, on cancel), and hub switches AeroSpace to
# that workspace exactly like Alt-<id> would.

load helpers/stubs

REPO_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
HUB="$REPO_DIR/scripts/hub"

setup() {
    setup_stubs

    export WORKSPACES_FILE="$HOME/.config/hub/workspaces.json"
    export STUB_CALLS="$HOME/stub_calls"
    export COMMAND_PALETTE_RESULT="$HUB_RUNTIME_DIR/command-palette-result"

    cat > "$WORKSPACES_FILE" <<'JSON'
[{"name":"dgapp","path":"/tmp/dgapp","root_repo":"/tmp/dgapp","workspace_id":"1"},
 {"name":"cyera-taxonomy","path":"/tmp/cyera","root_repo":"/tmp/cyera","workspace_id":"5"}]
JSON

    cat > "$STUB_BIN/aerospace" <<'SH'
#!/usr/bin/env bash
echo "aerospace $*" >> "${STUB_CALLS:-/tmp/stub_calls}"
exit 0
SH
    chmod +x "$STUB_BIN/aerospace"

    # Fake compiled binary: the real one is a Cocoa modal we can't drive in
    # CI, so this stub stands in for "the user picked an item" by writing
    # whatever $FAKE_PALETTE_RESULT holds straight to COMMAND_PALETTE_RESULT.
    cat > "$STUB_BIN/command_palette" <<'SH'
#!/usr/bin/env bash
if [[ -n "${FAKE_PALETTE_RESULT:-}" ]]; then
    printf '%s' "$FAKE_PALETTE_RESULT" > "$COMMAND_PALETTE_RESULT"
fi
exit 0
SH
    chmod +x "$STUB_BIN/command_palette"
    export COMMAND_PALETTE_BIN="$STUB_BIN/command_palette"
}

teardown() {
    teardown_stubs
}

@test "cmd_palette switches to the selected workspace" {
    export FAKE_PALETTE_RESULT="5"
    run "$HUB" palette
    [[ "$status" -eq 0 ]]
    grep -q "aerospace workspace 5" "$STUB_CALLS"
}

@test "cmd_palette does nothing when the modal is cancelled" {
    unset FAKE_PALETTE_RESULT
    run "$HUB" palette
    [[ "$status" -eq 0 ]]
    [[ ! -f "$STUB_CALLS" ]] || ! grep -q "aerospace workspace" "$STUB_CALLS"
}

@test "cmd_palette is a no-op when the binary is missing" {
    export COMMAND_PALETTE_BIN="$STUB_BIN/does-not-exist"
    run "$HUB" palette
    [[ "$status" -eq 0 ]]
}

@test "cmd_palette clears any stale result file before running the modal" {
    echo "1" > "$COMMAND_PALETTE_RESULT"
    unset FAKE_PALETTE_RESULT
    run "$HUB" palette
    [[ "$status" -eq 0 ]]
    [[ ! -f "$STUB_CALLS" ]] || ! grep -q "aerospace workspace" "$STUB_CALLS"
}
