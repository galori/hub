# hub Development Guide

## Workflow

### REQUIRED: After every change

- MUST run `hub install` if any file in `config/` or `lib/` changed
- MUST create a git commit and `git push` after every completed set of changes

## Project Structure

- `scripts/hub` - Main shell script (install, up, down, new, list, remove, rename, open, apps, tree commands)
- `scripts/lib/apps_flow.sh` - Shared helpers for the app-picker and `hub apps` subcommand (sourced by scripts/hub)
- `config/app_presets.json` - Curated `CFBundleIdentifier` → launch-cmd database; deployed to `~/.config/hub/app_presets.json` by install
- `commands/` - Generic Claude Code slash commands (e.g. `hub-new.md`); deployed to `~/.claude/commands/` by install
- `commands.local/` - Gitignored, user-private slash commands (company-specific, etc.); also deployed to `~/.claude/commands/` by install
- `config/aerospace.toml` - AeroSpace config template (`__HUB_SCRIPT__` placeholder replaced during install)
- `lib/status_bar.swift` - Native Swift status bar (compiled to `~/.config/hub/status_bar`); replaces the retired SketchyBar dependency
- `lib/overlay.swift` - Status overlay HUD (compiled to `~/.config/hub/overlay`)
- `lib/new_workspace_dialog.swift` - Workspace creation dialog (compiled to `~/.config/hub/new_workspace_dialog`)
- `lib/confirm_dialog.swift` - Confirmation dialog (compiled to `~/.config/hub/confirm_dialog`)
- `lib/rename_dialog.swift` - Rename dialog (compiled to `~/.config/hub/rename_dialog`)
- `lib/dashboard_dialog.swift` - Dashboard/status overlay dialog (compiled to `~/.config/hub/dashboard_dialog`)
- `lib/output_window.swift` - Generic text output window used by `hub tree` (compiled to `~/.config/hub/output_window`)
- `lib/http_handler.swift` - HTTP/HTTPS URL handler daemon; receives Apple Events, shows HUD, opens URL in slot-2 browser (compiled to `~/.config/hub/http_handler`)
- `lib/browser_ctl.swift` - Browser control helper for focus/tab management (compiled to `~/.config/hub/browser_ctl`)
- `lib/spatial_order.swift` - CGWindowList geometry helper; in default mode takes window IDs as args and prints them sorted left-to-right; in `--tree` mode reconstructs and prints the AeroSpace tiling tree (compiled to `~/.config/hub/spatial_order`)
- `lib/testing_banner.swift` - Small floating "stand by" HUD shown top-right while an automated session is testing hub (compiled to `~/.config/hub/testing_banner`). Has a ✕ dismiss button and always prefixes its text with `[🤖]` to mark it as automated.
- `lib/progress_banner.swift` - User-facing floating progress HUD shown top-right during workspace setup; blue border, ✕ dismiss button, accepts stdin message updates (compiled to `~/.config/hub/progress_banner`)
- `lib/hide_menu_bar.applescript` - Menu bar toggle via System Settings UI automation
- `~/.config/hub/apps.json` - App launcher configuration (up to 5 slots, created by install)

## Principles

- **Keyboard-first**: All UI must be fully navigable with keyboard alone. Mouse support is secondary. Dialogs should have tab navigation, enter to submit, escape to cancel, and keyboard shortcuts for actions.
- **UI/CLI parity**: Every action available through a GUI dialog or keybinding must also have an equivalent CLI command. Commands without full flags show a GUI dialog; with all flags + `-y`, they execute silently. The same code path runs from both CLI and keybinding.
- **Single-binary Swift UIs**: GUI elements are standalone Swift files compiled with `swiftc -O -framework Cocoa`. No Xcode project, no storyboards.
- **Config is deployed, not symlinked**: `hub install` deploys configs to their destinations. `aerospace.toml` uses an `__HUB_SCRIPT__` placeholder substituted via sed.
- **Harmless deploy**: Running `hub install` is always safe as an idempotent deploy/reload step after code changes.
- **Responsiveness first**: UI actions must feel instant. Never block the user waiting for background work (app teardown, window closing, etc.) to complete. Move slow work off the critical path — fire-and-forget or background subshells — so the visible state updates immediately.
- **Dismissable HUDs**: Every floating/always-on-top HUD whose lifetime is tied to an external process (banners, progress overlays — anything launched as a background Swift binary fed via stdin/FIFO) MUST render a manual ✕ dismiss button. If the launching process crashes or is `^C`'d before it sends `QUIT`, the button is the user's only escape hatch. Such windows must set `ignoresMouseEvents = false`. Reuse the `ClickView` dismiss-button pattern in `lib/progress_banner.swift` / `lib/testing_banner.swift` (hover states + `onPress = { dismiss() }`). Modal overlays that auto-dismiss on a deterministic, short-lived action (e.g. `lib/overlay.swift` during `hub up`/`down`) are exempt.

## Agent Tools

- `agents/bin/screenshot-bar` - Captures a screenshot of just the bar region (top of screen). **MUST be used to visually confirm the bar looks correct after any bar-related change** — layout, icons, spacing, colors. Run it, read the PNG, and verify before committing. Outputs a PNG path: `agents/bin/screenshot-bar [output.png]`
- `hub testing-banner start|stop|run` - Raise/dismiss a small top-right "stand by" HUD so the user knows not to interact with the UI while you're testing. MUST be used before triggering transient UI, timing-sensitive screenshots, or focus-dependent flows. Always pair `start` with `stop`, even on failure paths. See CLAUDE.md for full guidance.

