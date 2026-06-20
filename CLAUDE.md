# Claude Guidance

## REQUIRED: After every change

IMPORTANT: You MUST follow these steps after completing any set of changes.

- MUST run `hub install` if any file in `config/` or `lib/` changed
- MUST commit and push after every completed set of changes

## REQUIRED: When testing/interacting with the live UI

Only raise the testing banner when your actions will visibly affect the user's
screen or could disrupt their work. The banner itself is disruptive — use it
only when necessary.

**Raise the banner for:**
- Restarting AeroSpace, the Hub Bar, or hub (causes visible Hub Bar flicker/reload)
- Opening a transient UI (dialog, HUD, popup) that appears on screen
- Triggering keyboard-shortcut-driven flows where focus matters
- Multi-step verifications where intermediate visible state must persist

**Do NOT raise the banner for:**
- Taking screenshots with `agents/bin/screenshot-bar` (passive, non-disruptive)
- Editing files, running `hub install` when it won't restart visible services
- Running shell commands, compiling, reading logs
- Anything the user won't see or feel

**Lifecycle:**

```
hub testing-banner start "short description of what you're testing"
# ... do the work ...
hub testing-banner stop
```

Or in one shot:

```
hub testing-banner run -- your-command --with args
```

Rules:
- Raise the banner BEFORE the first disruptive action, not after.
- ALWAYS call `stop` when done, including on error paths. The banner is
  obtrusive by design — leaving it up is worse than never raising it.
- Keep the message short (under ~40 chars). It's a signal, not a log.

## Progress overlays for slow operations

Any hub command that takes more than a moment (multi-step system changes,
compiling, network operations, etc.) should show a progress overlay so the
user knows what's happening.

**Use `progress_start` / `progress_step` / `progress_stop`** (not `start_overlay`
which is reserved for the full-screen install/uninstall modal):

```bash
progress_start "Doing the thing"
progress_step "Step one…"
# ... do step one ...
progress_step "Step two…"
# ... do step two ...
progress_step "✓  Done"
progress_stop
```

- Each `progress_step` call marks the previous step complete (✔) and starts the new one with a spinner.
- The final `progress_step "✓  Done"` + `progress_stop` closes cleanly.
- On error paths, call `progress_error "Short message"` instead of `progress_stop` — it shows a red state and auto-dismisses.
- Keep step labels short and action-oriented (e.g. "Hiding menu bar…", "Restarting Dock…").

@AGENTS.md
