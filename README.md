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
| `Alt + Shift + ;` | Enter service mode |

## Guiding Principles

- **Keyboard-first**: Everything should be keyboard-only accessible, similar to how AeroSpace is designed for keyboard use, but also usable with the mouse.
- **Minimal chrome**: Hide the Dock and menu bar. SketchyBar provides only what's needed.
- **Single command**: `ws2 up` to start, `ws2 down` to stop. No manual config needed after install.

## Dependencies

- [AeroSpace](https://github.com/nikitabobko/AeroSpace) - tiling window manager
- [SketchyBar](https://github.com/FelixKratz/SketchyBar) - custom menu bar
- [JankyBorders](https://github.com/FelixKratz/JankyBorders) - window borders
- macOS with Homebrew
- Swift compiler (included with Xcode Command Line Tools)
