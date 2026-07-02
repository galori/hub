#!/usr/bin/env bash
# Helpers for the guided app-picker and `hub apps` CLI.
# Sourced by scripts/hub; relies on its env (APPS_FILE, ICONS_DIR, REPO_DIR, bold, info, success, warn, fail).

APP_PRESETS_FILE="${APP_PRESETS_FILE:-$HOME/.config/hub/app_presets.json}"
APPS_MAX_SLOTS=5

# List every installed .app bundle as bundle_id<TAB>display_name<TAB>app_path.
# Cached in /tmp per-session so subsequent calls are instant.
apps_list_installed() {
    local cache="/tmp/hub_apps_cache.$$"
    [ -f "$cache" ] && { cat "$cache"; return; }
    info "Scanning Applications folder for installed apps…" >&2
    {
        find /Applications "$HOME/Applications" /System/Applications -maxdepth 3 -name "*.app" 2>/dev/null
    } | while read -r app_path; do
        [ -d "$app_path" ] || continue
        local plist="$app_path/Contents/Info.plist"
        [ -f "$plist" ] || continue
        local bundle_id display_name
        bundle_id=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$plist" 2>/dev/null) || continue
        display_name=$(/usr/libexec/PlistBuddy -c "Print :CFBundleDisplayName" "$plist" 2>/dev/null) \
            || display_name=$(/usr/libexec/PlistBuddy -c "Print :CFBundleName" "$plist" 2>/dev/null) \
            || display_name=$(basename "$app_path" .app)
        printf "%s\t%s\t%s\n" "$bundle_id" "$display_name" "$app_path"
    done | sort -u -t $'\t' -k2 | tee "$cache"
}

# Interactive search-then-pick for apps. Prints the selected app as TSV, or nothing on cancel (return 1).
# Uses fzf for live-search if available; falls back to a grep-and-pick loop.
apps_search_interactive() {
    local apps_tsv
    apps_tsv=$(apps_list_installed)
    local total
    total=$(printf "%s\n" "$apps_tsv" | grep -c . || echo 0)

    if command -v fzf >/dev/null 2>&1; then
        _apps_search_fzf "$apps_tsv" "$total"
    else
        _apps_search_readline "$apps_tsv" "$total"
    fi
}

# fzf-powered live-search. Feed tab-delimited rows to fzf so we can recover them exactly.
_apps_search_fzf() {
    local apps_tsv="$1" total="$2"
    echo >&2
    info "Found $total installed apps. Type to filter, use ↑/↓ to navigate, Enter to pick, Esc to cancel." >&2
    # Use fzf's --with-nth to hide the bundle_id (field 1) but keep it in the line
    # so our output still has the full TSV we need to return.
    printf "%s\n" "$apps_tsv" \
      | fzf --height=50% --reverse \
            --delimiter=$'\t' \
            --with-nth=2,3 \
            --prompt='  app> ' \
            --header='name                                          path' \
      || return 1
}

# Fallback: prompt for a substring, show top-15 matches, pick by number, repeat.
_apps_search_readline() {
    local apps_tsv="$1" total="$2"
    echo >&2
    info "Found $total installed apps. Type part of an app name to filter." >&2
    info "Type 'q' to cancel, or leave blank to browse all." >&2

    while true; do
        echo >&2
        local query
        read -rp "  Search: " query

        [ "$query" = "q" ] || [ "$query" = "Q" ] && return 1

        local filtered count
        if [ -z "$query" ]; then
            filtered="$apps_tsv"
        else
            filtered=$(printf "%s\n" "$apps_tsv" | grep -iF -- "$query" || true)
        fi
        count=$(printf "%s\n" "$filtered" | grep -c . || echo 0)

        if [ "$count" -eq 0 ]; then
            warn "No matches for \"$query\". Try a different search." >&2
            continue
        fi

        local shown=15
        [ "$count" -lt "$shown" ] && shown="$count"

        echo >&2
        local i=1
        local dim reset_color
        dim="$(tput setaf 8 2>/dev/null || true)"
        reset_color="$(tput sgr0 2>/dev/null || true)"
        while IFS=$'\t' read -r bundle_id name app_path; do
            [ -z "$bundle_id" ] && continue
            printf "  %2d) %s  %s(%s)%s\n" "$i" "$name" "$dim" "$bundle_id" "$reset_color" >&2
            printf "      %s%s%s\n" "$dim" "$app_path" "$reset_color" >&2
            i=$((i+1))
            [ "$i" -gt "$shown" ] && break
        done <<< "$filtered"

        if [ "$count" -gt "$shown" ]; then
            echo "  … $((count - shown)) more — refine your search to see them." >&2
        fi

        echo >&2
        local choice
        read -rp "  Pick number [1-$shown] (or Enter to search again, 'q' to cancel): " choice

        [ "$choice" = "q" ] || [ "$choice" = "Q" ] && return 1
        [ -z "$choice" ] && continue

        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "$shown" ]; then
            printf "%s\n" "$filtered" | sed -n "${choice}p"
            return 0
        fi

        warn "Invalid choice. Try again." >&2
    done
}

# Explain why the launch command matters. Printed once before each template prompt.
_apps_print_new_window_note() {
    echo >&2
    echo "  Heads up: hub works best when each launch opens a NEW window." >&2
    echo "  When you press Ctrl+Alt+<slot>, hub watches for a new window of that app" >&2
    echo "  and moves it into your current workspace. If the command just focuses an" >&2
    echo "  existing window instead, hub falls back to bringing that window over —" >&2
    echo "  so it still works, you just end up with one shared window across workspaces." >&2
    echo "  The macOS 'open -n' flag asks for a new instance, but each app decides" >&2
    echo "  whether to honor it. Many apps need their own '--new-window' flag too." >&2
    echo >&2
}

# Given bundle_id + app_path + name, return launch command (and optional cold-start,
# url, and prompt launch commands) via preset lookup or template prompt.
# Prints a TSV line:
# launch<TAB>url_launch<TAB>prompt_launch<TAB>first_launch<TAB>first_url_launch<TAB>first_prompt_launch
# Extra fields may be empty.
apps_pick_launch_template() {
    local bundle_id="$1" app_path="$2" display_name="$3"

    # Try preset DB first
    if [ -f "$APP_PRESETS_FILE" ]; then
        local preset
        preset=$(jq -r --arg id "$bundle_id" '.[$id] // empty' "$APP_PRESETS_FILE" 2>/dev/null)
        if [ -n "$preset" ]; then
            local preset_launch preset_url_launch preset_prompt_launch preset_first_launch preset_first_url_launch preset_first_prompt_launch preset_desc
            preset_launch=$(printf "%s" "$preset" | jq -r '.launch')
            preset_url_launch=$(printf "%s" "$preset" | jq -r '.url_launch // ""')
            preset_prompt_launch=$(printf "%s" "$preset" | jq -r '.prompt_launch // ""')
            preset_first_launch=$(printf "%s" "$preset" | jq -r '.first_launch // ""')
            preset_first_url_launch=$(printf "%s" "$preset" | jq -r '.first_url_launch // ""')
            preset_first_prompt_launch=$(printf "%s" "$preset" | jq -r '.first_prompt_launch // ""')
            preset_desc=$(printf "%s" "$preset" | jq -r '.description // ""')

            echo >&2
            success "Found preset for $display_name" >&2
            echo >&2
            echo "    What it does: $preset_desc" >&2
            echo "    Launch cmd:   $preset_launch" >&2
            [ -n "$preset_first_launch" ] && echo "    First launch:  $preset_first_launch" >&2
            [ -n "$preset_prompt_launch" ] && echo "    Prompt launch: $preset_prompt_launch" >&2
            [ -n "$preset_first_prompt_launch" ] && echo "    First prompt:  $preset_first_prompt_launch" >&2
            [ -n "$preset_url_launch" ] && echo "    URL launch:    $preset_url_launch" >&2
            [ -n "$preset_first_url_launch" ] && echo "    First URL:     $preset_first_url_launch" >&2
            _apps_print_new_window_note
            read -rp "  Use this preset? [Y/n/c=custom] " yn
            case "$yn" in
                ""|y|Y) printf "%s\t%s\t%s\t%s\t%s\t%s\n" "$preset_launch" "$preset_url_launch" "$preset_prompt_launch" "$preset_first_launch" "$preset_first_url_launch" "$preset_first_prompt_launch"; return 0 ;;
                c|C)    ;; # fall through to custom
                *)      return 1 ;;
            esac
        fi
    fi

    # No preset (or user declined) — offer generic templates
    echo >&2
    info "No preset for $display_name. Pick a launch template:" >&2
    echo >&2
    echo "    1) Just open the app (new instance)" >&2
    echo "       → open -na '$display_name'" >&2
    echo >&2
    echo "    2) Open with workspace path as an argument" >&2
    echo "       → open -na '$display_name' --args '{path}'" >&2
    echo "       (for editors or apps that accept a path as their first argument)" >&2
    echo >&2
    echo "    3) Custom command (you write it)" >&2
    echo "       Placeholders: {path} = workspace folder, {workspace} = workspace ID." >&2
    _apps_print_new_window_note
    read -rp "  Choice [1-3/c=cancel]: " tchoice
    local base_launch=""
    case "$tchoice" in
        1) base_launch="open -na '$display_name'" ;;
        2) base_launch="open -na '$display_name' --args '{path}'" ;;
        3)
            echo >&2
            read -rp "  Custom launch command: " base_launch
            [ -z "$base_launch" ] && return 1
            ;;
        *) return 1 ;;
    esac

    # For custom/template commands, offer an optional run-on-launch command
    echo >&2
    echo "  Optional: first-window launch command." >&2
    echo "  This is used when the app has zero windows anywhere. Leave blank to use launch." >&2
    local custom_first_launch=""
    read -rp "  First-window launch command (blank to skip): " custom_first_launch

    echo >&2
    echo "  Optional: run-on-launch command (e.g. to launch Claude Code with a prompt)." >&2
    echo "  This is used by 'hub new --prompt'. Leave blank to skip." >&2
    echo "  Use {path} = workspace folder, {prompt_cmd} = Claude wrapper path." >&2
    local custom_prompt_launch=""
    read -rp "  Run-on-launch command (blank to skip): " custom_prompt_launch

    local custom_first_prompt_launch=""
    if [ -n "$custom_prompt_launch" ]; then
        echo >&2
        echo "  Optional: first-window prompt launch command." >&2
        echo "  This is used by 'hub new --prompt' when the terminal has zero windows." >&2
        read -rp "  First-window prompt launch command (blank to skip): " custom_first_prompt_launch
    fi

    printf "%s\t%s\t%s\t%s\t%s\t%s\n" "$base_launch" "" "$custom_prompt_launch" "$custom_first_launch" "" "$custom_first_prompt_launch"
}

# Write a slot to apps.json atomically; preserves other slots. Triggers icon + bar refresh.
# Optional launch variants are only written when non-empty.
apps_save_slot() {
    local slot="$1" name="$2" launch="$3" icon="$4" url_launch="${5:-}" prompt_launch="${6:-}" first_launch="${7:-}" first_url_launch="${8:-}" first_prompt_launch="${9:-}"
    local idx=$((slot - 1))
    mkdir -p "$(dirname "$APPS_FILE")"
    [ -f "$APPS_FILE" ] || echo "[]" > "$APPS_FILE"

    local tmp
    tmp=$(mktemp "${APPS_FILE}.XXXXXX")
    jq --argjson idx "$idx" \
       --arg name "$name" \
       --arg launch "$launch" \
       --arg icon "$icon" \
       --arg url_launch "$url_launch" \
       --arg prompt_launch "$prompt_launch" \
       --arg first_launch "$first_launch" \
       --arg first_url_launch "$first_url_launch" \
       --arg first_prompt_launch "$first_prompt_launch" \
       '
       # Pad array to idx+1 with blank slot objects if needed, then set idx
       . as $a
       | (if length <= $idx then $a + [range(length; $idx + 1)] | map(if . == null or type == "number" then {name:"", launch:"", icon:""} else . end) else $a end)
       | .[$idx] = (
           {name: $name, launch: $launch, icon: $icon}
           + (if $url_launch != "" then {url_launch: $url_launch} else {} end)
           + (if $prompt_launch != "" then {prompt_launch: $prompt_launch} else {} end)
           + (if $first_launch != "" then {first_launch: $first_launch} else {} end)
           + (if $first_url_launch != "" then {first_url_launch: $first_url_launch} else {} end)
           + (if $first_prompt_launch != "" then {first_prompt_launch: $first_prompt_launch} else {} end)
         )
       ' "$APPS_FILE" > "$tmp" && mv "$tmp" "$APPS_FILE" || { rm -f "$tmp"; return 1; }
    success "Saved slot $slot: $name"
    apps_refresh
    if [[ "$slot" == "2" ]] && command -v build_http_handler >/dev/null 2>&1; then
        build_http_handler
    fi
}

# Remove a slot. Shrinks the array (so a subsequent add fills the next free index).
apps_remove_slot() {
    local slot="$1"
    local idx=$((slot - 1))
    [ -f "$APPS_FILE" ] || { warn "No apps.json"; return 1; }
    local tmp
    tmp=$(mktemp "${APPS_FILE}.XXXXXX")
    jq --argjson idx "$idx" '
       if length > $idx then del(.[$idx]) else . end
       ' "$APPS_FILE" > "$tmp" && mv "$tmp" "$APPS_FILE" || { rm -f "$tmp"; return 1; }
    success "Removed slot $slot"
    apps_refresh
    if [[ "$slot" == "2" ]] && command -v build_http_handler >/dev/null 2>&1; then
        build_http_handler
    fi
}

# Refresh Hub Bar after apps.json changes.
apps_refresh() {
    if command -v hub_bar_refresh >/dev/null 2>&1; then
        hub_bar_refresh
    elif [ -f "$HOME/.config/hub/hub_bar.pid" ]; then
        local _pid
        _pid="$(cat "$HOME/.config/hub/hub_bar.pid" 2>/dev/null || true)"
        [ -n "$_pid" ] && kill -USR1 "$_pid" 2>/dev/null || true
    fi
}

# Get app info from an .app bundle. Prints bundle_id<TAB>display_name.
apps_bundle_info() {
    local app_path="$1"
    local plist="$app_path/Contents/Info.plist"
    [ -f "$plist" ] || return 1
    local bundle_id display_name
    bundle_id=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$plist" 2>/dev/null) || return 1
    display_name=$(/usr/libexec/PlistBuddy -c "Print :CFBundleDisplayName" "$plist" 2>/dev/null) \
        || display_name=$(/usr/libexec/PlistBuddy -c "Print :CFBundleName" "$plist" 2>/dev/null) \
        || display_name=$(basename "$app_path" .app)
    printf "%s\t%s\n" "$bundle_id" "$display_name"
}

# One slot of the guided flow. Returns 1 if the user bails on this slot to end the loop.
apps_add_guided() {
    local slot="$1"

    local app_tsv
    app_tsv=$(apps_search_interactive) || return 1
    [ -z "$app_tsv" ] && return 1

    local bundle_id name app_path
    IFS=$'\t' read -r bundle_id name app_path <<< "$app_tsv"

    local launch_tsv
    launch_tsv=$(apps_pick_launch_template "$bundle_id" "$app_path" "$name") || {
        warn "Skipped slot $slot"
        return 0
    }
    [ -z "$launch_tsv" ] && { warn "Skipped slot $slot"; return 0; }

    # Use cut rather than IFS-read to preserve empty fields (IFS collapses consecutive tabs)
    local launch url_launch prompt_launch first_launch first_url_launch first_prompt_launch
    launch="$(printf '%s' "$launch_tsv" | cut -f1)"
    url_launch="$(printf '%s' "$launch_tsv" | cut -f2)"
    prompt_launch="$(printf '%s' "$launch_tsv" | cut -f3)"
    first_launch="$(printf '%s' "$launch_tsv" | cut -f4)"
    first_url_launch="$(printf '%s' "$launch_tsv" | cut -f5)"
    first_prompt_launch="$(printf '%s' "$launch_tsv" | cut -f6)"
    [ -z "$launch" ] && { warn "Skipped slot $slot"; return 0; }

    apps_save_slot "$slot" "$name" "$launch" "$name" "$url_launch" "$prompt_launch" "$first_launch" "$first_url_launch" "$first_prompt_launch"
}

# Pretty-print current apps.json
apps_list() {
    if [ ! -f "$APPS_FILE" ]; then
        warn "No apps.json yet. Run: hub apps add"
        return
    fi
    local count
    count=$(jq 'length' "$APPS_FILE" 2>/dev/null || echo 0)
    if [ "$count" -eq 0 ]; then
        info "No apps configured. Add one with: hub apps add"
        return
    fi
    echo -e "${bold}Configured apps (${count} slots):${reset}"
    local i
    for ((i=1; i<=count; i++)); do
        local idx=$((i-1))
        local name launch icon url_launch prompt_launch first_launch first_url_launch first_prompt_launch role_hint
        name=$(jq -r --argjson i "$idx" '.[$i].name // ""' "$APPS_FILE")
        launch=$(jq -r --argjson i "$idx" '.[$i].launch // ""' "$APPS_FILE")
        icon=$(jq -r --argjson i "$idx" '.[$i].icon // ""' "$APPS_FILE")
        url_launch=$(jq -r --argjson i "$idx" '.[$i].url_launch // ""' "$APPS_FILE")
        prompt_launch=$(jq -r --argjson i "$idx" '.[$i].prompt_launch // ""' "$APPS_FILE")
        first_launch=$(jq -r --argjson i "$idx" '.[$i].first_launch // ""' "$APPS_FILE")
        first_url_launch=$(jq -r --argjson i "$idx" '.[$i].first_url_launch // ""' "$APPS_FILE")
        first_prompt_launch=$(jq -r --argjson i "$idx" '.[$i].first_prompt_launch // ""' "$APPS_FILE")
        role_hint=""
        [ "$i" -eq 1 ] && role_hint="  ${yellow}(terminal slot)${reset}"
        [ "$i" -eq 2 ] && role_hint="  ${yellow}(browser slot)${reset}"
        if [ -z "$name" ]; then
            printf "  %d)  ${yellow}(empty)${reset}%b\n" "$i" "$role_hint"
        else
            printf "  %d)  ${bold}%s${reset}%b\n" "$i" "$name" "$role_hint"
            printf "      launch: %s\n" "$launch"
            [ -n "$first_launch" ] && printf "      first_launch: %s\n" "$first_launch"
            [ -n "$prompt_launch" ] && printf "      prompt_launch: %s\n" "$prompt_launch"
            [ -n "$first_prompt_launch" ] && printf "      first_prompt_launch: %s\n" "$first_prompt_launch"
            [ -n "$url_launch" ] && printf "      url_launch: %s\n" "$url_launch"
            [ -n "$first_url_launch" ] && printf "      first_url_launch: %s\n" "$first_url_launch"
            printf "      icon:   %s\n" "$icon"
        fi
    done
}

# List every preset available in the preset DB.
apps_list_presets() {
    if [ ! -f "$APP_PRESETS_FILE" ]; then
        warn "No preset database at $APP_PRESETS_FILE"
        info "Run 'hub install' to deploy the shipped presets."
        return 1
    fi
    local count
    count=$(jq 'length' "$APP_PRESETS_FILE" 2>/dev/null || echo 0)
    echo -e "${bold}Available presets (${count}):${reset}"
    echo "  Source: $APP_PRESETS_FILE"
    echo
    # Print sorted by name
    jq -c 'to_entries | sort_by(.value.name) | .[]' "$APP_PRESETS_FILE" \
      | while IFS= read -r preset; do
            local name bundle_id desc launch first_launch prompt_launch first_prompt_launch url_launch first_url_launch
            name="$(printf '%s' "$preset" | jq -r '.value.name')"
            bundle_id="$(printf '%s' "$preset" | jq -r '.key')"
            desc="$(printf '%s' "$preset" | jq -r '.value.description // ""')"
            launch="$(printf '%s' "$preset" | jq -r '.value.launch')"
            first_launch="$(printf '%s' "$preset" | jq -r '.value.first_launch // ""')"
            prompt_launch="$(printf '%s' "$preset" | jq -r '.value.prompt_launch // ""')"
            first_prompt_launch="$(printf '%s' "$preset" | jq -r '.value.first_prompt_launch // ""')"
            url_launch="$(printf '%s' "$preset" | jq -r '.value.url_launch // ""')"
            first_url_launch="$(printf '%s' "$preset" | jq -r '.value.first_url_launch // ""')"
            printf "  ${bold}%s${reset}  ${yellow}(%s)${reset}\n" "$name" "$bundle_id"
            [ -n "$desc" ] && printf "      %s\n" "$desc"
            printf "      launch: %s\n" "$launch"
            [ -n "$first_launch" ] && printf "      first_launch: %s\n" "$first_launch"
            [ -n "$prompt_launch" ] && printf "      prompt_launch: %s\n" "$prompt_launch"
            [ -n "$first_prompt_launch" ] && printf "      first_prompt_launch: %s\n" "$first_prompt_launch"
            [ -n "$url_launch" ] && printf "      url_launch: %s\n" "$url_launch"
            [ -n "$first_url_launch" ] && printf "      first_url_launch: %s\n" "$first_url_launch"
            echo
        done
}
