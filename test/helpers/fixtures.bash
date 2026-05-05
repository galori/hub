# Shared test fixtures for hub bats tests.
# Source this after helpers/stubs in setup().
#
# All fixtures assume $HOME is the isolated test dir (set by setup_stubs) and
# write files into $HOME/.config/hub/ or $HOME/.config/sketchybar/.

# seed_workspaces <id:name:path[:root_repo]>...
# Writes workspaces.json with the given entries. Omit root_repo to default to path.
# Example: seed_workspaces "1:Alpha:/tmp/alpha" "2:Beta:/tmp/beta" "Z:General:/tmp:"
seed_workspaces() {
    local file="$HOME/.config/hub/workspaces.json"
    local entries=()
    for spec in "$@"; do
        local id name path root
        IFS=':' read -r id name path root <<< "$spec"
        root="${root:-$path}"
        entries+=("$(printf '{"name":"%s","path":"%s","root_repo":"%s","workspace_id":"%s"}' \
            "$name" "$path" "$root" "$id")")
    done
    local joined
    joined="$(IFS=,; echo "${entries[*]}")"
    printf '[%s]\n' "$joined" > "$file"
}

# seed_apps <name:launch[:icon]>...
# Writes apps.json with the given app slots.
# Example: seed_apps "iTerm2:echo it {path}" "Chrome:echo chrome:Google Chrome"
seed_apps() {
    local file="$HOME/.config/hub/apps.json"
    local entries=()
    for spec in "$@"; do
        local name launch icon
        IFS=':' read -r name launch icon <<< "$spec"
        icon="${icon:-$name}"
        entries+=("$(printf '{"name":"%s","launch":"%s","icon":"%s"}' \
            "$name" "$launch" "$icon")")
    done
    local joined
    joined="$(IFS=,; echo "${entries[*]}")"
    printf '[%s]\n' "$joined" > "$file"
}

# mock_aerospace_windows <ws_id> <wid1> <wid2> ...
# Installs an aerospace stub that reports the given window IDs for the given
# workspace (via --format '%{window-id}'). Other aerospace subcommands become
# no-ops returning 0. Does NOT record calls — combine with mock_aerospace_recording
# if you need call assertions too.
mock_aerospace_windows() {
    local ws_id="$1"; shift
    local wids=("$@")
    local wid_lines
    wid_lines="$(printf '%s\n' "${wids[@]}")"
    cat > "$STUB_BIN/aerospace" <<SH
#!/usr/bin/env bash
case "\$*" in
    "list-workspaces --focused") echo "$ws_id" ;;
    "list-windows --workspace $ws_id --format %{window-id}") cat <<WIDS
$wid_lines
WIDS
    ;;
    *) exit 0 ;;
esac
SH
    chmod +x "$STUB_BIN/aerospace"
}

# mock_aerospace_recording <ws_id> <wid1> <wid2> ...
# Like mock_aerospace_windows, but also appends every invocation to $STUB_CALLS
# so tests can assert on the command sequence.
mock_aerospace_recording() {
    local ws_id="$1"; shift
    local wids=("$@")
    local wid_lines
    wid_lines="$(printf '%s\n' "${wids[@]}")"
    : "${STUB_CALLS:=$HOME/stub_calls}"
    cat > "$STUB_BIN/aerospace" <<SH
#!/usr/bin/env bash
echo "aerospace \$*" >> "$STUB_CALLS"
case "\$*" in
    "list-workspaces --focused") echo "$ws_id" ;;
    "list-windows --workspace $ws_id --format %{window-id}") cat <<WIDS
$wid_lines
WIDS
    ;;
    *) exit 0 ;;
esac
SH
    chmod +x "$STUB_BIN/aerospace"
    export STUB_CALLS
}

# mock_spatial_order <wid1> <wid2> ...
# Stubs SPATIAL_ORDER_BIN to return the given wids in order (one per line),
# regardless of input args. Used to simulate a known spatial layout.
mock_spatial_order() {
    local bin="$HOME/.config/hub/spatial_order"
    local wid_lines
    wid_lines="$(printf '%s\n' "$@")"
    mkdir -p "$(dirname "$bin")"
    cat > "$bin" <<SH
#!/usr/bin/env bash
cat <<WIDS
$wid_lines
WIDS
SH
    chmod +x "$bin"
}

# assert_called <pattern>
# Greps $STUB_CALLS for a matching line. Fails the test with a clear message
# if not found. Pattern is passed to grep as a basic regex.
assert_called() {
    local pattern="$1"
    : "${STUB_CALLS:=$HOME/stub_calls}"
    if ! grep -q "$pattern" "$STUB_CALLS" 2>/dev/null; then
        echo "assert_called: pattern not found: $pattern" >&2
        echo "=== $STUB_CALLS ===" >&2
        cat "$STUB_CALLS" 2>/dev/null >&2 || echo "(no calls recorded)" >&2
        return 1
    fi
}

# assert_not_called <pattern>
# Inverse of assert_called.
assert_not_called() {
    local pattern="$1"
    : "${STUB_CALLS:=$HOME/stub_calls}"
    if grep -q "$pattern" "$STUB_CALLS" 2>/dev/null; then
        echo "assert_not_called: pattern unexpectedly found: $pattern" >&2
        echo "=== $STUB_CALLS ===" >&2
        cat "$STUB_CALLS" 2>/dev/null >&2
        return 1
    fi
}

# count_calls <pattern>
# Prints the number of matching call lines.
count_calls() {
    local pattern="$1"
    : "${STUB_CALLS:=$HOME/stub_calls}"
    grep -c "$pattern" "$STUB_CALLS" 2>/dev/null || echo 0
}
