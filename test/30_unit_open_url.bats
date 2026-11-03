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
[ -n "\${FAKE_LAUNCH_STDERR:-}" ] && echo "launch failed for \$*" >&2
sleep "\${FAKE_LAUNCH_DELAY:-0.3}"
n=\$(( \$(cat "\$FAKE_NEXT_ID") + 1 ))
echo "\$n" > "\$FAKE_NEXT_ID"
echo "\$n|\${FAKE_APP:-Browser}|\${FAKE_LAUNCH_WS:-1}" >> "\$FAKE_WINDOWS"
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

    # Three sign-in URLs from separate `aws sso login` runs. Each run has its own
    # state value, so no two are the same URL.
    export SSO_URL_1='https://oidc.us-west-2.amazonaws.com/authorize?response_type=code&state=aaa&code_challenge=c1'
    export SSO_URL_2='https://oidc.us-west-2.amazonaws.com/authorize?response_type=code&state=bbb&code_challenge=c2'
    export SSO_URL_3='https://device.sso.us-west-2.amazonaws.com/?user_code=ABCD-EFGH'

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

# ---------------------------------------------------------------------------
# Query values stay out of the logs
# ---------------------------------------------------------------------------

@test "url_redact keeps scheme, host and path and hides the query" {
    export URL='https://oidc.us-west-2.amazonaws.com/authorize?state=abc&code_challenge=xyz'

    run hub_eval 'url_redact "$URL"'

    [ "$status" -eq 0 ]
    [ "$output" = 'https://oidc.us-west-2.amazonaws.com/authorize?…' ]
}

@test "url_redact drops credentials and fragments" {
    export URL='https://user:pw@x.test:8443/a/b?t=1#frag'
    run hub_eval 'url_redact "$URL"'
    [ "$status" -eq 0 ]
    [ "$output" = 'https://x.test:8443/a/b?…' ]

    export URL='https://x.test/a#section'
    run hub_eval 'url_redact "$URL"'
    [ "$status" -eq 0 ]
    [ "$output" = 'https://x.test/a#…' ]
}

@test "url_redact leaves a URL without query or fragment alone" {
    export URL='https://x.test/a/b'
    run hub_eval 'url_redact "$URL"'
    [ "$status" -eq 0 ]
    [ "$output" = 'https://x.test/a/b' ]

    export URL='https://x.test'
    run hub_eval 'url_redact "$URL"'
    [ "$status" -eq 0 ]
    [ "$output" = 'https://x.test' ]
}

@test "url_redact never prints control characters" {
    export URL=$'https://x.test/a\nFAKE LOG LINE/b?q=1'

    run hub_eval 'url_redact "$URL"'

    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -eq 1 ]
    [ "$output" = 'https://x.test/aFAKE LOG LINE/b?…' ]
}

@test "open-url keeps query values out of hub.log" {
    export URL='https://oidc.us-west-2.amazonaws.com/authorize?state=SECRETSTATE&code_challenge=SECRETCHALLENGE'

    run hub_eval 'cmd_open_url "$URL" 1'

    [ "$status" -eq 0 ]
    grep -qF 'open-url https://oidc.us-west-2.amazonaws.com/authorize?… [' "$HUB_CONFIG_DIR/hub.log"
    grep -Eq 'open-url [^ ]+ \[[0-9a-f]{8}\] \(workspace 1\)' "$HUB_CONFIG_DIR/hub.log"
    grep -qF 'launch Browser on workspace 1:' "$HUB_CONFIG_DIR/hub.log"
    ! grep -q 'SECRETSTATE' "$HUB_CONFIG_DIR/hub.log"
    ! grep -q 'SECRETCHALLENGE' "$HUB_CONFIG_DIR/hub.log"
    # The browser still gets the whole URL.
    grep -qF 'browser-first [https://oidc.us-west-2.amazonaws.com/authorize?state=SECRETSTATE&code_challenge=SECRETCHALLENGE]' "$STUB_CALLS"
}

@test "open-url keeps the URL out of logged launch errors" {
    export FAKE_LAUNCH_STDERR=1
    export URL='https://x.test/cb?token=ab$cd'

    run hub_eval 'cmd_open_url "$URL" 1'

    [ "$status" -eq 0 ]
    grep -q 'launch stderr' "$HUB_CONFIG_DIR/hub.log"
    ! grep -qF 'ab$cd' "$HUB_CONFIG_DIR/hub.log"
    ! grep -qF 'ab%24cd' "$HUB_CONFIG_DIR/hub.log"
}

# ---------------------------------------------------------------------------
# Sign-in URL groups
# ---------------------------------------------------------------------------

# Number of launches that created a browser window (tabs do not count).
count_launches() {
    grep -c -E '^browser-(new|first) ' "$STUB_CALLS" || true
}

# age_group_state <group> <seconds>
# Makes the remembered URLs and window look <seconds> older.
age_group_state() {
    local dir="$HUB_RUNTIME_DIR/url-groups" f
    for f in "$dir/$1.seen" "$dir/$1.window"; do
        [[ -f "$f" ]] || continue
        awk -F'\t' -v OFS='\t' -v n="$2" '{ $1 = $1 - n; print }' "$f" > "$f.aged"
        mv "$f.aged" "$f"
    done
}

@test "shipped rules put AWS IAM Identity Center sign-in URLs in the aws-sso group" {
    local u
    for u in \
        'https://oidc.us-west-2.amazonaws.com/authorize?response_type=code&client_id=abc&state=1' \
        'https://oidc.eu-central-1.amazonaws.com/authorize?x=1' \
        'https://oidc.cn-north-1.amazonaws.com.cn/authorize?x=1' \
        'https://device.sso.us-east-1.amazonaws.com/?user_code=ABCD-EFGH' \
        'https://device.sso.eu-west-1.amazonaws.com/' \
        'HTTPS://OIDC.US-WEST-2.AMAZONAWS.COM/authorize?x=1'; do
        export URL="$u"
        run hub_eval 'url_group_for "$URL"'
        if [[ "$output" != "aws-sso" ]]; then
            echo "expected aws-sso for $u, got: $output" >&2
            return 1
        fi
    done
}

@test "shipped rules leave every other URL, and look-alike hosts, ungrouped" {
    local u
    for u in \
        'https://example.com/' \
        'https://oidc.us-west-2.amazonaws.com/other' \
        'https://oidc.us-west-2.amazonaws.com.evil.test/authorize?x=1' \
        'https://notoidc.us-west-2.amazonaws.com/authorize?x=1' \
        'https://evil.test/?u=https://oidc.us-west-2.amazonaws.com/authorize' \
        'https://oidc.us-west-2.amazonaws.com@evil.test/authorize?x=1' \
        'https://user@oidc.us-west-2.amazonaws.com/authorize?x=1' \
        'https://evil.test\@oidc.us-west-2.amazonaws.com/authorize?x=1' \
        'ftp://oidc.us-west-2.amazonaws.com/authorize?x=1' \
        'not a url'; do
        export URL="$u"
        run hub_eval 'url_group_for "$URL"'
        if [[ -n "$output" ]]; then
            echo "expected no group for $u, got: $output" >&2
            return 1
        fi
    done
}

@test "a rules file in the config dir replaces the shipped rules" {
    echo '{"corp":{"match":[{"host":"^login\\.corp\\.test$"}]}}' > "$HUB_CONFIG_DIR/url_groups.json"

    export URL='https://login.corp.test/start?x=1'
    run hub_eval 'url_group_for "$URL"'
    [ "$output" = "corp" ]

    export URL="$SSO_URL_1"
    run hub_eval 'url_group_for "$URL"'
    [ -z "$output" ]
}

@test "url_group_setting reads a number from the rules and falls back to the default" {
    run hub_eval 'url_group_setting aws-sso dedupe_seconds 99'
    [ "$output" = "30" ]

    echo '{"g":{"dedupe_seconds":5,"reuse_window_seconds":"soon"}}' > "$HUB_CONFIG_DIR/url_groups.json"
    run hub_eval 'url_group_setting g dedupe_seconds 99'
    [ "$output" = "5" ]
    run hub_eval 'url_group_setting g reuse_window_seconds 99'
    [ "$output" = "99" ]
    run hub_eval 'url_group_setting g missing 99'
    [ "$output" = "99" ]
}

@test "a second sign-in URL opens as a tab in the first sign-in window" {
    run hub_eval 'cmd_open_url "$SSO_URL_1" 1'
    [ "$status" -eq 0 ]
    run hub_eval 'cmd_open_url "$SSO_URL_2" 1'
    [ "$status" -eq 0 ]

    [ "$(count_launches)" -eq 1 ]
    grep -qF "browser-first [$SSO_URL_1]" "$STUB_CALLS"
    grep -qF "browser-tab [101] [$SSO_URL_2]" "$STUB_CALLS"
    grep -q 'group aws-sso: opened as a tab in window 101' "$HUB_CONFIG_DIR/hub.log"
}

@test "a device-code sign-in URL joins the same window" {
    run hub_eval 'cmd_open_url "$SSO_URL_1" 1'
    run hub_eval 'cmd_open_url "$SSO_URL_3" 1'

    [ "$(count_launches)" -eq 1 ]
    grep -qF "browser-tab [101] [$SSO_URL_3]" "$STUB_CALLS"
}

@test "the sign-in window follows the user to the current workspace and gets focus" {
    run hub_eval 'cmd_open_url "$SSO_URL_1" 1'
    run hub_eval 'cmd_open_url "$SSO_URL_2" 3'

    grep -qF 'aerospace move-node-to-workspace --window-id 101 3' "$STUB_CALLS"
    # One focus when the window opened, one more when the tab joined it.
    [ "$(grep -c 'aerospace focus --window-id 101' "$STUB_CALLS")" -eq 2 ]
}

@test "the same sign-in URL twice in a row opens once and raises the window" {
    run hub_eval 'cmd_open_url "$SSO_URL_1" 1'
    run hub_eval 'cmd_open_url "$SSO_URL_1" 3'

    [ "$status" -eq 0 ]
    [ "$(count_launches)" -eq 1 ]
    ! grep -q '^browser-tab' "$STUB_CALLS"
    grep -q 'group aws-sso: same URL seen in the last 30s, skipped' "$HUB_CONFIG_DIR/hub.log"
    grep -qF 'aerospace move-node-to-workspace --window-id 101 3' "$STUB_CALLS"
}

@test "the same sign-in URL opens again once the repeat window has passed" {
    run hub_eval 'cmd_open_url "$SSO_URL_1" 1'
    age_group_state aws-sso 100
    run hub_eval 'cmd_open_url "$SSO_URL_1" 1'

    grep -qF "browser-tab [101] [$SSO_URL_1]" "$STUB_CALLS"
}

@test "a sign-in window that is older than the reuse time is not reused" {
    run hub_eval 'cmd_open_url "$SSO_URL_1" 1'
    age_group_state aws-sso 700
    run hub_eval 'cmd_open_url "$SSO_URL_2" 1'

    [ "$(count_launches)" -eq 2 ]
    ! grep -q '^browser-tab' "$STUB_CALLS"
    grep -qF "browser-new [$SSO_URL_2]" "$STUB_CALLS"
}

@test "after the sign-in window is closed the next URL opens a new one that later URLs join" {
    run hub_eval 'cmd_open_url "$SSO_URL_1" 1'
    : > "$FAKE_WINDOWS"
    run hub_eval 'cmd_open_url "$SSO_URL_2" 1'
    run hub_eval 'cmd_open_url "$SSO_URL_3" 1'

    [ "$(count_launches)" -eq 2 ]
    grep -qF "browser-first [$SSO_URL_2]" "$STUB_CALLS"
    grep -qF "browser-tab [102] [$SSO_URL_3]" "$STUB_CALLS"
}

@test "a window of another browser is not reused after slot 2 changes" {
    run hub_eval 'cmd_open_url "$SSO_URL_1" 1'
    cat > "$APPS_FILE" <<'JSON'
[
  {"name":"iTerm2","launch":"echo term"},
  {"name":"Other","launch":"browser-new",
   "url_launch":"browser-new '{url}'",
   "first_url_launch":"browser-first '{url}'",
   "tab_launch":"browser-tab {window_id} '{url}'"}
]
JSON
    export FAKE_APP=Other
    run hub_eval 'cmd_open_url "$SSO_URL_2" 1'

    [ "$(count_launches)" -eq 2 ]
    ! grep -q '^browser-tab' "$STUB_CALLS"
}

@test "a failed tab command falls back to a new window and later URLs join that one" {
    run hub_eval 'cmd_open_url "$SSO_URL_1" 1'
    export FAKE_TAB_RC=1
    run hub_eval 'cmd_open_url "$SSO_URL_2" 1'
    [ "$status" -eq 0 ]

    grep -q '^browser-tab' "$STUB_CALLS"
    [ "$(count_launches)" -eq 2 ]
    grep -q 'could not add a tab to window 101' "$HUB_CONFIG_DIR/hub.log"

    export FAKE_TAB_RC=0
    run hub_eval 'cmd_open_url "$SSO_URL_3" 1'
    grep -qF "browser-tab [102] [$SSO_URL_3]" "$STUB_CALLS"
}

@test "a browser without a tab command gets one window per URL but no repeats" {
    cat > "$APPS_FILE" <<'JSON'
[
  {"name":"iTerm2","launch":"echo term"},
  {"name":"Browser","launch":"browser-new",
   "url_launch":"browser-new '{url}'",
   "first_url_launch":"browser-first '{url}'"}
]
JSON
    run hub_eval 'cmd_open_url "$SSO_URL_1" 1'
    run hub_eval 'cmd_open_url "$SSO_URL_2" 1'
    run hub_eval 'cmd_open_url "$SSO_URL_1" 1'

    [ "$(count_launches)" -eq 2 ]
    ! grep -q '^browser-tab' "$STUB_CALLS"
}

@test "the shipped Safari preset adds the tab through osascript arguments, not script text" {
    cat > "$APPS_FILE" <<'JSON'
[
  {"name":"iTerm2","launch":"echo term"},
  {"name":"Safari","launch":"browser-new",
   "url_launch":"browser-new '{url}'",
   "first_url_launch":"browser-first '{url}'"}
]
JSON
    export FAKE_APP=Safari
    make_fake_tab_command osascript
    export SSO_URL_2='https://oidc.us-west-2.amazonaws.com/authorize?state=b"b&x=$(id)'

    run hub_eval 'cmd_open_url "$SSO_URL_1" 1'
    run hub_eval 'cmd_open_url "$SSO_URL_2" 1'

    local line
    line="$(grep '^osascript ' "$STUB_CALLS")"
    [[ "$line" == *' [--] [https://oidc.us-west-2.amazonaws.com/authorize?state=b%22b&x=%24(id)] [101]' ]]
    # The URL appears once, as an argument; the AppleScript text does not contain it.
    [ "$(grep -o 'oidc' <<< "$line" | wc -l | tr -d ' ')" -eq 1 ]
}

@test "URLs outside every group are opened as before and leave no group state" {
    export URL_A='https://example.com/a?x=1'
    run hub_eval 'cmd_open_url "$URL_A" 1'
    run hub_eval 'cmd_open_url "$URL_A" 1'

    [ "$(count_launches)" -eq 2 ]
    ! grep -q '^browser-tab' "$STUB_CALLS"
    [ ! -e "$HUB_RUNTIME_DIR/url-groups" ]
}

@test "an unreadable rules file does not stop URLs from opening" {
    echo '{ not json' > "$HUB_CONFIG_DIR/url_groups.json"

    run hub_eval 'cmd_open_url "$SSO_URL_1" 1'
    run hub_eval 'cmd_open_url "$SSO_URL_2" 1'

    [ "$status" -eq 0 ]
    [ "$(count_launches)" -eq 2 ]
    grep -q 'url_groups' "$HUB_CONFIG_DIR/hub.log"
}

@test "sign-in URLs that arrive together end up in one window" {
    export FAKE_LAUNCH_DELAY=0.6
    local i
    for i in 1 2 3 4 5 6; do
        (
            export U="https://oidc.us-west-2.amazonaws.com/authorize?state=par$i"
            hub_eval 'cmd_open_url "$U" 1' >/dev/null 2>&1
        ) 3>&- &
    done
    wait

    [ "$(count_launches)" -eq 1 ]
    [ "$(grep -c '^browser-tab' "$STUB_CALLS")" -eq 5 ]
    [ ! -L "$HUB_RUNTIME_DIR/url-groups/aws-sso.lock" ]
}

@test "a lock left by a process that has died is taken over" {
    mkdir -p "$HUB_RUNTIME_DIR/url-groups"
    # macOS process ids stop below 100000, so this one cannot be running.
    ln -s 999999 "$HUB_RUNTIME_DIR/url-groups/aws-sso.lock"

    run hub_eval 'cmd_open_url "$SSO_URL_1" 1'

    [ "$status" -eq 0 ]
    [ "$(count_launches)" -eq 1 ]
    [ ! -L "$HUB_RUNTIME_DIR/url-groups/aws-sso.lock" ]
}

@test "a lock that stays held does not stop the URL from opening" {
    mkdir -p "$HUB_RUNTIME_DIR/url-groups"
    sleep 30 3>&- >/dev/null 2>&1 &
    local holder=$!
    ln -s "$holder" "$HUB_RUNTIME_DIR/url-groups/aws-sso.lock"
    export HUB_URL_GROUP_LOCK_TIMEOUT=1

    run hub_eval 'cmd_open_url "$SSO_URL_1" 1'
    kill "$holder" 2>/dev/null || true

    [ "$status" -eq 0 ]
    [ "$(count_launches)" -eq 1 ]
    grep -q 'could not lock group aws-sso' "$HUB_CONFIG_DIR/hub.log"
    # The lock belongs to another process, so it stays.
    [ -L "$HUB_RUNTIME_DIR/url-groups/aws-sso.lock" ]
}
