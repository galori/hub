# ws2 Development Guide

## Project Structure

- `scripts/ws2` - Main shell script (install, up, down, new commands)
- `config/aerospace.toml` - AeroSpace config template (`__WS2_SCRIPT__` placeholder replaced during install)
- `config/sketchybar/` - SketchyBar config and plugin scripts
- `lib/overlay.swift` - Status overlay HUD (compiled to ~/.config/ws2/overlay)
- `lib/new_workspace_dialog.swift` - Workspace creation dialog (compiled to ~/.config/ws2/new_workspace_dialog)
- `lib/confirm_dialog.swift` - Confirmation dialog (compiled to ~/.config/ws2/confirm_dialog)
- `lib/hide_menu_bar.applescript` - Menu bar toggle via System Settings UI automation

## Principles

- **Keyboard-first**: All UI must be fully navigable with keyboard alone. Mouse support is secondary. Dialogs should have tab navigation, enter to submit, escape to cancel, and keyboard shortcuts for actions.
- **UI/CLI parity**: Every action available through a GUI dialog or keybinding must also have an equivalent CLI command. Commands without full flags show a GUI dialog; with all flags + `-y`, they execute silently. The same code path runs from both CLI and keybinding.
- **Single-binary Swift UIs**: GUI elements are standalone Swift files compiled with `swiftc -O -framework Cocoa`. No Xcode project, no storyboards.
- **Config is deployed, not symlinked**: `ws2 install` copies configs to their destinations. The aerospace.toml uses `__WS2_SCRIPT__` placeholder substituted via sed.

## Workflow

After changing any file in `config/` or `lib/`, run `ws2 install` to deploy and recompile.
