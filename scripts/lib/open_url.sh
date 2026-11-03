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
