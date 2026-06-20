# Plan: Move Core Hub Orchestration to Swift

## Context

Hub is a macOS workspace manager (~1800 lines bash) that orchestrates AeroSpace and app launching, with a native Swift Hub Bar. It already has 8+ standalone Swift binaries for UI (dialogs, overlay, browser control, Hub Bar). The goal is to move core orchestration logic into a single Swift binary (`hub-core`) while keeping peripheral scripts (install/deploy, up/down lifecycle) in bash. This gives type safety and eliminates fragile `jq` pipelines for the critical path, without rewriting everything.

## Architecture

### Single `hub-core` binary with subcommands

```
lib/core/
  main.swift          -- CLI dispatch (CommandLine.arguments)
  State.swift         -- Codable models, JSON persistence, label file generation
  Aerospace.swift     -- Process wrapper for aerospace CLI
  BarRefresh.swift    -- Signal the Hub Bar to refresh (SIGUSR1)
  Tiling.swift        -- Window arrangement logic (2-5 window layouts)
  AppSlots.swift      -- App open/focus/cycle logic
  Navigation.swift    -- next/prev workspace cycling
```

Compiled with:
```bash
swiftc -O -o ~/.config/hub/hub-core lib/core/*.swift -framework Foundation
```

No SPM, no Xcode. Same pattern as existing Swift binaries but multi-file.

### Communication protocol
- Bash dispatches to `hub-core <subcommand> [args]` for migrated commands
- Swift outputs JSON to stdout when bash needs data back (e.g., `hub-core query workspace A`)
- Exit codes signal success/failure
- Swift owns `workspaces.json` exclusively (reads + writes)
- Bash reads workspace info only through `hub-core` or the labels cache file
- UI dialogs remain separate binaries, communicate via `/tmp/hub-*` files (unchanged)

### What moves to Swift
| Command | Why |
|---------|-----|
| `list` | Eliminates 5+ jq calls, type-safe workspace rendering |
| `next`/`prev` | Self-contained navigation with aerospace queries |
| `rename` | JSON mutation + bar label update |
| `status` | Workspace state queries |
| `label-length` / `repo-prefix` | Simple state + bar refresh |
| `open` (app slots) | Complex polling/focus logic benefits from structured code |
| `arrange` (window tiling) | Complex split logic, currently fragile string manipulation |
| State queries for `new`/`remove` | Swift handles JSON, bash handles dialogs + teardown |

### What stays in bash
| Command | Why |
|---------|-----|
| `install` | Build orchestration, brew, sed templating, config deploy |
| `up` / `down` | Daemon lifecycle, AppleScript, defaults database, process management |
| `reboot` | Thin wrapper around down + install + up |
| `new` (orchestration) | Launches dialog, reads result, calls `hub-core create`, opens apps |
| `remove` (orchestration) | Launches confirm dialog, calls `hub-core delete`, cleans worktrees |
| `dashboard` / `keys` | Terminal formatting, dialog launching |
| `tree` | Delegates to existing Python agent script |
| Hub Bar | Swift process — refreshed via SIGUSR1 |

## Key models (`State.swift`)

```swift
struct Workspace: Codable {
    let name: String
    let path: String
    let rootRepo: String
    let workspaceId: String
    var color: String?
    var setupCmd: String?
    var apps: String?

    enum CodingKeys: String, CodingKey {
        case name, path, color, apps
        case rootRepo = "root_repo"
        case workspaceId = "workspace_id"
        case setupCmd = "setupCmd"
    }
}

struct AppSlot: Codable {
    let name: String
    let launch: String
    let icon: String
    var urlLaunch: String?

    enum CodingKeys: String, CodingKey {
        case name, launch, icon
        case urlLaunch = "url_launch"
    }
}
```

## Migration phases

### Phase 1: Foundation (State + List + Query)
- `lib/core/main.swift` -- subcommand dispatch
- `lib/core/State.swift` -- read/write workspaces.json, generate labels cache
- Subcommands: `list`, `list -v`, `query workspace <id>`, `query all`
- Update bash `cmd_list` to delegate to `hub-core list`
- Update `hub install` to compile hub-core from `lib/core/*.swift`

### Phase 2: Navigation
- `lib/core/Aerospace.swift` -- wrapper for `aerospace list-workspaces`, `aerospace workspace`
- `lib/core/Navigation.swift` -- next/prev logic
- Subcommands: `next`, `prev`
- Replace bash `_cycle_hub_workspace` with `exec hub-core next/prev`

### Phase 3: Mutations
- Subcommands: `create <args>`, `delete <id>`, `rename <id> <name>`
- `label-length <+|-|N>`, `repo-prefix <on|off|toggle>`
- `lib/core/Sketchybar.swift` -- batch `--set` calls for label updates
- Bash `cmd_new` calls `hub-core create` after dialog, `cmd_remove` calls `hub-core delete`

### Phase 4: App Slots + Tiling
- `lib/core/AppSlots.swift` -- open/focus with polling, TTY detection via `isatty()`
- `lib/core/Tiling.swift` -- arrange_workspace_windows logic
- Subcommands: `open <slot> [--force] [--all]`, `arrange [--ws <id>]`
- This is the most complex phase; port the window polling loop and split calculations

### Phase 5: Cleanup
- Remove `jq` from install dependency checks (no longer needed for core ops)
- Bash script shrinks to ~400-500 lines (install, up, down, dispatch, dialog orchestration)
- Add atomic JSON writes (write-to-temp + rename)

## Build integration

In `hub install`, add to the compilation section:
```bash
compile_swift_dir() {
    local name="$1" src_dir="$2" bin="$3" framework="${4:-Foundation}"
    if [[ ! -f "$bin" ]] || find "$src_dir" -name "*.swift" -newer "$bin" | grep -q .; then
        mkdir -p "$(dirname "$bin")"
        swiftc -O -o "$bin" "$src_dir"/*.swift -framework "$framework" || { fail "Failed to compile $name"; exit 1; }
    fi
}

compile_swift_dir "hub-core" "$LIB_DIR/core" "$HOME/.config/hub/hub-core"
```

## Verification

After each phase:
1. Run `hub install` -- should compile hub-core successfully
2. Run `hub list` / `hub list -v` -- output matches previous behavior
3. Run `hub next` / `hub prev` -- workspace cycling works
4. Run `hub status` -- shows correct info
5. Run `hub open 1` -- app focusing works
6. Test bar labels update correctly after mutations
7. Run existing tests (`test/` directory) if applicable

## Estimated size

- `hub-core`: ~800-1200 lines of Swift across 7 files
- Bash script: shrinks from 1788 to ~400-500 lines
- Net effect: same total LOC, but core logic is type-safe with proper error handling
