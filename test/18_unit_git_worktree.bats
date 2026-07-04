#!/usr/bin/env bats
# Unit tests for git worktree creation helpers.

REPO_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
HUB_SCRIPT="$REPO_DIR/scripts/hub"

setup_git_identity() {
    local repo="$1"
    git -C "$repo" config user.name "hub-test"
    git -C "$repo" config user.email "hub-test@localhost"
}

source_hub_and_add_worktree() {
    local repo_root="$1" branch="$2" worktree_path="$3"
    HUB_SCRIPT="$HUB_SCRIPT" \
    REPO_ROOT="$repo_root" \
    BRANCH="$branch" \
    WORKTREE_PATH="$worktree_path" \
    bash -c '
        set --
        source "$HUB_SCRIPT" >/dev/null 2>&1
        _git_worktree_add "$REPO_ROOT" "$BRANCH" "$WORKTREE_PATH"
    '
}

@test "_git_worktree_add creates new branches from fetched origin default branch" {
    local remote="$BATS_TEST_TMPDIR/origin.git"
    local repo="$BATS_TEST_TMPDIR/repo"
    local updater="$BATS_TEST_TMPDIR/updater"
    local worktree="$BATS_TEST_TMPDIR/worktree"

    git init --bare "$remote"

    git init -b main "$repo"
    setup_git_identity "$repo"
    echo "base" > "$repo/README.md"
    git -C "$repo" add README.md
    git -C "$repo" commit -m "Initial commit" --no-gpg-sign
    git -C "$repo" remote add origin "$remote"
    git -C "$repo" push -u origin main

    git clone "$remote" "$updater"
    setup_git_identity "$updater"
    git -C "$updater" switch main
    echo "remote only" > "$updater/remote-only.txt"
    git -C "$updater" add remote-only.txt
    git -C "$updater" commit -m "Add remote-only file" --no-gpg-sign
    git -C "$updater" push origin main

    run source_hub_and_add_worktree "$repo" "feature-from-origin" "$worktree"

    [[ "$status" -eq 0 ]]
    [[ -f "$worktree/remote-only.txt" ]]
    [[ "$(git -C "$worktree" branch --show-current)" == "feature-from-origin" ]]
}
