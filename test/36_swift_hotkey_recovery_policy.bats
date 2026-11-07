#!/usr/bin/env bats

REPO_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

setup() {
    if [[ -n "${SKIP_SWIFT_COMPILE:-}" ]]; then
        skip "SKIP_SWIFT_COMPILE set"
    fi
    if ! command -v swiftc >/dev/null 2>&1; then
        skip "swiftc not available"
    fi
    COMPILE_OUT="$(mktemp -d)"
    export CLANG_MODULE_CACHE_PATH="$COMPILE_OUT/module-cache"
    mkdir -p "$CLANG_MODULE_CACHE_PATH"
    cat > "$COMPILE_OUT/main.swift" <<'SWIFT'
import Foundation

var budget = HotkeyRestartBudget()
precondition(budget.nextAllowedTime(at: 0) == nil)
budget.record(at: 0)
precondition(budget.nextAllowedTime(at: 59) == 60)
precondition(budget.nextAllowedTime(at: 60) == nil)
budget.record(at: 60)
budget.record(at: 120)
precondition(budget.nextAllowedTime(at: 121) == 600)
precondition(budget.nextAllowedTime(at: 600) == nil)
SWIFT
    swiftc -O -o "$COMPILE_OUT/hotkey_recovery_policy" \
        "$REPO_DIR/lib/hotkey_recovery_policy.swift" "$COMPILE_OUT/main.swift"
}

teardown() {
    if [[ -n "${COMPILE_OUT:-}" ]]; then rm -rf "$COMPILE_OUT"; fi
}

@test "automatic recovery permits one restart per minute and three per ten minutes" {
    run "$COMPILE_OUT/hotkey_recovery_policy"
    [[ "$status" -eq 0 ]]
}
