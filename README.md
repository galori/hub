# hub

<img src="assets/hub-logo.png" width="20%" align="right" style="padding:20px; ">

A keyboard-first macOS workspace environment that orchestrates [AeroSpace](https://github.com/nikitabobko/AeroSpace) (tiling window manager), [SketchyBar](https://github.com/FelixKratz/SketchyBar) (custom menu bar), and [JankyBorders](https://github.com/FelixKratz/JankyBorders) (window borders) into a unified workspace manager.

<img src="assets/hub-screenshot.png">
<br/>

https://github.com/user-attachments/assets/931a020c-86c1-44b4-8c0b-ad8610f6ebd2

<br clear="all">

## Keybindings

All keybindings use `Alt` as the modifier (AeroSpace default):

| Key | Action |
|-----|--------|
| `Alt + [1-9, A-Z]` | Switch to workspace |
| `Alt + Shift + [1-9, A-Z]` | Move window to workspace |
| `Alt + H/J/K/L` | Focus left/down/up/right |
| `Alt + Shift + H/J/K/L` | Move window left/down/up/right |
| `Alt + /` | Toggle tiles horizontal/vertical |
| `Alt + ,` | Toggle accordion layout |
| `Alt + -/=` | Resize window |
| `Alt + Tab` | Switch to previous workspace |
| `Alt + Shift + Tab` | Move workspace to next monitor |
| `Ctrl + Alt + N` | Create new workspace |
| `Ctrl + Alt + D` | Remove current workspace |
| `Ctrl + Alt + R` | Rename current workspace |
| `Ctrl + Alt + O` | Open all configured apps |
| `Ctrl + Alt + 1-5` | Open specific app slot |
| `Ctrl + Alt + -` | Shrink workspace labels |
| `Ctrl + Alt + =` | Grow workspace labels |
| `Alt + Shift + ;` | Enter service mode |

## Setup

### Install

```sh
git clone <repo-url> ~/workspace/hub
cd ~/workspace/hub
./scripts/hub install
```

This will:
- Check and optionally install dependencies via Homebrew (aerospace, sketchybar, borders)
- Deploy the AeroSpace config to `~/.aerospace.toml`
- Deploy the SketchyBar config to `~/.config/sketchybar/`
- Compile Swift binaries (overlay HUD, workspace dialog)
- Install a `hub` shell alias in your shell config

### Start the environment

```sh
hub up
```

Starts AeroSpace, SketchyBar, and JankyBorders. Hides the macOS Dock and menu bar for a distraction-free tiled workspace.

### Stop the environment

```sh
hub down
```

Stops all managed services and restores the Dock and menu bar.

### Create a workspace

Press **`Ctrl+Alt+N`** from anywhere to open the new workspace dialog.

Opens a dialog to create a named workspace. Supports picking a git repo (with optional worktree creation), assigning a workspace key (1-9, A-Z), and automatically switching to it with a terminal open at the project path.

CLI alternative: `hub new`

### List workspaces

SketchyBar displays all workspace labels in the menu bar at all times.

CLI alternative: `hub list` — shows a table of all defined workspaces with their ID, name, path, and root repo.

### Remove a workspace

Press **`Ctrl+Alt+D`** to remove the current workspace (prompts for confirmation).

Removes the workspace from configuration, clears its sketchybar label, and moves any windows to workspace 1. For worktree-backed workspaces, offers to teardown and remove the git worktree.

CLI alternative:
```sh
hub remove        # remove the current workspace (prompts for confirmation)
hub remove A      # remove workspace A
hub remove A -y   # remove without confirmation
```

### Rename a workspace

Press **`Ctrl+Alt+R`** to rename the current workspace.

Opens a dialog to rename the workspace. Updates the sketchybar label immediately.

CLI alternative:
```sh
hub rename        # rename the current workspace
hub rename A      # rename workspace A
```

### Open apps in a workspace

Press **`Ctrl+Alt+O`** to open all configured apps in the current workspace, or **`Ctrl+Alt+1-5`** for individual app slots.

Opens the apps defined in `~/.config/hub/apps.json` in the current workspace. Skips apps already open on the workspace. New windows are automatically moved to the correct workspace.

Default apps: iTerm2, Google Chrome, VS Code. Edit `~/.config/hub/apps.json` to customize (up to 5 slots).

SketchyBar shows clickable app icons on the right side — full-size when open on the current workspace, dimmed when not.

CLI alternative:
```sh
hub open           # open all configured apps in current workspace
hub open 1         # open just the first configured app (e.g., iTerm)
hub open 2         # open just the second configured app (e.g., Chrome)
```

## Guiding Principles

- **Keyboard-first**: Everything should be keyboard-only accessible, similar to how AeroSpace is designed for keyboard use, but also usable with the mouse.
- **UI/CLI parity**: Every action available through a GUI dialog or keybinding must also have an equivalent CLI command.
- **Minimal chrome**: Hide the Dock and menu bar. SketchyBar provides only what's needed.
- **Single command**: `hub up` to start, `hub down` to stop. No manual config needed after install.

## Development

If working from a worktree, run `hub reboot` after making changes to get everything running from the worktree path for testing.

## Dependencies

- [AeroSpace](https://github.com/nikitabobko/AeroSpace) - tiling window manager
- [SketchyBar](https://github.com/FelixKratz/SketchyBar) - custom menu bar
- [JankyBorders](https://github.com/FelixKratz/JankyBorders) - window borders
- macOS with Homebrew
- Swift compiler (included with Xcode Command Line Tools)
