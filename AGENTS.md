# hub Development Guide

## Workflow

### REQUIRED: After every change

- MUST run `hub install` if any file in `config/` or `lib/` changed
- MUST create a git commit and `git push` after every completed set of changes

## Project Structure

- `scripts/hub` - Main shell script (install, up, down, new, list, remove, rename, open, tree commands)
- `config/aerospace.toml` - AeroSpace config template (`__HUB_SCRIPT__` placeholder replaced during install)
- `config/sketchybar/` - SketchyBar config and plugin scripts
- `config/sketchybar/plugins/app_launcher.sh` - Updates app icon visual state on workspace change
- `lib/overlay.swift` - Status overlay HUD (compiled to `~/.config/hub/overlay`)
- `lib/new_workspace_dialog.swift` - Workspace creation dialog (compiled to `~/.config/hub/new_workspace_dialog`)
- `lib/confirm_dialog.swift` - Confirmation dialog (compiled to `~/.config/hub/confirm_dialog`)
- `lib/rename_dialog.swift` - Rename dialog (compiled to `~/.config/hub/rename_dialog`)
- `lib/dashboard_dialog.swift` - Dashboard/status overlay dialog (compiled to `~/.config/hub/dashboard_dialog`)
- `lib/output_window.swift` - Generic text output window used by `hub tree` (compiled to `~/.config/hub/output_window`)
- `lib/http_handler.swift` - HTTP/HTTPS URL handler daemon; receives Apple Events, shows HUD, opens URL in slot-2 browser (compiled to `~/.config/hub/http_handler`)
- `lib/browser_ctl.swift` - Browser control helper for focus/tab management (compiled to `~/.config/hub/browser_ctl`)
- `lib/spatial_order.swift` - CGWindowList geometry helper; in default mode takes window IDs as args and prints them sorted left-to-right; in `--tree` mode reconstructs and prints the AeroSpace tiling tree (compiled to `~/.config/hub/spatial_order`)
- `lib/hide_menu_bar.applescript` - Menu bar toggle via System Settings UI automation
- `~/.config/hub/apps.json` - App launcher configuration (up to 5 slots, created by install)

## Principles

- **Keyboard-first**: All UI must be fully navigable with keyboard alone. Mouse support is secondary. Dialogs should have tab navigation, enter to submit, escape to cancel, and keyboard shortcuts for actions.
- **UI/CLI parity**: Every action available through a GUI dialog or keybinding must also have an equivalent CLI command. Commands without full flags show a GUI dialog; with all flags + `-y`, they execute silently. The same code path runs from both CLI and keybinding.
- **Single-binary Swift UIs**: GUI elements are standalone Swift files compiled with `swiftc -O -framework Cocoa`. No Xcode project, no storyboards.
- **Config is deployed, not symlinked**: `hub install` deploys configs to their destinations. Both aerospace.toml and sketchybar configs use `__HUB_SCRIPT__` placeholder substituted via sed.
- **Harmless deploy**: Running `hub install` is always safe as an idempotent deploy/reload step after code changes.
- **Responsiveness first**: UI actions must feel instant. Never block the user waiting for background work (app teardown, window closing, etc.) to complete. Move slow work off the critical path — fire-and-forget or background subshells — so the visible state updates immediately.

## Agent Tools

- `agents/bin/screenshot-bar` - Captures a screenshot of just the sketchybar region (top of screen). **MUST be used to visually confirm the bar looks correct after any sketchybar-related change** — layout, icons, spacing, colors. Run it, read the PNG, and verify before committing. Outputs a PNG path: `agents/bin/screenshot-bar [output.png]`

