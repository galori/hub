# Helpers for `hub open-url`. Sourced by scripts/hub.
#
# The URL is untrusted input: any app on the machine can ask the HTTP handler
# to open any string, and the handler passes it on to `hub open-url`.
#
# Must stay bash 3.2 compatible. The HTTP handler daemon starts `hub open-url`
# with the minimal PATH that Launch Services gives it, so `#!/usr/bin/env bash`
# resolves to /bin/bash.

# url_encode_for_launch URL
# Prints URL with the characters that are special inside the quotes of a launch
# template percent-encoded. Launch templates are run through `bash -c`, and the
# shipped Safari templates also put the URL inside an AppleScript string, so a
# URL such as https://x.test/?a=$(cmd) must not reach them as it is.
# Returns 1 for a URL with control characters (a newline has no place in one).
url_encode_for_launch() {
    local url="$1"
    case "$url" in
        *[[:cntrl:]]*) return 1 ;;
    esac
    url="${url//\"/%22}"
    url="${url//\'/%27}"
    url="${url//\`/%60}"
    url="${url//\$/%24}"
    url="${url//\\/%5C}"
    url="${url// /%20}"
    printf '%s' "$url"
}

# url_redact URL
# Prints URL as scheme://host[:port]/path, followed by "?…" or "#…" when a
# query or fragment was cut. Sign-in and magic-link URLs carry one-time codes
# and tokens in the query, which must not end up in logs or on screen.
url_redact() {
    local url="$1" base marker="" rest after authority path scheme
    # A newline in the URL must not start a forged log line.
    url="${url//[[:cntrl:]]/}"
    base="${url%%[?#]*}"
    rest="${url#"$base"}"
    case "$rest" in
        \?*) marker='?…' ;;
        \#*) marker='#…' ;;
    esac
    case "$base" in
        *://*)
            scheme="${base%%://*}"
            after="${base#*://}"
            authority="${after%%/*}"
            path=""
            if [[ "$after" == */* ]]; then
                path="/${after#*/}"
            fi
            authority="${authority##*@}"
            base="$scheme://$authority$path"
            ;;
    esac
    printf '%s%s' "${base:0:300}" "$marker"
}

# url_hash URL
# Prints the SHA-256 of URL. Logs show the first 8 characters so entries about
# one URL can be matched without revealing it.
url_hash() {
    printf '%s' "$1" | shasum -a 256 | awk '{print $1}'
}

# --- URL groups --------------------------------------------------------------
# A group is a set of pages that belong together, such as the sign-in pages
# `aws sso login` opens. When a machine's AWS session ends, every tool that
# needs it runs its own login, and each one opens its own browser window. A
# group opens one window and adds later pages to it as tabs.
#
# Groups come from url_groups.json (shipped in config/, replaceable by a file
# of the same name in the Hub config dir).

# url_groups_file
# Prints the path of the rules file, or returns 1 if there is none.
url_groups_file() {
    local file
    for file in "$HUB_CONFIG_DIR/url_groups.json" "$CONFIG_DIR/url_groups.json"; do
        if [[ -f "$file" ]]; then
            printf '%s' "$file"
            return 0
        fi
    done
    return 1
}

# url_group_for URL
# Prints the name of the group that URL belongs to, or nothing. Only http and
# https URLs with a plain host (and optional port) match. A URL with
# credentials, or with other characters before the path, never does: a browser
# and this parser could disagree about which host it points to.
# Always returns 0, so an unreadable rules file only means "no group".
url_group_for() {
    local url="$1" re file scheme host path out
    re='^([A-Za-z][A-Za-z0-9+.-]*)://([A-Za-z0-9.-]+)(:[0-9]+)?(/[^?#]*)?([?#].*)?$'
    if ! [[ "$url" =~ $re ]]; then
        return 0
    fi
    scheme="$(printf '%s' "${BASH_REMATCH[1]}" | tr '[:upper:]' '[:lower:]')"
    host="$(printf '%s' "${BASH_REMATCH[2]}" | tr '[:upper:]' '[:lower:]')"
    path="${BASH_REMATCH[4]}"
    if [[ -z "$path" ]]; then
        path="/"
    fi
    case "$scheme" in
        http|https) ;;
        *) return 0 ;;
    esac
    file="$(url_groups_file)" || return 0
    if ! out="$(jq -r --arg host "$host" --arg path "$path" '
        first(
            to_entries[]
            | select(
                (.key | test("^[A-Za-z0-9._-]+$"))
                and ((.value.match // []) | any(.[];
                    ((.host // "") as $h | ($h == "" or ($host | test($h))))
                    and ((.path // "") as $p | ($p == "" or ($path | test($p))))))
            )
            | .key
        )' "$file" 2>/dev/null)"; then
        hub_log "ERR" "url_groups: cannot read the rules in $file"
        return 0
    fi
    printf '%s' "$out"
}

# url_group_setting GROUP KEY DEFAULT
# Prints a whole-number setting of GROUP from the rules, or DEFAULT.
url_group_setting() {
    local group="$1" key="$2" default="$3" file value=""
    if file="$(url_groups_file)"; then
        value="$(jq -r --arg g "$group" --arg k "$key" '.[$g][$k] // empty' "$file" 2>/dev/null || true)"
    fi
    case "$value" in
        ''|*[!0-9]*) printf '%s' "$default" ;;
        *) printf '%s' "$value" ;;
    esac
}

# Where the groups keep what they know: recent URLs, the group's window, a lock.
_url_group_dir() {
    printf '%s/url-groups' "$HUB_RUNTIME_DIR"
}

# url_group_lock_acquire GROUP
# Waits for the group's lock. Many tools open their sign-in pages at the same
# moment, and without the lock each of them would see "no window yet". The lock
# is a symlink to the holder's pid: ln -s fails if the name exists, so taking it
# is atomic and the pid is in place from the first instant.
# Returns 1 if the lock could not be taken in HUB_URL_GROUP_LOCK_TIMEOUT
# seconds (default 60); the caller then opens the URL without the group.
url_group_lock_acquire() {
    local group="$1" dir lock timeout deadline
    dir="$(_url_group_dir)"
    lock="$dir/$group.lock"
    timeout="${HUB_URL_GROUP_LOCK_TIMEOUT:-60}"
    case "$timeout" in
        ''|*[!0-9]*) timeout=60 ;;
    esac
    mkdir -p "$dir" 2>/dev/null || return 1
    deadline=$(( SECONDS + timeout ))
    while ! ln -s "$$" "$lock" 2>/dev/null; do
        _url_group_lock_clear_stale "$lock"
        if [[ "$SECONDS" -ge "$deadline" ]]; then
            return 1
        fi
        sleep 0.1
    done
    return 0
}

# Removes LOCK if its holder died, or if it is far older than any open takes.
_url_group_lock_clear_stale() {
    local lock="$1" holder mtime now
    holder="$(readlink "$lock" 2>/dev/null || true)"
    if [[ -z "$holder" ]]; then
        return 0
    fi
    case "$holder" in
        *[!0-9]*)
            rm -f "$lock"
            return 0
            ;;
    esac
    if ! kill -0 "$holder" 2>/dev/null; then
        rm -f "$lock"
        return 0
    fi
    mtime="$(stat -f %m "$lock" 2>/dev/null || echo 0)"
    now="$(date +%s)"
    if [[ "$mtime" =~ ^[0-9]+$ ]]; then
        if [[ $(( now - mtime )) -gt 300 ]]; then
            rm -f "$lock"
        fi
    fi
    return 0
}

# url_group_lock_release GROUP
# Releases the lock if this process holds it.
url_group_lock_release() {
    local lock
    lock="$(_url_group_dir)/$1.lock"
    if [[ "$(readlink "$lock" 2>/dev/null || true)" == "$$" ]]; then
        rm -f "$lock"
    fi
    return 0
}

# url_group_seen_recently GROUP HASH SECONDS
# Returns 0 if the URL with this hash was opened in the last SECONDS seconds.
# Only hashes are kept, so the remembered URLs cannot be read back.
url_group_seen_recently() {
    local file hash="$2" ttl="$3" now ts h
    file="$(_url_group_dir)/$1.seen"
    if [[ ! -f "$file" ]]; then
        return 1
    fi
    now="$(date +%s)"
    while IFS=$'\t' read -r ts h; do
        case "$ts" in
            ''|*[!0-9]*) continue ;;
        esac
        if [[ "$h" == "$hash" ]]; then
            if [[ $(( now - ts )) -le "$ttl" ]]; then
                return 0
            fi
        fi
    done < "$file"
    return 1
}

# url_group_record_seen GROUP HASH SECONDS
# Remembers HASH as opened now and forgets hashes older than SECONDS seconds.
# Call it with the group's lock held.
url_group_record_seen() {
    local group="$1" hash="$2" ttl="$3" dir file tmp now ts h
    dir="$(_url_group_dir)"
    file="$dir/$group.seen"
    mkdir -p "$dir" 2>/dev/null || return 0
    tmp="$(mktemp "$dir/.seen.XXXXXX")" || return 0
    now="$(date +%s)"
    {
        if [[ -f "$file" ]]; then
            while IFS=$'\t' read -r ts h; do
                case "$ts" in
                    ''|*[!0-9]*) continue ;;
                esac
                if [[ "$h" != "$hash" ]]; then
                    if [[ $(( now - ts )) -le "$ttl" ]]; then
                        printf '%s\t%s\n' "$ts" "$h"
                    fi
                fi
            done < "$file"
        fi
        printf '%s\t%s\n' "$now" "$hash"
    } > "$tmp"
    mv "$tmp" "$file" 2>/dev/null || true
    return 0
}

# url_group_window_load GROUP
# Sets URL_GROUP_WINDOW_TS, URL_GROUP_WINDOW_ID and URL_GROUP_WINDOW_APP to the
# group's remembered window (when it was last used, its id, the browser app),
# or to empty strings.
url_group_window_load() {
    local file ts="" wid="" app=""
    file="$(_url_group_dir)/$1.window"
    URL_GROUP_WINDOW_TS=""
    URL_GROUP_WINDOW_ID=""
    URL_GROUP_WINDOW_APP=""
    if [[ -f "$file" ]]; then
        IFS=$'\t' read -r ts wid app < "$file" || true
        case "$ts" in
            ''|*[!0-9]*) return 0 ;;
        esac
        case "$wid" in
            ''|*[!0-9]*) return 0 ;;
        esac
        URL_GROUP_WINDOW_TS="$ts"
        URL_GROUP_WINDOW_ID="$wid"
        URL_GROUP_WINDOW_APP="$app"
    fi
    return 0
}

# url_group_window_save GROUP WINDOW_ID APP_NAME
# Remembers WINDOW_ID as the group's window, last used now.
url_group_window_save() {
    local dir tmp
    dir="$(_url_group_dir)"
    mkdir -p "$dir" 2>/dev/null || return 0
    tmp="$(mktemp "$dir/.window.XXXXXX")" || return 0
    printf '%s\t%s\t%s\n' "$(date +%s)" "$2" "$3" > "$tmp"
    mv "$tmp" "$dir/$1.window" 2>/dev/null || true
    return 0
}
