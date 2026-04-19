# helm Development Guide

## Project Structure

- `scripts/helm` - Main shell script (install, up, down, new, list, remove, rename, open commands)
- `config/aerospace.toml` - AeroSpace config template (`__HELM_SCRIPT__` placeholder replaced during install)
- `config/sketchybar/` - SketchyBar config and plugin scripts
- `config/sketchybar/plugins/app_launcher.sh` - Updates app icon visual state on workspace change
- `lib/overlay.swift` - Status overlay HUD (compiled to ~/.config/helm/overlay)
- `lib/new_workspace_dialog.swift` - Workspace creation dialog (compiled to ~/.config/helm/new_workspace_dialog)
- `lib/confirm_dialog.swift` - Confirmation dialog (compiled to ~/.config/helm/confirm_dialog)
- `lib/rename_dialog.swift` - Rename dialog (compiled to ~/.config/helm/rename_dialog)
- `lib/hide_menu_bar.applescript` - Menu bar toggle via System Settings UI automation
- `~/.config/helm/apps.json` - App launcher configuration (up to 5 slots, created by install)

## Principles

- **Keyboard-first**: All UI must be fully navigable with keyboard alone. Mouse support is secondary. Dialogs should have tab navigation, enter to submit, escape to cancel, and keyboard shortcuts for actions.
- **UI/CLI parity**: Every action available through a GUI dialog or keybinding must also have an equivalent CLI command. Commands without full flags show a GUI dialog; with all flags + `-y`, they execute silently. The same code path runs from both CLI and keybinding.
- **Single-binary Swift UIs**: GUI elements are standalone Swift files compiled with `swiftc -O -framework Cocoa`. No Xcode project, no storyboards.
- **Config is deployed, not symlinked**: `helm install` deploys configs to their destinations. Both aerospace.toml and sketchybar configs use `__HELM_SCRIPT__` placeholder substituted via sed.

## Workflow

After changing any file in `config/` or `lib/`, run `helm install` to deploy and recompile.

Create a git commit after every completed set of changes.
