import Cocoa

// float_nudge <pid> <min-y-from-top>
//
// Moves any window owned by <pid> whose top edge is within <min-y-from-top>
// pixels of the screen top so that its top edge sits exactly at min-y-from-top.
// This prevents floating windows from spawning under the Hub Bar.
//
// <pid>            — the app's process ID (from `aerospace list-windows --format %{app-pid}`)
// <min-y-from-top> — pixels from the absolute screen top that must stay clear (e.g. 48)
//
// Exit 0 on success or if no adjustment needed; non-zero on fatal error.

guard CommandLine.arguments.count == 3,
      let pid    = pid_t(CommandLine.arguments[1]),
      let minY   = Double(CommandLine.arguments[2]), minY >= 0
else {
    fputs("Usage: float_nudge <pid> <min-y-from-top>\n", stderr)
    exit(1)
}

let threshold = CGFloat(minY)

// ── Identify screen heights (needed for CG↔NS coordinate conversions) ─────

// CGWindowList Y is measured from the top of the primary screen (top-left origin).
// AX position Y is also measured from the primary screen top.
// NSScreen Y is from the bottom-left of the primary screen.
let primaryH: CGFloat = NSScreen.screens.first.map { $0.frame.height } ?? 800

// ── Ask the Accessibility API for this app's windows ──────────────────────

let appRef = AXUIElementCreateApplication(pid)

var windowsRef: CFTypeRef?
let axErr = AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsRef)
guard axErr == .success, let windows = windowsRef as? [AXUIElement], !windows.isEmpty else {
    // App may not have Accessibility support — silently exit.
    exit(0)
}

for axWin in windows {
    var posRef: CFTypeRef?, sizeRef: CFTypeRef?
    guard AXUIElementCopyAttributeValue(axWin, kAXPositionAttribute as CFString, &posRef) == .success,
          AXUIElementCopyAttributeValue(axWin, kAXSizeAttribute as CFString, &sizeRef) == .success,
          let posVal = posRef, let sizeVal = sizeRef
    else { continue }

    var pos  = CGPoint.zero
    var size = CGSize.zero
    // AX uses a top-left origin measured from the primary screen top (same as CG).
    AXValueGetValue(posVal  as! AXValue, .cgPoint, &pos)
    AXValueGetValue(sizeVal as! AXValue, .cgSize,  &size)

    // Window top edge in CG/AX coordinates (distance from primary screen top).
    let topEdge = pos.y

    // Only nudge windows whose top edge is above (less than) the bar bottom.
    guard topEdge < threshold else { continue }

    var newPoint = CGPoint(x: pos.x, y: threshold)
    guard let axPos = AXValueCreate(.cgPoint, &newPoint) else { continue }
    AXUIElementSetAttributeValue(axWin, kAXPositionAttribute as CFString, axPos)
}
