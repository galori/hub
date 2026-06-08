---
name: hub-new
description: Create a new hub workspace (worktree off the current repo) for the task described in $ARGUMENTS. Uses `hub new` non-interactively. Optionally pass a prompt to launch Claude Code in the new terminal window (works with any configured terminal: iTerm2, Ghostty, etc.).
---

Create a new hub workspace for the task: **$ARGUMENTS**

Steps:

1. Sluggify the task description into a short branch/worktree name. Lowercase, hyphens for spaces, drop punctuation, keep it under ~40 chars. Example: "Fix login redirect bug" → `fix-login-redirect-bug`.

2. Detect the current git repo root:
   ```bash
   git rev-parse --show-toplevel 2>/dev/null
   ```

3. Decide whether to include `--prompt`:
   - If $ARGUMENTS contains a clear task description that would be useful to pass directly into Claude Code in the new workspace, include `--prompt "<task description>"`.
   - Use the original natural-language task description (not the slug) as the prompt value.
   - Omit `--prompt` if the task is just a workspace name/label with no actionable work to hand off.

4. Build the command:
   - In a git repo:
     ```bash
     hub new --path <repo-root> --worktree <slug> --apps 1 [--prompt "<task description>"]
     ```
   - Not in a repo:
     ```bash
     hub new --no-repo --name <slug> --apps 1 [--prompt "<task description>"]
     ```

5. Echo the exact `hub new` invocation BEFORE running it so the user can audit. Don't pass `--id` or `--color` — let `hub new` apply its defaults (auto-allocated ID, color from `.envrc.local`). Always pass `--apps 1` to open only the terminal (slot 1) in the new workspace.

6. After it completes, report the new workspace ID and path. Stay in the current shell — don't `cd` into the worktree.

Notes:
- `hub new` runs non-interactively whenever any flag is passed.
- The prompt is staged in a temp file by `hub new`; it tells Claude to read from that file so no shell escaping issues arise.
- If the slug looks ambiguous or you're unsure of the repo, ask the user once before invoking.
- Don't run `hub new` without flags — that opens the GUI dialog.
