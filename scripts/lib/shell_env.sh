# hub shell environment integration (sourced by .hub-shell-integration).
#
# Sets HUB_WORKSPACE_ID / HUB_WORKSPACE_UID in every terminal hub opens, for all
# launchers (Ghostty, iTerm2, Terminal, WezTerm, Warp, …). hub launches each
# terminal in the workspace's directory, so we derive the workspace from $PWD by
# matching it against workspaces.json. Works even for launchers whose terminal
# does not inherit hub's environment (osascript-driven Terminal/iTerm2, and
# `open -na` apps), which is why a plain `export` at launch time is not enough.
#
# This is sourced into interactive bash and zsh sessions. It is intentionally
# POSIX-ish so the one file works in both shells.

# _hub_workspaces_file: path to workspaces.json, honoring HUB_CONFIG_DIR/HUB_HOME.
_hub_workspaces_file() {
    local dir="${HUB_CONFIG_DIR:-${HUB_HOME:-$HOME}/.config/hub}"
    printf '%s/workspaces.json' "$dir"
}

# _hub_canonical_path PATH: print a canonical absolute path (resolves symlinks
# and macOS /private aliasing when possible). Falls back to the input unchanged.
_hub_canonical_path() {
    local p="$1"
    [ -n "$p" ] || return 0
    # `cd -P` resolves symlinks without needing realpath/readlink -f (absent on
    # stock macOS). Run in a subshell so it never changes the caller's cwd.
    if [ -d "$p" ]; then
        ( CDPATH='' cd -P -- "$p" 2>/dev/null && pwd -P ) || printf '%s' "$p"
    else
        printf '%s' "$p"
    fi
}

# _hub_path_within CHILD PARENT: return 0 if CHILD is PARENT or a descendant of
# PARENT, matching on a path boundary so "/a/app" is not "within" "/a/app2".
_hub_path_within() {
    local child="$1" parent="$2"
    [ -n "$child" ] && [ -n "$parent" ] || return 1
    [ "$child" = "$parent" ] && return 0
    case "$child" in
        "$parent"/*) return 0 ;;
    esac
    return 1
}

# _hub_set_workspace_env: look up $PWD against workspaces.json and, if it lies
# within a workspace path, export HUB_WORKSPACE_ID / HUB_WORKSPACE_UID.
#
# Rules:
#   * An explicit value set by hub (the AI-prompt wrapper) is never overwritten:
#     if the vars are set and HUB_WORKSPACE_ENV_AUTO is not "1", we leave them.
#   * We only manage values we set ourselves; those carry HUB_WORKSPACE_ENV_AUTO=1
#     so a later `cd` can update or clear them.
#   * On a tie, the longest (most specific) workspace path wins — this handles a
#     workspace nested inside another workspace's directory.
_hub_set_workspace_env() {
    # Re-entrancy guard: _hub_canonical_path uses `cd` in a subshell, and zsh
    # fires the chpwd hook for that too, which would recurse into this function.
    [ -n "${_HUB_SET_WS_ENV_ACTIVE:-}" ] && return 0
    _HUB_SET_WS_ENV_ACTIVE=1

    _hub_set_workspace_env_impl
    local _rc=$?
    unset _HUB_SET_WS_ENV_ACTIVE
    return $_rc
}

_hub_set_workspace_env_impl() {
    # Respect an explicit, non-auto value (e.g. the prompt wrapper's export).
    if [ -n "${HUB_WORKSPACE_ID:-}" ] && [ "${HUB_WORKSPACE_ENV_AUTO:-}" != "1" ]; then
        return 0
    fi

    local wsfile
    wsfile="$(_hub_workspaces_file)"
    if [ ! -f "$wsfile" ] || ! command -v jq >/dev/null 2>&1; then
        return 0
    fi

    local here here_raw
    here_raw="$PWD"
    here="$(_hub_canonical_path "$PWD")"
    [ -n "$here" ] || here="$here_raw"

    # jq only flattens the file into "path<TAB>id<TAB>uid" lines; the actual
    # path matching happens in shell so we can canonicalize each workspace path
    # the same way we canonicalize $PWD (jq cannot resolve symlinks, and macOS
    # aliases /var -> /private/var, /tmp -> /private/tmp, etc.).
    local best_id="" best_uid="" best_len=-1
    local ws_path ws_id ws_uid cpath cpath_len
    while IFS=$'\t' read -r ws_path ws_id ws_uid; do
        [ -n "$ws_path" ] || continue
        # strip a single trailing slash for a clean boundary compare
        case "$ws_path" in
            */) [ "$ws_path" != "/" ] && ws_path="${ws_path%/}" ;;
        esac
        cpath="$(_hub_canonical_path "$ws_path")"
        [ -n "$cpath" ] || cpath="$ws_path"
        # Match $PWD (canonical or raw) against the workspace path (canonical or
        # raw) with a path boundary so "/a/app" never matches "/a/app2".
        if _hub_path_within "$here" "$cpath" || _hub_path_within "$here_raw" "$ws_path" \
            || _hub_path_within "$here" "$ws_path" || _hub_path_within "$here_raw" "$cpath"; then
            cpath_len=${#cpath}
            if [ "$cpath_len" -gt "$best_len" ]; then
                best_len=$cpath_len
                best_id="$ws_id"
                best_uid="$ws_uid"
            fi
        fi
    done <<EOF
$(jq -r '.[] | select(type == "object") | [(.path // ""), (.workspace_id // ""), (.uid // "")] | @tsv' "$wsfile" 2>/dev/null)
EOF

    if [ -z "$best_id" ]; then
        # $PWD is not inside any workspace. Clear only a value we set ourselves,
        # so stale auto-set vars do not leak after cd'ing out of a workspace.
        if [ "${HUB_WORKSPACE_ENV_AUTO:-}" = "1" ]; then
            unset HUB_WORKSPACE_ID HUB_WORKSPACE_UID HUB_WORKSPACE_ENV_AUTO
        fi
        return 0
    fi

    export HUB_WORKSPACE_ID="$best_id"
    export HUB_WORKSPACE_UID="$best_uid"
    export HUB_WORKSPACE_ENV_AUTO=1
}

# Run once at shell startup.
_hub_set_workspace_env

# Re-run after every directory change. osascript-driven terminals (Terminal.app,
# iTerm2) run .zshrc *before* typing `cd {path}`, so the startup call above sees
# the wrong $PWD for them; the cd hook corrects it on the first prompt.
if [ -n "${ZSH_VERSION:-}" ]; then
    autoload -Uz add-zsh-hook 2>/dev/null
    if command -v add-zsh-hook >/dev/null 2>&1; then
        add-zsh-hook chpwd _hub_set_workspace_env 2>/dev/null
    else
        # shellcheck disable=SC2206  # zsh array append; this branch is zsh-only
        chpwd_functions=(${chpwd_functions[@]} _hub_set_workspace_env)
    fi
elif [ -n "${BASH_VERSION:-}" ]; then
    # Append to PROMPT_COMMAND so the first prompt (after any typed `cd`) updates.
    case ";${PROMPT_COMMAND:-};" in
        *";_hub_set_workspace_env;"*) : ;;
        *) PROMPT_COMMAND="${PROMPT_COMMAND:+$PROMPT_COMMAND;}_hub_set_workspace_env" ;;
    esac
fi
