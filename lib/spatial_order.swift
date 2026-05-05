import Foundation
import CoreGraphics

// Reads x-coordinates for the given window IDs from CGWindowList and
// prints them to stdout sorted left-to-right, one per line.
//
// Used by hub's arrange_* functions to determine spatial order, because
// `aerospace list-windows` returns windows in a non-spatial order (roughly
// creation order) after flatten, which breaks join-with-left targeting.
//
// Usage: spatial_order <wid1> <wid2> ...

let wids = Set(CommandLine.arguments.dropFirst().compactMap { Int($0) })
guard !wids.isEmpty else { exit(0) }

let opts = CGWindowListOption([.optionOnScreenOnly, .excludeDesktopElements])
guard let info = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else {
    exit(0)
}

var out: [(Int, Int)] = []
for w in info {
    guard let wid = w[kCGWindowNumber as String] as? Int,
          wids.contains(wid),
          let bounds = w[kCGWindowBounds as String] as? [String: CGFloat]
    else { continue }
    out.append((Int(bounds["X"] ?? 0), wid))
}
out.sort { $0.0 < $1.0 }
for (_, wid) in out { print(wid) }
