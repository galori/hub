#!/usr/bin/env bash
# Workspace reordering: `hub reorder`. Sourced by scripts/hub.
#
# A workspace's place in the Hub Bar is its ID, so moving a pill means changing
# IDs. AeroSpace cannot rename a workspace, so windows are moved to the new ID.

# Slot order, left to right. Z (General) is fixed and is never a target.
REORDER_SLOTS=(1 2 3 4 5 6 7 8 9 A B C D E F G I M N O P Q R S T U V W X Y)

_reorder_slot_index() {
    local want="$1" i
    for i in "${!REORDER_SLOTS[@]}"; do
        if [[ "${REORDER_SLOTS[$i]}" == "$want" ]]; then
            echo "$i"
            return 0
        fi
    done
    return 1
}

# _reorder_plan SRC AFTER USED_IDS
#   SRC       workspace to move
#   AFTER     workspace it lands right after ("" = first slot)
#   USED_IDS  newline-separated IDs that hold a workspace (SRC included)
# Prints "old new" pairs: shifted workspaces highest first, then "SRC target".
# Prints nothing when the move changes nothing. Returns 1 when no slot is free.
_reorder_plan() {
    local src="$1" after="$2" used="$3"
    local src_i target_i i

    src_i="$(_reorder_slot_index "$src")" || return 2
    if [[ -z "$after" ]]; then
        target_i=0
    else
        [[ "$after" == "$src" ]] && return 0
        target_i="$(_reorder_slot_index "$after")" || return 2
        target_i=$(( target_i + 1 ))
    fi
    [[ "$target_i" -eq "$src_i" ]] && return 0

    # First free slot at or after the target (the source slot counts as free).
    local last=$(( ${#REORDER_SLOTS[@]} - 1 )) gap_i=-1
    for (( i = target_i; i <= last; i++ )); do
        if [[ "$i" -eq "$src_i" ]] || ! grep -qxF "${REORDER_SLOTS[$i]}" <<< "$used"; then
            gap_i="$i"
            break
        fi
    done
    [[ "$gap_i" -lt 0 ]] && return 1

    for (( i = gap_i - 1; i >= target_i; i-- )); do
        echo "${REORDER_SLOTS[$i]} ${REORDER_SLOTS[$((i + 1))]}"
    done
    echo "$src ${REORDER_SLOTS[$target_i]}"
}

# _reorder_after_for_before BEFORE -> prints the slot just left of BEFORE ("" if first)
_reorder_slot_before() {
    local i
    i="$(_reorder_slot_index "$1")" || return 2
    [[ "$i" -eq 0 ]] && return 0
    echo "${REORDER_SLOTS[$((i - 1))]}"
}

# Rename the per-workspace Claude status files from one ID to another.
_reorder_move_claude_state() {
    local old="$1" new="$2" dir="${HUB_CLAUDE_STATE_DIR:-/tmp}" kind
    for kind in active pid alert; do
        if [[ -e "$dir/hub_claude_${kind}_${old}" ]]; then
            mv -f "$dir/hub_claude_${kind}_${old}" "$dir/hub_claude_${kind}_${new}" 2>/dev/null || true
        fi
    done
}

# Move every window from one workspace to another.
_reorder_move_windows() {
    local from="$1" to="$2" wid
    while IFS= read -r wid; do
        [[ -z "$wid" ]] && continue
        aerospace move-node-to-workspace --window-id "$wid" "$to" 2>/dev/null || true
    done < <(spatial_order_ltr "$from")
}

_print_reorder_usage() {
    cat <<'EOF'
Usage: hub reorder <ws> (--after <id> | --before <id> | --first) [--monitor <name>]
       hub reorder left|right

Move workspace <ws> to a new place in the Hub Bar. It takes the ID of its new
slot. Workspaces to its right shift one slot up, until the first free slot.

  --after <id>      Land right after workspace <id>
  --before <id>     Land right before workspace <id>
  --first           Land in the first slot
  --monitor <name>  Also move the workspace to that monitor (by name or ID)
  left | right      Move the focused workspace one pill left or right
EOF
}

# Prints the ID of the pill next to WS on WS's monitor, in direction DIR (-1/1).
_reorder_neighbor() {
    local ws="$1" dir="$2" mon_id on_mon ids id prev="" found=""
    mon_id="$(_monitor_of_workspace "$ws" 2>/dev/null || true)"
    mon_id="${mon_id%%|*}"
    if [[ -n "$mon_id" ]]; then
        on_mon="$(aerospace list-workspaces --monitor "$mon_id" 2>/dev/null || true)"
    else
        on_mon="$(aerospace list-workspaces --monitor all --empty no 2>/dev/null || true)"
    fi
    ids="$(jq -r '.[].workspace_id' "$WORKSPACES_FILE" 2>/dev/null || true)"
    for id in "${REORDER_SLOTS[@]}"; do
        grep -qxF "$id" <<< "$ids" || continue
        grep -qxF "$id" <<< "$on_mon" || continue
        if [[ "$dir" -lt 0 ]]; then
            [[ "$id" == "$ws" ]] && { echo "$prev"; return 0; }
            prev="$id"
        else
            [[ -n "$found" ]] && { echo "$id"; return 0; }
            [[ "$id" == "$ws" ]] && found=1
        fi
    done
    return 0
}

cmd_reorder() {
    local src="" after="" mode="" monitor=""
    case "${1:-}" in
        -h|--help|help|'') _print_reorder_usage; return 0 ;;
        left|right)
            local dir=-1 nb
            [[ "$1" == "right" ]] && dir=1
            src="$(aerospace list-workspaces --focused 2>/dev/null || echo "")"
            [[ -z "$src" ]] && { fail "Could not determine current workspace"; return 1; }
            nb="$(_reorder_neighbor "$src" "$dir")"
            if [[ -z "$nb" ]]; then
                [[ "$dir" -lt 0 ]] && { info "Already first"; return 0; }
                info "Already last"
                return 0
            fi
            if [[ "$dir" -lt 0 ]]; then
                mode="before"; after="$nb"
            else
                mode="after"; after="$nb"
            fi
            ;;
        *)
            src="$1"; shift
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --after)   mode="after";  after="${2:-}"; shift 2 || { fail "--after needs an ID"; return 2; } ;;
                    --before)  mode="before"; after="${2:-}"; shift 2 || { fail "--before needs an ID"; return 2; } ;;
                    --first)   mode="first"; after=""; shift ;;
                    --monitor) monitor="${2:-}"; shift 2 || { fail "--monitor needs a name"; return 2; } ;;
                    *) fail "Unknown option: $1"; _print_reorder_usage; return 2 ;;
                esac
            done
            ;;
    esac
    [[ -z "$mode" ]] && { fail "Say where: --after, --before or --first"; _print_reorder_usage; return 2; }

    _is_valid_workspace_id "$src" && [[ "$src" != "Z" ]] || { fail "Cannot move workspace '$src'"; return 2; }
    if [[ ! -f "$WORKSPACES_FILE" ]] || ! jq -e --arg id "$src" 'any(.[]; .workspace_id == $id)' "$WORKSPACES_FILE" >/dev/null 2>&1; then
        fail "No workspace found with ID '$src'"
        return 1
    fi
    if [[ "$mode" == "before" ]]; then
        _is_valid_workspace_id "$after" && [[ "$after" != "Z" ]] || { fail "Bad workspace ID '$after'"; return 2; }
        if [[ "$after" == "$src" ]]; then return 0; fi
        after="$(_reorder_slot_before "$after")"
    elif [[ "$mode" == "after" ]]; then
        _is_valid_workspace_id "$after" && [[ "$after" != "Z" ]] || { fail "Bad workspace ID '$after'"; return 2; }
    fi

    # Resolve --monitor to an AeroSpace monitor ID and a stored name.
    local mon_id="" mon_name=""
    if [[ -n "$monitor" ]]; then
        local line
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            if [[ "${line%%|*}" == "$monitor" || "${line#*|}" == "$monitor" ]]; then
                mon_id="${line%%|*}"; mon_name="${line#*|}"; break
            fi
        done < <(_list_monitors)
        [[ -z "$mon_id" ]] && { fail "No monitor '$monitor'"; return 1; }
    fi

    _hub_lock_acquire || return 1

    local used plan rc=0
    used="$( { jq -r '.[].workspace_id' "$WORKSPACES_FILE" 2>/dev/null
               aerospace list-workspaces --monitor all --empty no 2>/dev/null; } | sort -u)"
    plan="$(_reorder_plan "$src" "$after" "$used")" || rc=$?
    if [[ "$rc" -eq 1 ]]; then
        _hub_lock_release
        fail "No free workspace slot"
        return 1
    elif [[ "$rc" -ne 0 ]]; then
        _hub_lock_release
        fail "Bad workspace ID"
        return 2
    fi
    if [[ -z "$plan" ]]; then
        _hub_lock_release
        if [[ -n "$mon_id" ]]; then
            _move_workspace_to_monitor "$src" "$mon_id"
            _set_workspace_monitor "$src" "$mon_name"
            hub_bar_refresh
        fi
        return 0
    fi

    hub_log "INPUT" "reorder $src: $(tr '\n' ';' <<< "$plan")"

    # Pin moved workspaces to their current monitor so they stay put (multi-monitor only).
    local old new cur
    if [[ "$(_list_monitors | grep -c .)" -gt 1 ]]; then
        while read -r old new; do
            cur="$(_monitor_of_workspace "$old" 2>/dev/null || true)"
            [[ -n "$cur" ]] && _set_workspace_monitor_locked "$old" "${cur#*|}"
        done <<< "$plan"
    fi

    local focused target tmp_ws="hub-reorder-tmp"
    focused="$(aerospace list-workspaces --focused 2>/dev/null || echo "")"
    target="$(tail -1 <<< "$plan" | cut -d' ' -f2)"

    # 1. Park the source so a shift can reuse its slot.
    _reorder_move_windows "$src" "$tmp_ws"
    _reorder_move_claude_state "$src" "${src}_reorder_tmp"
    # 2. Shift, highest first (each target is free by then).
    local map_old=() map_new=()
    while read -r old new; do
        [[ "$old" == "$src" ]] && continue
        _reorder_move_windows "$old" "$new"
        _reorder_move_claude_state "$old" "$new"
        map_old+=("$old"); map_new+=("$new")
    done <<< "$plan"
    # 3. Drop the source into its slot.
    _reorder_move_windows "$tmp_ws" "$target"
    _reorder_move_claude_state "${src}_reorder_tmp" "$target"
    map_old+=("$src"); map_new+=("$target")

    # 4. Rewrite IDs in workspaces.json in one pass.
    local pairs="" i
    for i in "${!map_old[@]}"; do
        pairs+="${map_old[$i]} ${map_new[$i]}"$'\n'
    done
    local updated
    updated="$(jq --arg pairs "$pairs" --arg mon "$mon_name" --arg src "$src" '
        ($pairs | split("\n") | map(select(length > 0) | split(" ") | {key: .[0], value: .[1]}) | from_entries) as $m
        | map(if $m[.workspace_id] != null
              then (if .workspace_id == $src and $mon != "" then .monitor = $mon else . end)
                   | .workspace_id = $m[.workspace_id]
              else . end)' "$WORKSPACES_FILE")" && echo "$updated" > "$WORKSPACES_FILE"
    _hub_lock_release

    rebuild_labels_file
    restore_workspace_monitors
    # Keep the user looking at the same workspace.
    if [[ -n "$focused" ]]; then
        for i in "${!map_old[@]}"; do
            [[ "${map_old[$i]}" == "$focused" ]] && { focused="${map_new[$i]}"; break; }
        done
        aerospace workspace "$focused" 2>/dev/null || true
    fi
    hub_bar_refresh
    success "Moved workspace $src to slot $target"
}

# Like _set_workspace_monitor, but the caller already holds the Hub lock.
_set_workspace_monitor_locked() {
    local ws_id="$1" mon_name="$2" updated
    [[ -f "$WORKSPACES_FILE" ]] || return 0
    updated="$(jq --arg id "$ws_id" --arg m "$mon_name" \
        'map(if .workspace_id == $id then .monitor = $m else . end)' "$WORKSPACES_FILE")" \
        && echo "$updated" > "$WORKSPACES_FILE"
}
