import Foundation
import CoreGraphics

// Two modes:
//
//   spatial_order <wid1> <wid2> ...
//     Reads x-coordinates for the given window IDs from CGWindowList and
//     prints them to stdout sorted left-to-right, one per line.
//     Used by hub's arrange_* functions to determine spatial order.
//
//   spatial_order --tree [--workspace <ws>|--all] [--json]
//     Reconstructs the AeroSpace tiling tree from window geometry and prints
//     it as text (or JSON with --json). Replaces agents/bin/aerospace-tree.

// ── CGWindowList geometry ─────────────────────────────────────────────────────

struct WinRect {
    let wid: Int
    let x, y, w, h: Int
    var right:  Int { x + w }
    var bottom: Int { y + h }
}

func allWindowRects() -> [Int: WinRect] {
    let opts = CGWindowListOption([.optionOnScreenOnly, .excludeDesktopElements])
    guard let info = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else {
        return [:]
    }
    var result: [Int: WinRect] = [:]
    for entry in info {
        guard let wid = entry[kCGWindowNumber as String] as? Int,
              let bounds = entry[kCGWindowBounds as String] as? [String: CGFloat]
        else { continue }
        result[wid] = WinRect(
            wid: wid,
            x: Int(bounds["X"] ?? 0),
            y: Int(bounds["Y"] ?? 0),
            w: Int(bounds["Width"] ?? 0),
            h: Int(bounds["Height"] ?? 0)
        )
    }
    return result
}

// ── spatial_order mode ────────────────────────────────────────────────────────

func runSpatialOrder(args: [String]) {
    let wids = Set(args.compactMap { Int($0) })
    guard !wids.isEmpty else { exit(0) }
    let rects = allWindowRects()
    var out: [(Int, Int)] = []
    for (wid, rect) in rects where wids.contains(wid) {
        out.append((rect.x, wid))
    }
    out.sort { $0.0 < $1.0 }
    for (_, wid) in out { print(wid) }
}

// ── aerospace subprocess helpers ──────────────────────────────────────────────

func run(_ args: [String]) -> String {
    let p = Process()
    p.launchPath = "/usr/bin/env"
    p.arguments = args
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = Pipe()
    try? p.run(); p.waitUntilExit()
    return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
}

func focusedWorkspace() -> String? {
    let out = run(["aerospace", "list-workspaces", "--focused"]).trimmingCharacters(in: .whitespacesAndNewlines)
    return out.isEmpty ? nil : out
}

func allWorkspaces() -> [String: Bool] {
    let out = run(["aerospace", "list-workspaces", "--all",
                   "--format", "%{workspace}\t%{workspace-is-visible}"])
    var result: [String: Bool] = [:]
    for line in out.components(separatedBy: "\n") {
        let parts = line.components(separatedBy: "\t")
        guard parts.count == 2 else { continue }
        result[parts[0]] = parts[1].trimmingCharacters(in: .whitespacesAndNewlines) == "true"
    }
    return result
}

struct WinInfo {
    let wid: Int
    let app: String
    let title: String
    var rect: WinRect?
}

func windowsForWorkspace(_ ws: String) -> [WinInfo] {
    let out = run(["aerospace", "list-windows", "--workspace", ws,
                   "--format", "%{window-id}\t%{app-name}\t%{window-title}"])
    var result: [WinInfo] = []
    for line in out.components(separatedBy: "\n") {
        let parts = line.components(separatedBy: "\t")
        guard parts.count >= 3, let wid = Int(parts[0]) else { continue }
        result.append(WinInfo(wid: wid, app: parts[1], title: parts[2]))
    }
    return result
}

// ── tree reconstruction ───────────────────────────────────────────────────────

let TOLERANCE = 4

indirect enum Node {
    case leaf(WinInfo)
    case split(axis: String, hidden: Bool, children: [Node])
}

func boundingBox(_ windows: [WinInfo]) -> WinRect? {
    guard !windows.isEmpty, windows.allSatisfy({ $0.rect != nil }) else { return nil }
    let rects = windows.compactMap { $0.rect }
    let minX = rects.map { $0.x }.min()!
    let minY = rects.map { $0.y }.min()!
    let maxR = rects.map { $0.right }.max()!
    let maxB = rects.map { $0.bottom }.max()!
    return WinRect(wid: 0, x: minX, y: minY, w: maxR - minX, h: maxB - minY)
}

func sliceByCuts(_ windows: [WinInfo], cuts: [Int],
                 getLo: (WinInfo) -> Int, getHi: (WinInfo) -> Int) -> [[WinInfo]] {
    var groups: [[WinInfo]] = []
    var remaining = windows
    for cut in cuts {
        let group = remaining.filter { getHi($0) <= cut + TOLERANCE }
        remaining  = remaining.filter { getLo($0) >= cut - TOLERANCE }
        if !group.isEmpty { groups.append(group) }
    }
    if !remaining.isEmpty { groups.append(remaining) }
    return groups
}

func findGroups(_ windows: [WinInfo]) -> (String, [[WinInfo]])? {
    guard windows.count >= 2, let box = boundingBox(windows) else { return nil }
    // Try h-split first (vertical column cuts)
    let hCuts = Set(windows.compactMap { $0.rect }.map { $0.right }
        .filter { abs($0 - box.right) > TOLERANCE }).sorted()
    if !hCuts.isEmpty {
        let groups = sliceByCuts(windows, cuts: hCuts,
                                 getLo: { $0.rect!.x }, getHi: { $0.rect!.right })
        if groups.count >= 2, groups.reduce(0, { $0 + $1.count }) == windows.count {
            return ("h", groups)
        }
    }
    // Try v-split (horizontal row cuts)
    let vCuts = Set(windows.compactMap { $0.rect }.map { $0.bottom }
        .filter { abs($0 - box.bottom) > TOLERANCE }).sorted()
    if !vCuts.isEmpty {
        let groups = sliceByCuts(windows, cuts: vCuts,
                                 getLo: { $0.rect!.y }, getHi: { $0.rect!.bottom })
        if groups.count >= 2, groups.reduce(0, { $0 + $1.count }) == windows.count {
            return ("v", groups)
        }
    }
    return nil
}

func buildTree(_ windows: [WinInfo]) -> Node {
    if windows.count == 1 { return .leaf(windows[0]) }
    if let (axis, groups) = findGroups(windows) {
        return .split(axis: axis, hidden: false, children: groups.map { buildTree($0) })
    }
    return .split(axis: "h", hidden: false, children: windows.map { .leaf($0) })
}

// ── output ────────────────────────────────────────────────────────────────────

func nodeToText(_ node: Node, indent: Int) -> String {
    let pad = String(repeating: "  ", count: indent)
    switch node {
    case .leaf(let w):
        var geo = ""
        if let r = w.rect { geo = " [\(r.w)x\(r.h) @ \(r.x),\(r.y)]" }
        return "\(pad)window \(w.wid)  \(w.app)  \"\(w.title)\"\(geo)"
    case .split(let axis, let hidden, let children):
        var label = "[\(axis)-split]"
        if hidden { label += "  (hidden — geometry unavailable)" }
        var lines = ["\(pad)\(label)"]
        for child in children { lines.append(nodeToText(child, indent: indent + 1)) }
        return lines.joined(separator: "\n")
    }
}

func nodeToJSON(_ node: Node) -> Any {
    switch node {
    case .leaf(let w):
        var d: [String: Any] = ["type": "window", "window-id": w.wid, "app": w.app, "title": w.title]
        if let r = w.rect { d["rect"] = ["x": r.x, "y": r.y, "w": r.w, "h": r.h] }
        return d
    case .split(let axis, let hidden, let children):
        var d: [String: Any] = ["type": "split-\(axis)", "children": children.map { nodeToJSON($0) }]
        if hidden { d["note"] = "hidden workspace — geometry unavailable, order may be wrong" }
        return d
    }
}

// ── --tree mode ───────────────────────────────────────────────────────────────

func runTree(args: [String]) {
    var remaining = args
    let asJSON = remaining.contains("--json")
    remaining.removeAll { $0 == "--json" }

    let wsInfo = allWorkspaces()
    let frames = allWindowRects()

    var workspaces: [String]
    if let idx = remaining.firstIndex(of: "--workspace"), idx + 1 < remaining.count {
        workspaces = [remaining[idx + 1]]
    } else if remaining.contains("--all") {
        workspaces = wsInfo.keys.sorted()
    } else {
        workspaces = [focusedWorkspace() ?? wsInfo.keys.sorted().first ?? ""]
    }

    var result: [(String, Node)] = []
    for ws in workspaces {
        var windows = windowsForWorkspace(ws)
        guard !windows.isEmpty else { continue }
        for i in 0..<windows.count { windows[i].rect = frames[windows[i].wid] }
        let isVisible = wsInfo[ws] ?? false
        let node: Node
        if isVisible {
            let withGeo    = windows.filter { $0.rect != nil }
            let withoutGeo = windows.filter { $0.rect == nil }
            var tree = withGeo.isEmpty ? Node.split(axis: "h", hidden: false, children: [])
                                       : buildTree(withGeo)
            if !withoutGeo.isEmpty, case .split(let ax, let hid, var ch) = tree {
                ch += withoutGeo.map { .leaf($0) }
                tree = .split(axis: ax, hidden: hid, children: ch)
            }
            node = tree
        } else {
            node = .split(axis: "h", hidden: true, children: windows.map { .leaf($0) })
        }
        result.append((ws, node))
    }

    if asJSON {
        var dict: [String: Any] = [:]
        for (ws, node) in result { dict[ws] = nodeToJSON(node) }
        if let data = try? JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted),
           let str = String(data: data, encoding: .utf8) {
            print(str)
        }
    } else {
        for (ws, node) in result {
            print("workspace \(ws)")
            print(nodeToText(node, indent: 1))
            print()
        }
    }
}

// ── entry point ───────────────────────────────────────────────────────────────

let args = Array(CommandLine.arguments.dropFirst())
if args.first == "--tree" {
    runTree(args: Array(args.dropFirst()))
} else {
    runSpatialOrder(args: args)
}
