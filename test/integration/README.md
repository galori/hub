# Hub Live Integration Tests

These tests run against **real, running macOS services** (AeroSpace, SketchyBar,
JankyBorders). They are entirely separate from the stubbed unit-test suite in
`test/` and are gated so they never run by accident.

---

## Prerequisites

### Machine

> **Only run these tests on a dedicated / isolated macOS session** — e.g. a
> standalone test machine or a test user. Test 1 (`01_install_up.bats`) is
> intentionally destructive:
>
> - `rm -rf ~/.config/sketchybar` then redeploys hub's config
> - overwrites `~/.aerospace.toml`
> - appends an alias line to `~/.zshrc` / `~/.bash_profile` (guarded; idempotent)
> - copies `commands/*.md` into `~/.claude/commands/`
> - runs `swiftc` to recompile all Swift HUD binaries
> - calls `hub up`, which swaps the system default browser to HubHTTPHandler

### Software — must be pre-installed via Homebrew

| Tool | Install |
|---|---|
| `bats-core` | `brew install bats-core` |
| `aerospace` | `brew install --cask nikitabobko/tap/aerospace` |
| `sketchybar` | `brew install sketchybar` |
| `borders` (JankyBorders) | `brew install FelixKratz/formulae/borders` |
| `jq` | `brew install jq` |

### macOS Permissions (for the terminal running the tests)

The terminal you run tests from must have:

1. **Accessibility** — System Settings → Privacy & Security → Accessibility  
   Required so `aerospace` CLI can query and switch workspaces.
2. **Automation** (may prompt on first run) — Terminal/iTerm needs permission to
   control System Events / Finder if aerospace needs it.

These permissions cannot be granted in CI — they require interactive approval
in a live GUI session.

### Session

Tests must run in a **real `loginwindow` GUI session** on the display. SSH
sessions without a window server (`DISPLAY` unset, headless) will not work
because both SketchyBar and AeroSpace bind to the WindowServer.

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
| `01_install_up.bats` | `hub install` (non-interactive) + `hub up` — services start, sketchybar loaded with hub config, clock widget live |
| `02_new_workspace.bats` | `hub new` — worktree created, workspaces.json entry, `hub list`, sketchybar pill |
| `03_new_workspace_custom_setup.bats` | Same + `.superset/config.json` `"setup"` hook writes a marker file in the worktree |

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
