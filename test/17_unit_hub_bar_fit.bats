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
    export CLANG_MODULE_CACHE_PATH="$COMPILE_OUT/module-cache"
    mkdir -p "$CLANG_MODULE_CACHE_PATH"
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
let preferredPad = preferredPillPadH()

guard preferredPad > pillPadH else {
    fail("expected preferred padding \(preferredPad) to exceed minimum padding \(pillPadH)")
}

let paddingPills: [(ws: String, fullName: String, isFocused: Bool)] = [
    ("1", "centerpad", false),
    ("2", "workspace", true),
    ("3", "notch", false),
]
let paddingMaxCap = 60
let preferredFullWidth = stripWidth(pills: paddingPills, cap: paddingMaxCap, focused: "2",
                                    claudeAlert: [], claudeActive: [], padH: preferredPad)
let minimumFullWidth = stripWidth(pills: paddingPills, cap: paddingMaxCap, focused: "2",
                                  claudeAlert: [], claudeActive: [], padH: pillPadH)

let roomyFit = decideFit(
    pills: paddingPills,
    screenW: preferredFullWidth + 16,
    notchMinX: nil,
    notchMaxX: nil,
    isFullscreen: false,
    focused: "2",
    claudeAlert: [],
    claudeActive: [],
    mode: .shrink,
    lastRows: 1)
guard roomyFit.effectivePadH == preferredPad else {
    fail("expected roomy layout to use preferred padding \(preferredPad), got \(roomyFit.effectivePadH)")
}
guard roomyFit.effectiveCap == paddingMaxCap else {
    fail("expected roomy layout to keep max cap \(paddingMaxCap), got \(roomyFit.effectiveCap)")
}

let mediumFit = decideFit(
    pills: paddingPills,
    screenW: preferredFullWidth + 16 - 10,
    notchMinX: nil,
    notchMaxX: nil,
    isFullscreen: false,
    focused: "2",
    claudeAlert: [],
    claudeActive: [],
    mode: .shrink,
    lastRows: 1)
guard mediumFit.effectivePadH < preferredPad && mediumFit.effectivePadH > pillPadH else {
    fail("expected medium layout to reduce padding within bounds, got \(mediumFit.effectivePadH)")
}
guard mediumFit.effectiveCap == paddingMaxCap else {
    fail("expected medium layout to keep labels uncapped while shrinking padding, got cap \(mediumFit.effectiveCap)")
}

let tightFit = decideFit(
    pills: paddingPills,
    screenW: minimumFullWidth + 16 - 8,
    notchMinX: nil,
    notchMaxX: nil,
    isFullscreen: false,
    focused: "2",
    claudeAlert: [],
    claudeActive: [],
    mode: .shrink,
    lastRows: 1)
guard tightFit.effectivePadH == pillPadH else {
    fail("expected tight layout to reach minimum padding \(pillPadH), got \(tightFit.effectivePadH)")
}
guard tightFit.effectiveCap < paddingMaxCap else {
    fail("expected tight layout to reduce cap only after reaching minimum padding, got \(tightFit.effectiveCap)")
}

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
let rightPad = fit.rightPadH ?? fit.effectivePadH
let rightCap = fit.rightCap ?? fit.effectiveCap
guard rightPad > fit.effectivePadH || rightCap > fit.effectiveCap else {
    fail("expected right segment to relax beyond global padding/cap \(fit.effectivePadH)/\(fit.effectiveCap), got \(rightPad)/\(rightCap)")
}

let rightPills = Array(pills[split...])
let expectedRightIDs = Set(rightPills.map { $0.ws })
guard fit.rightWsIDs == expectedRightIDs else {
    fail("expected right relaxation IDs \(expectedRightIDs), got \(fit.rightWsIDs)")
}

let baseWidth = stripWidth(pills: rightPills, cap: fit.effectiveCap, focused: "3",
                           claudeAlert: [], claudeActive: [], padH: fit.effectivePadH)
let relaxedWidth = stripWidth(pills: rightPills, cap: rightCap, focused: "3",
                              claudeAlert: [], claudeActive: [], padH: rightPad)
guard relaxedWidth > baseWidth else {
    fail("expected relaxed right width \(relaxedWidth) to exceed base width \(baseWidth)")
}
guard relaxedWidth <= rightSegW else {
    fail("expected relaxed right width \(relaxedWidth) to fit right segment \(rightSegW)")
}

let previousRefreshFit = FitDecision(
    rows: 1,
    rowAssignment: [[0, 1, 2]],
    effectiveCap: 8,
    effectivePadH: pillPadH,
    row0Split: 1,
    leftCap: nil,
    leftPadH: nil,
    leftWsIDs: [],
    rightCap: 14,
    rightPadH: nil,
    rightWsIDs: Set(["2", "3"]))
let afterDeletionFit = FitDecision(
    rows: 1,
    rowAssignment: [[0, 1]],
    effectiveCap: 8,
    effectivePadH: pillPadH,
    row0Split: 1,
    leftCap: nil,
    leftPadH: nil,
    leftWsIDs: [],
    rightCap: 18,
    rightPadH: nil,
    rightWsIDs: Set(["3"]))

let rebuildAfterDeletion = refreshRequiresRebuild(
    lastFitRows: 1,
    lastFitCap: 8,
    lastFitDecision: previousRefreshFit,
    lastVisiblePillIDs: ["1", "2", "3"],
    previousMode: .shrink,
    currentMode: .shrink,
    currentPillIDs: ["1", "3"],
    existingPillIDs: Set(["1", "2", "3"]),
    newFit: afterDeletionFit)
guard rebuildAfterDeletion else {
    fail("expected deletion of an existing visible pill to rebuild notch row stacks")
}

let previousPaddingFit = FitDecision(
    rows: 1,
    rowAssignment: [[0, 1]],
    effectiveCap: 60,
    effectivePadH: pillPadH,
    row0Split: nil,
    leftCap: nil,
    leftPadH: nil,
    leftWsIDs: [],
    rightCap: nil,
    rightPadH: nil,
    rightWsIDs: [])
let afterPaddingFit = FitDecision(
    rows: 1,
    rowAssignment: [[0, 1]],
    effectiveCap: 60,
    effectivePadH: pillPadH + 1,
    row0Split: nil,
    leftCap: nil,
    leftPadH: nil,
    leftWsIDs: [],
    rightCap: nil,
    rightPadH: nil,
    rightWsIDs: [])
guard !fitStructureMatchesForRefresh(previousPaddingFit, afterPaddingFit) else {
    fail("expected padding-only fit changes to refresh workspace widths")
}
SWIFT

    swiftc -D HUB_BAR_TEST -O -o "$COMPILE_OUT/hub_bar_fit" \
        -framework Cocoa "$THEME_SRC" "$harness"
    "$COMPILE_OUT/hub_bar_fit"
}

@test "fullscreen notch shrink relaxes right-side labels when left segment constrains global cap" {
    compile_and_run_harness
}
