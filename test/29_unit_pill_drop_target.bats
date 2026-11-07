#!/usr/bin/env bats
# Unit tests for the pure Hub Bar drag-and-drop logic (drop position and `hub reorder` arguments).

REPO_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
THEME_SRC="$REPO_DIR/lib/theme.swift"
HUB_BAR_SRC="$REPO_DIR/lib/hub_bar.swift"

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

@test "drop target picks the left neighbour, the line position and hub reorder args" {
    local harness="$COMPILE_OUT/main.swift"
    cp "$HUB_BAR_SRC" "$harness"
    cat >> "$harness" <<'SWIFT'
import Cocoa

func fail(_ message: String) -> Never {
    fputs(message + "\n", stderr)
    exit(1)
}

// One row: pills 1,2,3,4,5 each 50 wide with a 4pt gap, starting at x=8.
func row(_ ids: [String], y: CGFloat = 10) -> [(ws: String, frame: NSRect)] {
    var x: CGFloat = 8
    return ids.map { id in
        defer { x += 54 }
        return (id, NSRect(x: x, y: y, width: 50, height: 32))
    }
}
let one = row(["1", "2", "3", "4", "5"])   // midX: 33, 87, 141, 195, 249; gaps at 58, 112, ...

// Drag 2 to the gap between 4 and 5 -> lands after 4.
guard let a = pillDropTarget(frames: one, dragged: "2", point: NSPoint(x: 222, y: 26)),
      a.after == "4", abs(a.lineX - 222) < 0.01 else {
    fail("expected after 4 at x=222")
}
// Left of everything -> first slot.
guard let b = pillDropTarget(frames: one, dragged: "3", point: NSPoint(x: 2, y: 26)),
      b.after == nil, b.lineX < 8 else { fail("expected first slot") }
// Right of everything -> after the last pill that is not the dragged one.
guard let c = pillDropTarget(frames: one, dragged: "2", point: NSPoint(x: 900, y: 26)),
      c.after == "5" else { fail("expected after 5") }
// The dragged pill itself is ignored: dropping on its own spot lands after its left neighbour.
guard let d = pillDropTarget(frames: one, dragged: "3", point: NSPoint(x: 141, y: 26)),
      d.after == "2" else { fail("expected after 2, got \(String(describing: pillDropTarget(frames: one, dragged: "3", point: NSPoint(x: 141, y: 26))))") }
// No other pill visible (empty monitor) -> nil.
guard pillDropTarget(frames: row(["2"]), dragged: "2", point: NSPoint(x: 10, y: 26)) == nil else {
    fail("expected nil for an empty target")
}

// Two rows (expand mode). Row 0 is higher (larger y). Row 1 holds 4,5.
let two = row(["1", "2", "3"], y: 50) + row(["4", "5"], y: 10)
guard let e = pillDropTarget(frames: two, dragged: "1", point: NSPoint(x: 2, y: 26)),
      e.after == "3", e.lineMidY == 26 else { fail("expected start of row 1 to land after 3") }
guard let f = pillDropTarget(frames: two, dragged: "5", point: NSPoint(x: 70, y: 66)),
      f.after == "1", f.lineMidY == 66 else { fail("expected row 0 gap after 1") }

// hub reorder arguments
guard reorderArguments(ws: "2", target: a, sourceMonitor: 1, dropMonitor: 1) == ["reorder", "2", "--after", "4"] else {
    fail("bad args for same monitor")
}
guard reorderArguments(ws: "2", target: b, sourceMonitor: 1, dropMonitor: 1) == ["reorder", "2", "--first"] else {
    fail("bad args for first")
}
guard reorderArguments(ws: "2", target: a, sourceMonitor: 1, dropMonitor: 2) == ["reorder", "2", "--after", "4", "--monitor", "2"] else {
    fail("bad args for other monitor")
}
guard reorderArguments(ws: "2", target: nil, sourceMonitor: 1, dropMonitor: 2) == ["reorder", "2", "--monitor", "2"] else {
    fail("bad args for empty monitor")
}
SWIFT
    swiftc -D HUB_BAR_TEST -O -o "$COMPILE_OUT/drop_target" -framework Cocoa \
        "$THEME_SRC" "$REPO_DIR/lib/hotkey_protocol.swift" "$harness" 2>&1
    "$COMPILE_OUT/drop_target"
}
