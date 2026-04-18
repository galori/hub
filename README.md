# ws2

A keyboard-first macOS workspace environment that orchestrates [AeroSpace](https://github.com/nikitabobko/AeroSpace) (tiling window manager), [SketchyBar](https://github.com/FelixKratz/SketchyBar) (custom menu bar), and [JankyBorders](https://github.com/FelixKratz/JankyBorders) (window borders) into a unified workspace manager.

## Setup

### Install

```sh
git clone <repo-url> ~/workspace/ws2
cd ~/workspace/ws2
./scripts/ws2 install
```

This will:
- Check and optionally install dependencies via Homebrew (aerospace, sketchybar, borders)
- Deploy the AeroSpace config to `~/.aerospace.toml`
- Deploy the SketchyBar config to `~/.config/sketchybar/`
- Compile Swift binaries (overlay HUD, workspace dialog)
- Install a `ws2` shell alias in your shell config

### Start the environment

```sh
ws2 up
```

Starts AeroSpace, SketchyBar, and JankyBorders. Hides the macOS Dock and menu bar for a distraction-free tiled workspace.

### Stop the environment

```sh
ws2 down
```

Stops all managed services and restores the Dock and menu bar.

### Create a workspace

```sh
ws2 new
```

Opens a dialog to create a named workspace. Supports picking a git repo (with optional worktree creation), assigning a workspace key (1-9, A-Z), and automatically switching to it with a terminal open at the project path.

Keyboard shortcut: `Ctrl+Alt+N` (from anywhere, via AeroSpace keybinding).

### List workspaces

```sh
ws2 list
```

Shows a table of all defined workspaces with their ID, name, path, and root repo.

### Remove a workspace

```sh
ws2 remove        # remove the current workspace (prompts for confirmation)
ws2 remove A      # remove workspace A
ws2 remove A -y   # remove without confirmation
```

Removes a workspace from the configuration, clears its sketchybar label, and moves any windows to workspace 1.

Keyboard shortcut: `Ctrl+Alt+D` (removes current workspace without confirmation).

### Open apps in a workspace

```sh
ws2 open           # open all configured apps in current workspace
ws2 open 1         # open just the first configured app (e.g., iTerm)
ws2 open 2         # open just the second configured app (e.g., Chrome)
```

Opens the apps defined in `~/.config/ws2/apps.json` in the current workspace. Skips apps already open on the workspace. New windows are automatically moved to the correct workspace.

Default apps: iTerm2, Google Chrome, VS Code. Edit `~/.config/ws2/apps.json` to customize (up to 5 slots).

Keyboard shortcuts: `Ctrl+Alt+O` (all apps), `Ctrl+Alt+1-5` (individual slots).

SketchyBar shows clickable app icons on the right side — full-size when open on the current workspace, dimmed when not.

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
| `Ctrl + Alt + O` | Open all configured apps |
| `Ctrl + Alt + 1-5` | Open specific app slot |
| `Alt + Shift + ;` | Enter service mode |

## Guiding Principles

- **Keyboard-first**: Everything should be keyboard-only accessible, similar to how AeroSpace is designed for keyboard use, but also usable with the mouse.
- **UI/CLI parity**: Every action available through a GUI dialog or keybinding must also have an equivalent CLI command.
- **Minimal chrome**: Hide the Dock and menu bar. SketchyBar provides only what's needed.
- **Single command**: `ws2 up` to start, `ws2 down` to stop. No manual config needed after install.

## Dependencies

- [AeroSpace](https://github.com/nikitabobko/AeroSpace) - tiling window manager
- [SketchyBar](https://github.com/FelixKratz/SketchyBar) - custom menu bar
- [JankyBorders](https://github.com/FelixKratz/JankyBorders) - window borders
- macOS with Homebrew
- Swift compiler (included with Xcode Command Line Tools)
