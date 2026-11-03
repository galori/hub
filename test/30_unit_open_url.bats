#!/usr/bin/env bats
# Unit tests for `hub open-url`: URL hardening, log redaction, and sign-in
# URL grouping. Everything runs against stubs; no real browser or AeroSpace.

load helpers/stubs
load helpers/fixtures

REPO_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
HUB="$REPO_DIR/scripts/hub"

# Run Hub shell code under macOS's system bash (3.2). The HTTP handler daemon
# starts `hub open-url` with the minimal PATH Launch Services gives it, so
# `#!/usr/bin/env bash` resolves to /bin/bash there.
hub_eval() {
    local shell=/bin/bash
    [[ -x "$shell" ]] || shell=bash
    "$shell" -c "source '$HUB' >/dev/null 2>&1; $1"
}

# make_fake_launcher <name>
# A browser launch command stub: records its argv as "name [arg] [arg]" and,
# after a short delay, adds a window of app "Browser" to the fake window table.
make_fake_launcher() {
    local name="$1"
    cat > "$STUB_BIN/$name" <<SH
#!/usr/bin/env bash
{
    printf '%s' "$name"
    for a in "\$@"; do printf ' [%s]' "\$a"; done
    printf '\n'
} >> "\$STUB_CALLS"
sleep "\${FAKE_LAUNCH_DELAY:-0.3}"
n=\$(( \$(cat "\$FAKE_NEXT_ID") + 1 ))
echo "\$n" > "\$FAKE_NEXT_ID"
echo "\$n|Browser|\${FAKE_LAUNCH_WS:-1}" >> "\$FAKE_WINDOWS"
SH
    chmod +x "$STUB_BIN/$name"
}

# A tab command stub: records its argv and exits with $FAKE_TAB_RC (default 0).
make_fake_tab_command() {
    local name="$1"
    cat > "$STUB_BIN/$name" <<SH
#!/usr/bin/env bash
{
    printf '%s' "$name"
    for a in "\$@"; do printf ' [%s]' "\$a"; done
    printf '\n'
} >> "\$STUB_CALLS"
exit "\${FAKE_TAB_RC:-0}"
SH
    chmod +x "$STUB_BIN/$name"
}

# AeroSpace stub backed by $FAKE_WINDOWS (lines: id|app|workspace).
make_fake_aerospace() {
    cat > "$STUB_BIN/aerospace" <<'SH'
#!/usr/bin/env bash
echo "aerospace $*" >> "$STUB_CALLS"
if [ "$1" = "list-workspaces" ]; then
    echo "${FAKE_FOCUSED_WS:-1}"
    exit 0
fi
if [ "$1" = "list-windows" ]; then
    fmt=""
    while [ $# -gt 0 ]; do
        [ "$1" = "--format" ] && fmt="$2"
        shift
    done
    while IFS='|' read -r id app ws; do
        [ -z "$id" ] && continue
        out="${fmt//%\{window-id\}/$id}"
        out="${out//%\{app-name\}/$app}"
        out="${out//%\{workspace\}/$ws}"
        echo "$out"
    done < "$FAKE_WINDOWS"
    exit 0
fi
if [ "$1" = "move-node-to-workspace" ]; then
    # move-node-to-workspace --window-id <id> <workspace>
    tmp="$FAKE_WINDOWS.tmp"
    : > "$tmp"
    while IFS='|' read -r id app ws; do
        [ -z "$id" ] && continue
        [ "$id" = "$3" ] && ws="$4"
        echo "$id|$app|$ws" >> "$tmp"
    done < "$FAKE_WINDOWS"
    mv "$tmp" "$FAKE_WINDOWS"
    exit 0
fi
exit 0
SH
    chmod +x "$STUB_BIN/aerospace"
}

setup() {
    setup_stubs
    export STUB_CALLS="$HOME/stub_calls"
    export FAKE_WINDOWS="$HOME/fake_windows"
    export FAKE_NEXT_ID="$HOME/fake_next_id"
    : > "$STUB_CALLS"
    : > "$FAKE_WINDOWS"
    echo 100 > "$FAKE_NEXT_ID"

    make_fake_aerospace
    make_fake_launcher browser-new
    make_fake_launcher browser-first
    make_fake_tab_command browser-tab

    # Slot 2 is the browser. first_url_launch quotes {url} with double quotes,
    # like the shipped Safari preset does.
    cat > "$APPS_FILE" <<'JSON'
[
  {"name":"iTerm2","launch":"echo term"},
  {"name":"Browser","launch":"browser-new",
   "url_launch":"browser-new '{url}'",
   "first_url_launch":"browser-first \"{url}\"",
   "tab_launch":"browser-tab {window_id} '{url}'"}
]
JSON
}

teardown() {
    teardown_stubs
}

# ---------------------------------------------------------------------------
# Shell and AppleScript safety of the URL
# ---------------------------------------------------------------------------

@test "url_encode_for_launch encodes characters that are special inside launch-template quotes" {
    export URL=$'https://x.test/a b?q="1"&r=\'2\'&s=$(id)&t=`id`&u=a\\b&p=100%25&v=(x)'

    run hub_eval 'url_encode_for_launch "$URL"'

    [ "$status" -eq 0 ]
    [ "$output" = 'https://x.test/a%20b?q=%221%22&r=%272%27&s=%24(id)&t=%60id%60&u=a%5Cb&p=100%25&v=(x)' ]
}

@test "url_encode_for_launch leaves an ordinary URL unchanged" {
    export URL='https://github.com/org/repo/pull/12?diff=split&w=1#discussion_r5'

    run hub_eval 'url_encode_for_launch "$URL"'

    [ "$status" -eq 0 ]
    [ "$output" = "$URL" ]
}

@test "url_encode_for_launch rejects control characters" {
    export URL=$'https://x.test/\nrm'

    run hub_eval 'url_encode_for_launch "$URL"'

    [ "$status" -ne 0 ]
}

@test "open-url does not run command substitution from a URL in a double-quoted launch template" {
    export URL='https://x.test/?a=$(touch '"$HOME"'/pwned)'

    run hub_eval 'cmd_open_url "$URL" 1'

    [ "$status" -eq 0 ]
    [ ! -e "$HOME/pwned" ]
    grep -qF "browser-first [https://x.test/?a=%24(touch%20$HOME/pwned)]" "$STUB_CALLS"
}

@test "open-url keeps double quotes and backslashes out of a quoted launch template" {
    echo "50|Browser|1" > "$FAKE_WINDOWS"
    export URL='https://x.test/?q="x"&y=\z'

    run hub_eval 'cmd_open_url "$URL" 1'

    [ "$status" -eq 0 ]
    grep -qF 'browser-new [https://x.test/?q=%22x%22&y=%5Cz]' "$STUB_CALLS"
}

@test "open-url refuses a URL with control characters" {
    export URL=$'https://x.test/\nrm'

    run hub_eval 'cmd_open_url "$URL" 1'

    [ "$status" -ne 0 ]
    ! grep -q '^browser-' "$STUB_CALLS"
}
