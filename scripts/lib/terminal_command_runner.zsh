#!/bin/zsh
# Execute one Hub terminal command request without reparsing its argv.
#
# The caller writes a private NUL-delimited payload:
#   workspace-path\0command\0argument...\0
# This runner claims the payload with an atomic rename before decoding it.
# Hub sends a RUN or CANCEL decision after it correlates the new window.

emulate -L zsh
setopt NO_NOMATCH

request="${1:-}"
ack="${2:-}"
decision="${3:-}"
claimed=""
decision_attempts="${HUB_COMMAND_DECISION_ATTEMPTS:-600}"
decision_interval="${HUB_COMMAND_DECISION_INTERVAL:-0.05}"
[[ "$decision_attempts" =~ ^[0-9]+$ ]] || decision_attempts=600
[[ "$decision_interval" =~ ^[0-9]+([.][0-9]+)?$ ]] || decision_interval=0.05

_runner_cleanup() {
    [[ -n "$claimed" ]] && rm -f -- "$claimed"
    claimed=""
}
trap '_runner_cleanup' EXIT
trap 'exit 1' HUP INT TERM

_write_ack() {
    local value="$1"
    [[ -n "$ack" && ! -e "$ack" && ! -L "$ack" ]] || return 1
    local tmp="${ack}.tmp.$$.$RANDOM"
    ( umask 077; printf '%s\n' "$value" > "$tmp" ) || return 1
    chmod 600 "$tmp" 2>/dev/null || true
    if ln "$tmp" "$ack" 2>/dev/null; then
        rm -f -- "$tmp"
        return 0
    fi
    rm -f -- "$tmp"
    return 1
}

_fail() {
    if [[ -f "$decision" && "$(cat "$decision" 2>/dev/null || true)" == "CANCEL" ]]; then
        exit 1
    fi
    _write_ack ERROR >/dev/null 2>&1 || true
    print -u2 -- "Hub terminal command request failed"
    exit 1
}

_cancel() {
    exit 1
}

# Accept only an absolute, private request directory. The marker is created by
# Hub when it prepares HUB_TERMINAL_REQUEST_DIR and prevents arbitrary paths
# from being treated as requests by this stable runner.
[[ -n "$request" && -n "$ack" && -n "$decision" && "$request" == /* && "$ack" == /* && "$decision" == /* ]] || _fail
request_dir="${request:h}"
request_name="${request:t}"
request_dir_abs="${request_dir:A}"
[[ -d "$request_dir_abs" && ! -L "$request_dir" && ! -L "$request_dir_abs" ]] || _fail
[[ -f "$request_dir_abs/.hub-terminal-command-dir" && ! -L "$request_dir_abs/.hub-terminal-command-dir" ]] || _fail
[[ "$request_name" == request.* ]] || _fail
[[ "$ack" == "$request.ack" ]] || _fail
[[ "$decision" == "$request.decision" ]] || _fail
[[ ! -e "$ack" && ! -L "$ack" ]] || _fail
[[ ! -L "$decision" ]] || _fail
[[ ! -e "$decision" || -O "$decision" ]] || _fail
[[ -f "$request" && ! -L "$request" && -O "$request" ]] || _fail

# A cancellation written before the terminal starts is authoritative.
if [[ -f "$decision" && "$(cat "$decision" 2>/dev/null || true)" == "CANCEL" ]]; then
    _cancel
fi

# The rename is the claim. A runner that loses the race cannot read or remove
# another runner's request. Keep the claim until Hub commits the launch.
claimed="${request}.claimed.$$.$RANDOM"
[[ ! -e "$claimed" && ! -L "$claimed" ]] || _fail
mv -- "$request" "$claimed" 2>/dev/null || _fail
[[ -f "$claimed" && ! -L "$claimed" && -O "$claimed" ]] || _fail

# A valid payload ends every field with NUL. Reject a truncated final field
# before any command is reconstructed.
last_byte="$(tail -c 1 -- "$claimed" 2>/dev/null | od -An -t x1 2>/dev/null | tr -d ' \n\t')"
[[ "$last_byte" == "00" ]] || _fail

typeset -a fields
field=""
while true; do
    field=""
    if IFS= read -r -d $'\0' field <&3; then
        fields+=("$field")
    else
        [[ -z "$field" ]] || _fail
        break
    fi
done 3< "$claimed"
(( ${#fields[@]} >= 2 )) || _fail
workspace="${fields[1]}"
(( ${#workspace} > 0 )) || _fail
typeset -a command_argv
command_argv=( "${(@)fields[2,-1]}" )
(( ${#command_argv[@]} > 0 )) || _fail

# Decode before acknowledging. No command data is copied to the
# acknowledgement or decision files.
if [[ -f "$HOME/.zshrc" ]]; then
    source "$HOME/.zshrc" 2>/dev/null || true
fi
cd -- "$workspace" 2>/dev/null || _fail
if [[ -f "$decision" && "$(cat "$decision" 2>/dev/null || true)" == "CANCEL" ]]; then
    _cancel
fi
_write_ack READY >/dev/null 2>&1 || _cancel

# READY means the runner is prepared, not that Hub has correlated the window.
# Only Hub's durable RUN decision permits command execution. A crashed Hub
# therefore leaves an idle terminal that exits after a bounded time.
decision_value=""
for ((i=0; i<decision_attempts; i++)); do
    if [[ -f "$decision" ]]; then
        decision_value="$(cat "$decision" 2>/dev/null || true)"
        rm -f -- "$decision"
        break
    fi
    sleep "$decision_interval"
done
case "$decision_value" in
    RUN) ;;
    CANCEL) exit 1 ;;
    *)
        print -u2 -- "Hub terminal command decision timed out"
        exit 1
        ;;
esac

rm -f -- "$claimed"
claimed=""
"${command_argv[@]}"
command_status=$?
if (( command_status != 0 )); then
    print -u2 -- "Hub command exited with status $command_status"
fi

# The terminal remains available for the user's interactive login shell.
exec "${SHELL:-/bin/zsh}" -il
