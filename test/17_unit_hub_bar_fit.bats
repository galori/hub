#!/usr/bin/env bats
# Unit tests for pure Hub Bar pill fit decisions.

REPO_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
LIB_DIR="$REPO_DIR/lib"
THEME_SRC="$LIB_DIR/theme.swift"
HUB_BAR_SRC="$LIB_DIR/hub_bar.swift"

setup() {
    if [[ -n "${SKIP_SWIFT_COMPILE:-}" ]]; then
        skip "SKIP_SWIFT_COMPILE set"
    fi
    if ! command -v swiftc &>/dev/null; then
        skip "swiftc not available"
    fi
    export COMPILE_OUT
    COMPILE_OUT="$(mktemp -d)"
}

teardown() {
    if [[ -n "${COMPILE_OUT:-}" ]]; then rm -rf "$COMPILE_OUT"; fi
}

compile_and_run_harness() {
    local harness="$COMPILE_OUT/main.swift"
    cp "$HUB_BAR_SRC" "$harness"
    cat >> "$harness" <<'SWIFT'
import Cocoa

func fail(_ message: String) -> Never {
    fputs(message + "\n", stderr)
    exit(1)
}

let pills: [(ws: String, fullName: String, isFocused: Bool)] = [
    ("1", "dgapp", false),
    ("2", "custom-bins", false),
    ("3", "hub", true),
    ("8", "shadow_validator", false),
    ("9", "code-reviews", false),
    ("A", "eng-vulns-todo", false),
    ("D", "vulns", false),
    ("G", "brand-code-reviews", false),
    ("I", "standardize_agent", false),
    ("M", "fix-tax-capture", false),
    ("Z", "General", false),
]

let screenW: CGFloat = 1512
let notchMinX: CGFloat = 675
let notchMaxX: CGFloat = 850
let rightSegW = max(0, (screenW - 8) - (notchMaxX + 2))

let fit = decideFit(
    pills: pills,
    screenW: screenW,
    notchMinX: notchMinX,
    notchMaxX: notchMaxX,
    isFullscreen: true,
    focused: "3",
    claudeAlert: [],
    claudeActive: [],
    mode: .shrink,
    lastRows: 1)

guard fit.rows == 1 else {
    fail("expected shrink layout to stay on one row, got \(fit.rows)")
}
guard let split = fit.row0Split, split > 0, split < pills.count else {
    fail("expected a two-sided notch split, got \(String(describing: fit.row0Split))")
}
guard let rightCap = fit.rightCap, rightCap > fit.effectiveCap else {
    fail("expected right segment to relax beyond global cap \(fit.effectiveCap), got \(String(describing: fit.rightCap))")
}

let rightPills = Array(pills[split...])
let expectedRightIDs = Set(rightPills.map { $0.ws })
guard fit.rightWsIDs == expectedRightIDs else {
    fail("expected right relaxation IDs \(expectedRightIDs), got \(fit.rightWsIDs)")
}

let baseWidth = stripWidth(pills: rightPills, cap: fit.effectiveCap, focused: "3",
                           claudeAlert: [], claudeActive: [])
let relaxedWidth = stripWidth(pills: rightPills, cap: rightCap, focused: "3",
                              claudeAlert: [], claudeActive: [])
guard relaxedWidth > baseWidth else {
    fail("expected relaxed right width \(relaxedWidth) to exceed base width \(baseWidth)")
}
guard relaxedWidth <= rightSegW else {
    fail("expected relaxed right width \(relaxedWidth) to fit right segment \(rightSegW)")
}
SWIFT

    swiftc -D HUB_BAR_TEST -O -o "$COMPILE_OUT/hub_bar_fit" \
        -framework Cocoa "$THEME_SRC" "$harness"
    "$COMPILE_OUT/hub_bar_fit"
}

@test "fullscreen notch shrink relaxes right-side labels when left segment constrains global cap" {
    compile_and_run_harness
}
