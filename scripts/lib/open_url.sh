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
