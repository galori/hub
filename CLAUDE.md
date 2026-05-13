# Claude Guidance

## REQUIRED: After every change

IMPORTANT: You MUST follow these steps after completing any set of changes.

- MUST run `hub install` if any file in `config/` or `lib/` changed
- MUST commit and push after every completed set of changes

## REQUIRED: When testing/interacting with the live UI

The user is typically working in a separate workspace while you run tests. If
you trigger a popup, dialog, or take a screenshot of a transient UI element,
the user may Cmd-Tab, click, or switch workspaces mid-test and invalidate your
result. To signal "don't touch", raise the testing banner before doing any of:

- Opening a transient UI (popup, dialog, HUD)
- Taking timing-sensitive screenshots with `agents/bin/screenshot-bar` or `screencapture`
- Triggering keyboard-shortcut-driven flows where focus matters
- Multi-step verifications where intermediate state must persist

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
- Raise the banner BEFORE the first test action, not after.
- ALWAYS call `stop` when done, including on error paths. The banner is
  obtrusive by design — leaving it up is worse than never raising it.
- Keep the message short (under ~40 chars). It's a signal, not a log.

@AGENTS.md
