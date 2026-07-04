# hub Development Guide

## Workflow

### REQUIRED: After every change

- MUST use test-driven development when feasible: write or update a failing test that captures the intended behavior before changing implementation, then make it pass. If TDD is not feasible, document the reason in the final response or PR notes.
- MUST run `hub install` if any file in `config/` or `lib/` changed
- MUST make changes on a non-`main` branch; never commit directly on `main`
- MUST create a git commit and push the branch after every completed set of changes
- MUST open a PR, wait for all PR builds/checks to run and pass, then merge it immediately

### Pull request flow

- Always create changes on a branch and open a PR; do not push directly to `main`.
- Push completed changes to the PR branch, not to `main`.
- Wait for every PR build/check to complete and turn green, including live integration when it runs for PRs.
- Once the PR is green and mergeable, merge it immediately.
- After merging, confirm the GitHub Actions run on `main` stays green.
- If live integration fails on `main`, investigate immediately and treat `main` as red until a repair PR lands.

## PR Style

simple
This is a simple repo. Use a concise title and one-paragraph body; no ticket numbers and no formal PR template are needed.

### Live integration failure repair

- Live integration failures create or update a GitHub issue titled `Live integration failure on main`.
- The issue includes the failing commit SHA, workflow run URL, and captured test output.
- Local repair automation may use Codex or Claude Code on the `Gall` runner to diagnose the failure.
- Repair agents MUST create a branch from current `main`, make the smallest safe fix, run relevant tests, and open a PR.
- Repair agents MUST NOT push fixes directly to `main`.

## Project Structure

- `scripts/hub` - Main shell script (install, up, down, new, list, remove, rename, open, apps, tree commands)
- `scripts/lib/apps_flow.sh` - Shared helpers for the app-picker and `hub apps` subcommand (sourced by scripts/hub)
- `config/app_presets.json` - Curated `CFBundleIdentifier` → launch-cmd database; deployed to `~/.config/hub/app_presets.json` by install
- `config/aerospace.toml` - AeroSpace config template (`__HUB_SCRIPT__` placeholder replaced during install)
- `commands/` - Generic Claude Code slash commands (for example, `hub-new.md`); deployed to `~/.claude/commands/` by install
- `commands.local/` - Gitignored, user-private slash commands (company-specific, etc.); also deployed to `~/.claude/commands/` by install
- `lib/theme.swift` - Shared Cocoa theme/helpers compiled alongside UI binaries
- `lib/hub_bar.swift` - Native Swift Hub Bar (compiled to `~/.config/hub/hub_bar`); replaces the retired SketchyBar dependency
- `lib/new_workspace_dialog.swift` - Workspace creation dialog (compiled to `~/.config/hub/new_workspace_dialog`)
- `lib/confirm_dialog.swift` - Confirmation dialog (compiled to `~/.config/hub/confirm_dialog`)
- `lib/rename_dialog.swift` - Rename dialog (compiled to `~/.config/hub/rename_dialog`)
- `lib/dashboard_dialog.swift` - Dashboard/status overlay dialog (compiled to `~/.config/hub/dashboard_dialog`)
- `lib/output_window.swift` - Generic text output window used by `hub tree` (compiled to `~/.config/hub/output_window`)
- `lib/progress_banner.swift` - Shared progress, modal overlay, and testing-banner HUD (compiled to `~/.config/hub/progress_banner`)
- `lib/app_switcher.swift` - Cmd-Tab-style app-slot switcher (compiled to `~/.config/hub/app_switcher`)
- `lib/log_viewer.swift` - GUI log viewer for `hub log --window` (compiled to `~/.config/hub/log_viewer`)
- `lib/http_handler.swift` - HTTP/HTTPS URL handler daemon; receives Apple Events, shows HUD, opens URL in slot-2 browser (compiled into `~/Applications/HubHTTPHandler.app`)
- `lib/browser_ctl.swift` - Browser control helper for focus/tab management (compiled to `~/.config/hub/browser_ctl`)
- `lib/spatial_order.swift` - CGWindowList geometry helper; in default mode takes window IDs as args and prints them sorted left-to-right; in `--tree` mode reconstructs and prints the AeroSpace tiling tree (compiled to `~/.config/hub/spatial_order`)
- `lib/float_nudge.swift` - Helper that nudges floating windows below the Hub Bar (compiled to `~/.config/hub/float_nudge`)
- `lib/overlay.swift` and `lib/testing_banner.swift` - Legacy HUD sources; current install uses `lib/progress_banner.swift` for overlays and testing banners
- `lib/hide_menu_bar.applescript` - Menu bar toggle via System Settings UI automation
- `~/.config/hub/apps.json` - App launcher configuration (up to 5 slots, created by install)

## Principles

- **Keyboard-first**: All UI must be fully navigable with keyboard alone. Mouse support is secondary. Dialogs should have tab navigation, enter to submit, escape to cancel, and keyboard shortcuts for actions.
- **UI/CLI parity**: Every action available through a GUI dialog or keybinding must also have an equivalent CLI command. Commands without full flags show a GUI dialog; with all flags + `-y`, they execute silently. The same code path runs from both CLI and keybinding.
- **Single-binary Swift UIs**: GUI elements are standalone Swift files compiled with `swiftc -O -framework Cocoa`. No Xcode project, no storyboards.
- **Config is deployed, not symlinked**: `hub install` deploys configs to their destinations. `aerospace.toml` uses an `__HUB_SCRIPT__` placeholder substituted via sed.
- **Harmless deploy**: Running `hub install` is always safe as an idempotent deploy/reload step after code changes.
- **Responsiveness first**: UI actions must feel instant. Never block the user waiting for background work (app teardown, window closing, etc.) to complete. Move slow work off the critical path — fire-and-forget or background subshells — so the visible state updates immediately.
- **Dismissable HUDs**: Every floating/always-on-top HUD whose lifetime is tied to an external process (banners, progress overlays — anything launched as a background Swift binary fed via stdin/FIFO) MUST render a manual ✕ dismiss button. If the launching process crashes or is `^C`'d before it sends `QUIT`, the button is the user's only escape hatch. Such windows must set `ignoresMouseEvents = false`. Reuse the `ClickView` dismiss-button pattern in `lib/progress_banner.swift` (hover states + `onPress = { dismiss() }`). Modal overlays that auto-dismiss on a deterministic, short-lived action via `start_overlay` / `stop_overlay` are exempt.

## Agent Tools

- `agents/bin/screenshot-bar` - Captures a screenshot of just the Hub Bar region (top of screen). **MUST be used to visually confirm the Hub Bar looks correct after any Hub Bar-related change** — layout, icons, spacing, colors. Run it, read the PNG, and verify before committing. Outputs a PNG path: `agents/bin/screenshot-bar [output.png]`
- `hub testing-banner start|stop|run` - Raise/dismiss a small top-right "stand by" HUD so the user knows not to interact with the UI while you're testing. MUST be used before triggering transient UI, timing-sensitive screenshots, or focus-dependent flows. Always pair `start` with `stop`, even on failure paths.

## Testing Live UI

Only raise the testing banner when your actions will visibly affect the user's screen or could disrupt their work. The banner itself is disruptive, so use it only when necessary.

Raise the banner for:

- Restarting AeroSpace, the Hub Bar, or hub when it causes visible Hub Bar flicker/reload
- Opening a transient UI such as a dialog, HUD, or popup
- Triggering keyboard-shortcut-driven flows where focus matters
- Multi-step verifications where intermediate visible state must persist

Do not raise the banner for:

- Taking screenshots with `agents/bin/screenshot-bar` because it is passive
- Editing files, compiling, reading logs, or running shell commands the user will not see or feel
- Running `hub install` only when it will not restart visible services

Use this lifecycle:

```bash
hub testing-banner start "short description"
# ... do the work ...
hub testing-banner stop
```

Or in one shot:

```bash
hub testing-banner run your-command --with args
```

Rules:

- Raise the banner before the first disruptive action.
- Always call `stop` when done, including on error paths. The banner is obtrusive by design, so leaving it up is worse than never raising it.
- Keep the message short, under about 40 characters. It is a signal, not a log.

## Progress Overlays

Any hub command that takes more than a moment, such as multi-step system changes, compiling, or network operations, should show a progress overlay so the user knows what is happening.

Use `progress_start` / `progress_step` / `progress_stop`, not `start_overlay`, for ordinary progress. `start_overlay` is reserved for the full-screen install/uninstall modal.

```bash
progress_start "Doing the thing"
progress_step "Step one..."
# ... do step one ...
progress_step "Step two..."
# ... do step two ...
progress_step "Done"
progress_stop
```

- Each `progress_step` call marks the previous step complete and starts the new one with a spinner.
- The final `progress_step "Done"` plus `progress_stop` closes cleanly.
- On error paths, call `progress_error "Short message"` instead of `progress_stop`; it shows a red state and auto-dismisses.
- Keep step labels short and action-oriented, such as `Hiding menu bar...` or `Restarting Dock...`.
