# Hub Live Integration Tests

These tests run against **real, running macOS services** (AeroSpace,
JankyBorders, the native Swift Hub Bar). They are entirely separate from the
stubbed unit-test suite in `test/` and are gated so they never run by accident.

---

## Prerequisites

### Machine

Test 1 (`01_install_up.bats`) runs a full `hub install` + `hub up`. Run this
suite on the dedicated macOS runner, a test user, or a machine where it is
acceptable to exercise the installed/running Hub:

- overwrites `~/.aerospace.toml` from `config/aerospace.toml` — same result
- shell rc / global gitignore / `~/.claude/commands` — all guarded; no-op if already installed
- recompiles Swift HUD binaries (including the Hub Bar)
- `hub up` restarts the Hub Bar (brief flicker) and reloads AeroSpace config

Visible side effects on your screen during the suite:
- A brief bar reload flicker (test 1)
- AeroSpace focus switches to the newly created test workspace (tests 2/3), then back after cleanup
- Hub fullscreen mode is toggled on/off while verifying AeroSpace top padding and revealed menu-bar spacing (tests 4/6)

> For routine worktree development, use `make test-fast` or `make test-local`.
> Live integration is intentionally reserved for CI/PR checks or explicit
> installed-Hub validation.

### Software — must be pre-installed via Homebrew

| Tool | Install |
|---|---|
| `bats-core` | `brew install bats-core` |
| `aerospace` | `brew install --cask nikitabobko/tap/aerospace` |
| `borders` (JankyBorders) | `brew install FelixKratz/formulae/borders` |
| `jq` | `brew install jq` |
| `imagemagick` | `brew install imagemagick` |

### macOS Permissions (for the terminal running the tests)

The terminal you run tests from must have:

1. **Accessibility** — System Settings → Privacy & Security → Accessibility  
   Required so `aerospace` CLI can query and switch workspaces.
2. **Automation** (may prompt on first run) — Terminal/iTerm needs permission to
   control System Events / Finder if aerospace needs it.

These permissions cannot be granted in CI — they require interactive approval
in a live GUI session.

### Session

Tests must run in a **real `loginwindow` GUI session** on the display. The guard
checks for `WindowServer` (present only in a live session). SSH sessions without
a window server (headless) will self-skip.

AeroSpace and the Hub Bar do **not** need to be running before you start —
test 1 launches them via `hub up`.

---

## Running

```bash
# From the repo root:
make test-integration

# Or directly:
HUB_RUN_INTEGRATION=1 bats test/integration/
```

Without `HUB_RUN_INTEGRATION=1`, every test auto-skips with a clear message,
so a stray `bats test/integration/` run is harmless.

The default `make test` / `bats test/` commands are **non-recursive** — they
never touch `test/integration/`.

---

## Test inventory

| File | What it tests |
|---|---|
| `01_install_up.bats` | `hub install` (non-interactive) + `hub up` — services start, Hub Bar running, hub_bar_labels file created |
| `02_new_workspace.bats` | `hub new` — worktree created, workspaces.json entry, `hub list`, hub_bar_labels entry |
| `03_new_workspace_custom_setup.bats` | Same + `.superset/config.json` `"setup"` hook writes a marker file in the worktree |
| `04_fullscreen_padding.bats` | `hub fullscreen on/off` — AeroSpace `outer.top` keeps tiled windows below the Hub Bar; Tahoe also checks cursor-at-top menu-bar reveal padding |
| `05_screenshot_bar_cropped.bats` | macOS Sequoia only — `screenshot-bar-cropped` does not leak green desktop pixels in normal mode |
| `06_fullscreen_revealed_menu_bar_screenshot.bats` | macOS Tahoe+ — screenshot crop verifies the Hub Bar top strip is visible below the revealed menu bar in Hub fullscreen |

---

## Cleanup

Tests create workspaces with unique timestamped names (`ittest-<epoch>-<rand>`)
and remove them in `teardown()` via `hub remove <id> -y`. Fixture repos live in
`$BATS_TEST_TMPDIR` and are auto-cleaned by Bats.

If a test crashes mid-run without cleanup, remove lingering workspaces with:

```bash
hub list          # find ittest-* names / IDs
hub remove <ID> -y
```

---

## Adding new tests

1. Create `test/integration/NN_<topic>.bats`
2. Load the helpers: `load helpers`
3. Call `require_live_session` in every `setup()` or `@test`
4. Use `unique_ws_name`, `make_fixture_repo`, `wait_for`, `cleanup_workspace`
   from `helpers.bash` — extend that file for any new shared logic
