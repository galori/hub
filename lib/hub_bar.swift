import Cocoa
import IOKit.ps
import CoreAudio
import Darwin

// Single-file native Swift Hub Bar for hub.
// Reads state files + aerospace queries on SIGUSR1, re-renders all views.
// PID written to ~/.config/hub/hub_bar.pid; hub bar-refresh sends SIGUSR1.

// ──────────────────────────────────────────────────────────────────────────────
// MARK: – Local aliases & geometry  (colors come from Theme in theme.swift)
// ──────────────────────────────────────────────────────────────────────────────

func luminance(argb: UInt32) -> Int {
    let r = Int((argb >> 16) & 0xff)
    let g = Int((argb >>  8) & 0xff)
    let b = Int( argb        & 0xff)
    return (r * 299 + g * 587 + b * 114) / 1000
}

// ── Gradient stops (raw UInt32 kept for CAGradientLayer / CGColor use) ──
let GRAD_TOP:    UInt32 = 0xFF1A1C22
let GRAD_BOT:    UInt32 = 0xFF15171C
let CLUSTER_BG:  UInt32 = 0xFF181A20

// ── Accent (teal drives the Hub Bar) ──
let ACCENT:      UInt32 = 0xFF41D1C4
let ACCENT_SOFT: UInt32 = 0x2241D1C4
let ACCENT_DOT:  UInt32 = 0xFF41D1C4

// ── Pill colours ──
let PILL_IDLE_BG:   UInt32 = 0x09FFFFFF
let PILL_IDX_IDLE:  UInt32 = 0xFFD3D6DE
let PILL_NAME_IDLE: UInt32 = 0xFFAEB3BF
let PILL_IDX_ACT:   UInt32 = 0x73000000
let PILL_NAME_ACT:  UInt32 = 0xFF06201E
let PILL_HOVER_BG:  UInt32 = 0x1E41D1C4
let PILL_HOVER_FOCUSED_BG: UInt32 = 0xFF57D9CE

// ── Status dots ──
let DOT_ORANGE: UInt32 = 0xFFF0883E
let DOT_BLUE:   UInt32 = 0xFF76CCE0

// ── App-icon group ──
let APPGRP_BG:     UInt32 = 0x0BFFFFFF
let APPGRP_BORDER: UInt32 = 0x0DFFFFFF
let APPGRP_RADIUS: CGFloat = 11

// ── Misc widget colours ──
let C_WHITE:  UInt32 = 0xFFE2E2E3
let C_RED:    UInt32 = 0xFFFC5D7C
let C_GREEN:  UInt32 = 0xFF9ED072
let C_BLUE:   UInt32 = 0xFF76CCE0
let C_YELLOW: UInt32 = 0xFFE7C664
let C_ORANGE: UInt32 = 0xFFF39660
let C_GREY:   UInt32 = 0xFF7F8490

// ── Service mode ──
let SERVICE_BG: UInt32 = 0xFFC91B00

// ── Geometry ──
let barHeightNormal: CGFloat = 40
let normalMenuBarOverlap: CGFloat = 1  // Cover the Sequoia compositor gap below the persistent menu bar.
let revealedMenuBarHubGap: CGFloat = 4  // Preserve the Hub Bar top padding below the transient macOS menu bar.
let tahoeRevealedMenuBarHubGap: CGFloat = 8  // Tahoe's taller menu bar needs a little more lower breathing room.
let pillH:           CGFloat = 32      // Standard pill height
let pillRadius:      CGFloat = 16      // Pill corner radius
let pillPadH:        CGFloat = 8       // Horizontal padding in pills
let pillGap:         CGFloat = 4       // Gap between pills
let appIconSize:     CGFloat = 20      // Application icon size
let appGroupGap:     CGFloat = 6       // Gap between app icons
let completeNameSlack:  CGFloat = 8     // Prevent AppKit from re-ellipsizing labels that fit by cap
let hoverExpandedSlack: CGFloat = 4     // Small buffer for the full label during hover expansion
let shortNameNoTruncateLimit = 4        // Ellipsizing tiny names saves little space and hurts scanability

func revealedMenuBarHubGap(forMajorOSVersion majorVersion: Int) -> CGFloat {
    majorVersion >= 26 ? tahoeRevealedMenuBarHubGap : revealedMenuBarHubGap
}

func currentMajorOSVersion() -> Int {
    ProcessInfo.processInfo.operatingSystemVersion.majorVersion
}

func fullscreenTransientAerospaceMetric(rows: Int,
                                        menuBarRevealInset: CGFloat,
                                        osMajorVersion: Int = currentMajorOSVersion()) -> Int {
    let rowCount = max(1, rows)
    let inset = max(0, menuBarRevealInset)
    let revealedGap = inset > 0 ? revealedMenuBarHubGap(forMajorOSVersion: osMajorVersion) : 0
    return Int(ceil(barHeightNormal * CGFloat(rowCount) + inset + revealedGap))
}

// ── Fonts ──
let monoFont11 = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
let monoFont12 = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
let monoFont13 = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
let monoFont16 = NSFont.monospacedSystemFont(ofSize: 16, weight: .regular)
let nerdFont   = monoFont13
let nerdFont16 = monoFont16
let nerdFont13 = monoFont13

// ── Legacy (kept for volume popup) ──
let ITEM_BG:    UInt32 = 0xFF363944
let ITEM_BG2:   UInt32 = 0xFF414550
let HOVER_BG:   UInt32 = 0x33FFFFFF
let CLICK_BG:   UInt32 = 0xFF76CCE0
let cornerRadius: CGFloat = 9
let borderWidth:  CGFloat = 2

// ── Workspace slot colours ──
let SLOT_COLORS: [UInt32] = Theme.Color.slotColors

let ALL_WS = ["1","2","3","4","5","6","7","8","9",
              "A","B","C","D","E","F","G","H","I","J","K","L","M",
              "N","O","P","Q","R","S","T","U","V","W","X","Y","Z"]

var slotColorMap: [String: UInt32] = {
    var m: [String: UInt32] = [:]
    for (i, ws) in ALL_WS.enumerated() { m[ws] = SLOT_COLORS[i % SLOT_COLORS.count] }
    return m
}()

// ──────────────────────────────────────────────────────────────────────────────
// MARK: – Window level utilities
// ──────────────────────────────────────────────────────────────────────────────

/// Returns the window level currently used by macOS notifications
func notificationWindowLevel() -> NSWindow.Level {
    let options = CGWindowListOption(arrayLiteral: .excludeDesktopElements, .optionOnScreenOnly)
    if let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] {
        for window in windowList {
            if let name = window[kCGWindowName as String] as? String,
               name.contains("Notification") || name.contains("alert"),
               let level = window[kCGWindowLayer as String] as? Int {
                return NSWindow.Level(rawValue: level)
            }
        }
    }
    // Fallback if we can't detect notification windows
    return NSWindow.Level(rawValue: 25) // kCGUtilityWindowLevel + some buffer
}

/// Returns true if there are active notification windows on screen
func hasActiveNotifications() -> Bool {
    let options = CGWindowListOption(arrayLiteral: .excludeDesktopElements, .optionOnScreenOnly)
    if let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] {
        for window in windowList {
            if let name = window[kCGWindowName as String] as? String,
               (name.contains("Notification") || name.contains("alert")),
               let bounds = window[kCGWindowBounds as String] as? [String: CGFloat] {
                // Check if window is actually visible on screen
                if let x = bounds["X"], let y = bounds["Y"], let w = bounds["Width"], let h = bounds["Height"], w > 50, h > 20 {
                    // Check if window intersects with any screen
                    let windowRect = NSRect(x: x, y: y, width: w, height: h)
                    for screen in NSScreen.screens {
                        if windowRect.intersects(screen.frame) {
                            return true
                        }
                    }
                }
            }
        }
    }
    return false
}

enum Aerospace {
    static func run(_ args: [String]) -> String {
        let aero = FileManager.default.fileExists(atPath: "/opt/homebrew/bin/aerospace")
            ? "/opt/homebrew/bin/aerospace" : "/usr/local/bin/aerospace"
        let p = Process(); p.launchPath = aero; p.arguments = args
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = Pipe()
        try? p.run(); p.waitUntilExit()
        let d = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: d, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

func hubScriptPath() -> String? {
    let path = NSHomeDirectory() + "/.config/hub/hub_path"
    guard let c = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
    return c.trimmingCharacters(in: .whitespacesAndNewlines)
}

func processArgs(pid: pid_t) -> [String] {
    var size = 0
    var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
    sysctl(&mib, 3, nil, &size, nil, 0)
    guard size > 0 else { return [] }
    var buf = [CChar](repeating: 0, count: size)
    guard sysctl(&mib, 3, &buf, &size, nil, 0) == 0 else { return [] }
    // First 4 bytes are argc; skip them, then parse null-terminated strings
    var idx = 4
    var args: [String] = []
    while idx < size {
        let start = idx
        while idx < size && buf[idx] != 0 { idx += 1 }
        if idx > start {
            let s = String(bytes: buf[start..<idx].map { UInt8(bitPattern: $0) }, encoding: .utf8) ?? ""
            if !s.isEmpty { args.append(s) }
        }
        idx += 1
    }
    return args
}

func claudeSessionStatus(pid: Int32) -> (status: String, statusUpdatedAtMs: Double)? {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    let path = "\(home)/.claude/sessions/\(pid).json"
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let status = json["status"] as? String else {
        return nil
    }

    if let n = json["statusUpdatedAt"] as? NSNumber {
        return (status, n.doubleValue)
    }
    if let n = json["updatedAt"] as? NSNumber {
        return (status, n.doubleValue)
    }
    return nil
}

func activeFlagModifiedAtMs(_ url: URL) -> Double? {
    guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
          let date = values.contentModificationDate else {
        return nil
    }
    return date.timeIntervalSince1970 * 1000.0
}

func shouldKeepClaudeActive(pid: Int32, activeSinceMs: Double?) -> Bool {
    guard kill(pid, 0) == 0 else { return false }

    let args = processArgs(pid: pid_t(pid))
    if args.contains("--bg-spare") { return false }

    // Missing or changed Claude session metadata is ambiguous; preserve blue.
    guard let session = claudeSessionStatus(pid: pid) else { return true }
    guard session.status == "idle" else { return true }
    guard let activeSinceMs = activeSinceMs else { return true }

    return session.statusUpdatedAtMs <= activeSinceMs
}

func cleanupStaleClaudeActiveFlags() {
    let fm = FileManager.default
    let tmp = URL(fileURLWithPath: "/tmp", isDirectory: true)
    guard let entries = try? fm.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil) else { return }

    var changed = false
    for url in entries {
        let name = url.lastPathComponent
        guard name.hasPrefix("hub_claude_active_") else { continue }
        let ws = String(name.dropFirst("hub_claude_active_".count))
        if ws.isEmpty { continue }
        let pidPath = "/tmp/hub_claude_pid_\(ws)"

        // Migration/cleanup: active flags created by older hook versions had no pid file.
        // Treat those as stale to prevent indefinitely blinking blue pills.
        guard fm.fileExists(atPath: pidPath) else {
            try? fm.removeItem(at: url)
            changed = true
            continue
        }

        let raw = (try? String(contentsOfFile: pidPath, encoding: .utf8)) ?? ""
        let pids = raw
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let activeSinceMs = activeFlagModifiedAtMs(url)
        var hasWorking = false
        var sawLiveClaude = false
        for p in pids {
            guard let pid = Int32(p), kill(pid, 0) == 0 else { continue }
            // Exclude background spare daemons — they outlive the real session
            let args = processArgs(pid: pid_t(pid))
            if args.contains("--bg-spare") { continue }
            sawLiveClaude = true
            if shouldKeepClaudeActive(pid: pid, activeSinceMs: activeSinceMs) {
                hasWorking = true
                break
            }
        }

        if !hasWorking {
            try? fm.removeItem(at: url)
            try? fm.removeItem(atPath: pidPath)
            if sawLiveClaude {
                try? "".write(toFile: "/tmp/hub_claude_alert_\(ws)", atomically: true, encoding: .utf8)
            }
            changed = true
        }
    }

    if changed, let hub = hubScriptPath() {
        DispatchQueue.global(qos: .utility).async {
            let process = Process()
            process.launchPath = "/bin/sh"
            process.arguments = ["-c", "'\(hub)' bar-refresh >/dev/null 2>&1"]
            try? process.run()
            process.waitUntilExit()
        }
    }
}

// ──────────────────────────────────────────────────────────────────────────────
// MARK: – HubBarState
// ──────────────────────────────────────────────────────────────────────────────

struct WsInfo {
    var id: String; var name: String; var color: String; var repo: String
}

struct HubBarState {
    var focused: String = ""
    var active: Set<String> = []
    var wsInfo: [String: WsInfo] = [:]
    var monitorWorkspaces: [Int: Set<String>] = [:]
    var currentWindows: [(id: Int, app: String)] = []
    var apps: [[String: String]] = []
    var actions: [[String: String]] = []
    var repoPrefix: Bool = false
    var serviceMode: Bool = false
    var claudeAlert: Set<String> = []
    var claudeActive: Set<String> = []
    // Layout mode: shrink (default) = one row, binary-search label cap to fit.
    //              expand           = full labels, bar grows 1..FIT_MAX_ROWS rows.
    enum LayoutMode: String { case shrink, expand }
    var layoutMode: LayoutMode = .shrink

    static func snapshot() -> HubBarState {
        var s = HubBarState()
        let hub = NSHomeDirectory() + "/.config/hub"

        s.focused = Aerospace.run(["list-workspaces", "--focused"])
        let activeRaw = Aerospace.run(["list-workspaces", "--monitor", "all", "--empty", "no"])
        s.active = Set(activeRaw.split(separator: "\n").map { String($0) })
        s.active.remove(s.focused)

        // Per-monitor workspace lists
        let monCountRaw = Aerospace.run(["list-monitors", "--format", "%{monitor-id}"])
        for mid in monCountRaw.split(separator: "\n").compactMap({ Int($0) }) {
            let wsRaw = Aerospace.run(["list-workspaces", "--monitor", "\(mid)"])
            s.monitorWorkspaces[mid] = Set(wsRaw.split(separator: "\n").map { String($0) })
        }

        // Labels file
        let labelsFile = hub + "/hub_bar_labels"
        if let lines = try? String(contentsOfFile: labelsFile, encoding: .utf8) {
            for line in lines.split(separator: "\n") {
                let parts = line.split(separator: ":", maxSplits: 3, omittingEmptySubsequences: false).map(String.init)
                guard parts.count >= 1, !parts[0].isEmpty else { continue }
                let id = parts[0]
                s.wsInfo[id] = WsInfo(id: id,
                    name:  parts.count > 1 ? parts[1] : "",
                    color: parts.count > 2 ? parts[2] : "",
                    repo:  parts.count > 3 ? parts[3] : "")
            }
        }

        // Current workspace windows
        let winRaw = Aerospace.run(["list-windows", "--workspace", s.focused.isEmpty ? "Z" : s.focused, "--format", "%{window-id}|%{app-name}"])
        for line in winRaw.split(separator: "\n") {
            let p = line.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
            if p.count == 2, let wid = Int(p[0].trimmingCharacters(in: .whitespaces)) {
                s.currentWindows.append((id: wid, app: p[1]))
            }
        }

        // apps.json
        let appsFile = hub + "/apps.json"
        if let d = try? Data(contentsOf: URL(fileURLWithPath: appsFile)),
           let arr = try? JSONSerialization.jsonObject(with: d) as? [[String: Any]] {
            s.apps = arr.map { dict in dict.mapValues { "\($0)" } }
        }

        // actions.json
        let actionsFile = hub + "/actions.json"
        if let d = try? Data(contentsOf: URL(fileURLWithPath: actionsFile)),
           let arr = try? JSONSerialization.jsonObject(with: d) as? [[String: Any]] {
            s.actions = arr.map { dict in dict.mapValues { "\($0)" } }
        }

        // repo_prefix
        if let v = try? String(contentsOfFile: hub + "/repo_prefix", encoding: .utf8) {
            s.repoPrefix = v.trimmingCharacters(in: .whitespacesAndNewlines) == "on"
        }

        // Layout mode: shrink (default) | expand
        if let v = try? String(contentsOfFile: hub + "/layout_mode", encoding: .utf8),
           let m = LayoutMode(rawValue: v.trimmingCharacters(in: .whitespacesAndNewlines)) {
            s.layoutMode = m
        }
        // service mode
        s.serviceMode = FileManager.default.fileExists(atPath: "/tmp/hub_service_mode")

        // claude states
        for ws in ALL_WS {
            if FileManager.default.fileExists(atPath: "/tmp/hub_claude_alert_\(ws)") { s.claudeAlert.insert(ws) }
            if FileManager.default.fileExists(atPath: "/tmp/hub_claude_active_\(ws)") { s.claudeActive.insert(ws) }
        }
        if !s.focused.isEmpty {
            // Clear the "done" alert dot when switching to a workspace — it's a notification.
            // Do NOT clear the "working" active dot — Claude is still running in that workspace.
            try? FileManager.default.removeItem(atPath: "/tmp/hub_claude_alert_\(s.focused)")
            s.claudeAlert.remove(s.focused)
        }
        return s
    }

    // Returns (idx, name) spans for display, using the given effective cap.
    func spansFor(ws: String, cap: Int) -> (idx: String, name: String) {
        guard let info = wsInfo[ws], !info.name.isEmpty else { return (ws, "") }
        var full = info.name
        if repoPrefix, !info.repo.isEmpty, full != info.repo { full = "\(info.repo):\(full)" }
        return (ws, cappedName(full: full, cap: cap))
    }

    func wsColor(ws: String) -> UInt32 {
        if let info = wsInfo[ws], !info.color.isEmpty {
            let hex = info.color.hasPrefix("#") ? String(info.color.dropFirst()) : info.color
            if let v = UInt32(hex, radix: 16) { return 0xff000000 | v }
        }
        return slotColorMap[ws] ?? ITEM_BG
    }

    // Visible pills for this monitor (in ALL_WS order)
    func visiblePillInfos(monitorWs: Set<String>?) -> [(ws: String, fullName: String, isFocused: Bool)] {
        var result: [(ws: String, fullName: String, isFocused: Bool)] = []
        for ws in ALL_WS {
            if let mws = monitorWs, !mws.contains(ws) { continue }
            let isActive = active.contains(ws) || ws == focused
            let isLabeled = wsInfo[ws] != nil
            guard isActive || isLabeled else { continue }
            var name = wsInfo[ws]?.name ?? ""
            if repoPrefix, let repo = wsInfo[ws]?.repo, !repo.isEmpty, name != repo { name = "\(repo):\(name)" }
            result.append((ws: ws, fullName: name, isFocused: ws == focused))
        }
        return result
    }
}

// ──────────────────────────────────────────────────────────────────────────────
// MARK: – Text-width measurement cache
// ──────────────────────────────────────────────────────────────────────────────

private var textWidthCache: [String: CGFloat] = [:]

func cachedTextWidth(_ s: String, font: NSFont) -> CGFloat {
    let key = "\(font.pointSize)/\(font.fontName)/\(s)"
    if let cached = textWidthCache[key] { return cached }
    let w = (s as NSString).size(withAttributes: [.font: font]).width
    textWidthCache[key] = w
    return w
}

func preferredPillPadH() -> CGFloat {
    pillPadH + ceil(cachedTextWidth("center", font: monoFont13))
}

// Apply a label cap to a workspace name.
// cap == -1 → full name; cap == 0 → empty; cap > 0 → truncate to cap chars.
func cappedName(full: String, cap: Int) -> String {
    if cap == 0 { return "" }
    if full.count <= shortNameNoTruncateLimit { return full }
    if cap > 0, full.count > cap { return String(full.prefix(cap)) + "…" }
    return full
}

// Analytic pill width for a given (idx, name) pair — mirrors WorkspacePill layout constants.
// showDot adds 4(spacing)+6(dot) to the inner stack.
func analyticalPillWidth(idx: String, name: String, showDot: Bool, padH: CGFloat = pillPadH) -> CGFloat {
    let idxFont = NSFontManager.shared.font(withFamily: "Hack Nerd Font", traits: .boldFontMask, weight: 9, size: 11)
                  ?? monoFont11
    var w = padH * 2 + cachedTextWidth(idx, font: idxFont)
    if !name.isEmpty {
        w += 4 + cachedTextWidth(name, font: monoFont13)  // innerStack spacing=4
    }
    if showDot { w += 4 + 6 }  // spacing + dot width
    return ceil(w)
}

func normalPillWidth(idx: String, fullName: String, displayName: String, showDot: Bool, padH: CGFloat = pillPadH) -> CGFloat {
    var width = analyticalPillWidth(idx: idx, name: displayName, showDot: showDot, padH: padH)
    if !displayName.isEmpty, displayName == fullName {
        width += completeNameSlack
    }
    return width
}

func normalPillWidth(idx: String, fullName: String, cap: Int, showDot: Bool, padH: CGFloat = pillPadH) -> CGFloat {
    normalPillWidth(
        idx: idx,
        fullName: fullName,
        displayName: cappedName(full: fullName, cap: cap),
        showDot: showDot,
        padH: padH)
}

func hoverExpandedPillWidth(idx: String, fullName: String, cappedName: String, showDot: Bool, padH: CGFloat = pillPadH) -> CGFloat {
    normalPillWidth(
        idx: idx,
        fullName: fullName,
        displayName: fullName,
        showDot: showDot,
        padH: padH) + hoverExpandedSlack
}

// Total strip width for a slice of pills at a given label cap.
func stripWidth(pills: [(ws: String, fullName: String, isFocused: Bool)],
                cap: Int, focused: String,
                claudeAlert: Set<String>, claudeActive: Set<String>,
                padH: CGFloat = pillPadH) -> CGFloat {
    guard !pills.isEmpty else { return 0 }
    var total: CGFloat = 0
    for (i, p) in pills.enumerated() {
        if i > 0 { total += pillGap }
        let effCap = cap
        let showDot = claudeAlert.contains(p.ws) || claudeActive.contains(p.ws)
        total += normalPillWidth(idx: p.ws, fullName: p.fullName, cap: effCap, showDot: showDot, padH: padH)
    }
    return total
}

// ──────────────────────────────────────────────────────────────────────────────
// MARK: – FitDecision
// ──────────────────────────────────────────────────────────────────────────────

struct FitDecision {
    var rows: Int           // 1..maxRows
    var rowAssignment: [[Int]]  // indices into `pills` for each row
    var effectiveCap: Int   // label cap (-1 unlimited, 0 code-only, N>0 truncated)
    var effectivePadH: CGFloat = pillPadH
    // Notch split for row 0: count of pills that go into the LEFT segment.
    // The remainder go into the RIGHT segment (right of notch).
    // nil = no notch / not fullscreen → single continuous row, unchanged behaviour.
    var row0Split: Int? = nil
    // Post-layout left-segment relaxation (fullscreen+notch+shrink only): the global
    // effectiveCap is chosen so BOTH segments fit, but the left segment usually has slack
    // before the notch. leftCap (> effectiveCap) is applied to the workspaces in leftWsIDs
    // so their labels grow to fill that space. nil = no relaxation (left uses effectiveCap).
    var leftCap: Int? = nil
    var leftPadH: CGFloat? = nil
    var leftWsIDs: Set<String> = []
    // Symmetric relaxation for the right side of the notch. When the left segment is the
    // limiting side, the right-side labels can safely grow without changing the split.
    var rightCap: Int? = nil
    var rightPadH: CGFloat? = nil
    var rightWsIDs: Set<String> = []

    // Per-workspace label cap: notch-side pills may use a relaxed segment cap; all others
    // use the global effectiveCap.
    func capFor(_ ws: String) -> Int {
        if let lc = leftCap, leftWsIDs.contains(ws) { return lc }
        if let rc = rightCap, rightWsIDs.contains(ws) { return rc }
        return effectiveCap
    }

    // Per-workspace horizontal padding: notch-side pills may use relaxed segment padding.
    func padFor(_ ws: String) -> CGFloat {
        if let lp = leftPadH, leftWsIDs.contains(ws) { return lp }
        if let rp = rightPadH, rightWsIDs.contains(ws) { return rp }
        return effectivePadH
    }
}

func fitStructureMatchesForRefresh(_ lhs: FitDecision?, _ rhs: FitDecision) -> Bool {
    guard let lhs = lhs else { return true }
    return lhs.rowAssignment == rhs.rowAssignment
        && lhs.effectivePadH == rhs.effectivePadH
        && lhs.row0Split == rhs.row0Split
        && lhs.leftCap == rhs.leftCap
        && lhs.leftPadH == rhs.leftPadH
        && lhs.leftWsIDs == rhs.leftWsIDs
        && lhs.rightCap == rhs.rightCap
        && lhs.rightPadH == rhs.rightPadH
        && lhs.rightWsIDs == rhs.rightWsIDs
}

func refreshRequiresRebuild(lastFitRows: Int,
                            lastFitCap: Int,
                            lastFitDecision: FitDecision?,
                            lastVisiblePillIDs: [String],
                            previousMode: HubBarState.LayoutMode,
                            currentMode: HubBarState.LayoutMode,
                            currentPillIDs: [String],
                            existingPillIDs: Set<String>,
                            newFit: FitDecision) -> Bool {
    let rowsChanged = newFit.rows != lastFitRows
    let capChanged = newFit.effectiveCap != lastFitCap
    let modeChanged = currentMode != previousMode
    let pillSequenceChanged = currentPillIDs != lastVisiblePillIDs
    let newPillMissing = currentPillIDs.contains { !existingPillIDs.contains($0) }
    let fitStructureChanged = !fitStructureMatchesForRefresh(lastFitDecision, newFit)

    return rowsChanged
        || capChanged
        || modeChanged
        || pillSequenceChanged
        || newPillMissing
        || fitStructureChanged
}

let FIT_MAX_ROWS = 4

// Greedy packing of pills into rows given row widths.
// Row 0 may have restricted capacity (notch / cluster); rows 1+ are full-width.
// Returns (rowAssignment, overflowed). overflowed=true means content didn't fit in maxRows.
private func greedyPack(pills: [(ws: String, fullName: String, isFocused: Bool)],
                        cap: Int, focused: String,
                        claudeAlert: Set<String>, claudeActive: Set<String>,
                        padH: CGFloat,
                        row0Width: CGFloat, fullRowWidth: CGFloat,
                        maxRows: Int) -> (assignment: [[Int]], overflowed: Bool) {
    var rows: [[Int]] = Array(repeating: [], count: maxRows)
    let rowWidths = [row0Width] + Array(repeating: fullRowWidth, count: maxRows - 1)
    var used: [CGFloat] = Array(repeating: 0, count: maxRows)
    var r = 0
    var overflowed = false

    for (i, p) in pills.enumerated() {
        let effCap = cap
        let showDot = claudeAlert.contains(p.ws) || claudeActive.contains(p.ws)
        let pw = normalPillWidth(idx: p.ws, fullName: p.fullName, cap: effCap, showDot: showDot, padH: padH)
        let gap: CGFloat = rows[r].isEmpty ? 0 : pillGap

        if used[r] + gap + pw <= rowWidths[r] {
            used[r] += gap + pw
            rows[r].append(i)
        } else {
            let next = r + 1
            if next >= maxRows {
                // Genuinely doesn't fit — signal overflow, park pill in last row
                overflowed = true
                rows[maxRows - 1].append(i)
                // Keep r = maxRows - 1 so subsequent pills don't OOB
                r = maxRows - 1
            } else {
                r = next
                used[r] = pw
                rows[r].append(i)
            }
        }
    }
    let usedRows = rows.prefix(maxRows)
    return (Array(usedRows), overflowed)
}

// Assigns row-0 pills to left/right notch segments using a greedy left-fill strategy.
// A pill is wholly in one segment — never straddles the notch. Returns the left-segment count.
private func splitRow0AroundNotch(
    row0Indices: [Int],
    pills: [(ws: String, fullName: String, isFocused: Bool)],
    cap: Int,
    claudeAlert: Set<String>, claudeActive: Set<String>,
    padH: CGFloat,
    leftSegW: CGFloat) -> Int {
    var used: CGFloat = 0
    var leftCount = 0
    for idx in row0Indices {
        let p = pills[idx]
        let effCap = cap
        let showDot = claudeAlert.contains(p.ws) || claudeActive.contains(p.ws)
        let pw = normalPillWidth(idx: p.ws, fullName: p.fullName, cap: effCap, showDot: showDot, padH: padH)
        let gap: CGFloat = leftCount == 0 ? 0 : pillGap
        if used + gap + pw <= leftSegW {
            used += gap + pw
            leftCount += 1
        } else {
            break  // first pill that doesn't fit left → rest go right
        }
    }
    return leftCount
}

// Feasibility check for a notch split at a given cap: greedily fill the left segment, then
// verify the REMAINING pills fit the right segment. Returns the left-segment count if both
// segments fit, or nil if the right segment overflows. Mirrors splitRow0AroundNotch's greedy
// partition so the shrink binary-search agrees with the renderer.
private func fitNotchSplit(
    pills: [(ws: String, fullName: String, isFocused: Bool)],
    cap: Int,
    claudeAlert: Set<String>, claudeActive: Set<String>,
    padH: CGFloat,
    leftSegW: CGFloat, rightSegW: CGFloat) -> Int? {
    func pillW(_ p: (ws: String, fullName: String, isFocused: Bool)) -> CGFloat {
        let showDot = claudeAlert.contains(p.ws) || claudeActive.contains(p.ws)
        return normalPillWidth(idx: p.ws, fullName: p.fullName, cap: cap, showDot: showDot, padH: padH)
    }
    // Greedy left-fill (must match splitRow0AroundNotch).
    var used: CGFloat = 0
    var leftCount = 0
    for p in pills {
        let pw = pillW(p)
        let gap: CGFloat = leftCount == 0 ? 0 : pillGap
        if used + gap + pw <= leftSegW { used += gap + pw; leftCount += 1 } else { break }
    }
    // Remaining pills must fit the right segment.
    var rUsed: CGFloat = 0
    var rCount = 0
    for p in pills[leftCount...] {
        let pw = pillW(p)
        let gap: CGFloat = rCount == 0 ? 0 : pillGap
        if rUsed + gap + pw <= rightSegW { rUsed += gap + pw; rCount += 1 } else { return nil }
    }
    return leftCount
}

// Greedy packing for expanded fullscreen notch layouts. Row 0 is physically two
// separate segments, so a combined-width row can still clip on the right side.
private func greedyPackNotchRows(
    pills: [(ws: String, fullName: String, isFocused: Bool)],
    cap: Int,
    focused: String,
    claudeAlert: Set<String>, claudeActive: Set<String>,
    padH: CGFloat,
    leftSegW: CGFloat, rightSegW: CGFloat,
    fullRowWidth: CGFloat,
    maxRows: Int) -> (assignment: [[Int]], overflowed: Bool) {
    var rows: [[Int]] = Array(repeating: [], count: maxRows)
    var used: [CGFloat] = Array(repeating: 0, count: maxRows)
    var overflowed = false

    guard maxRows > 0 else { return (rows, !pills.isEmpty) }

    var row0Count = 0
    if !pills.isEmpty {
        for end in 1...pills.count {
            let candidate = Array(pills[0..<end])
            if fitNotchSplit(pills: candidate, cap: cap,
                             claudeAlert: claudeAlert, claudeActive: claudeActive,
                             padH: padH,
                             leftSegW: leftSegW, rightSegW: rightSegW) != nil {
                row0Count = end
            } else {
                break
            }
        }
    }
    rows[0] = Array(0..<row0Count)

    var r = 1
    for i in row0Count..<pills.count {
        if r >= maxRows {
            overflowed = true
            rows[maxRows - 1].append(i)
            continue
        }

        let p = pills[i]
        let showDot = claudeAlert.contains(p.ws) || claudeActive.contains(p.ws)
        let pw = normalPillWidth(idx: p.ws, fullName: p.fullName, cap: cap, showDot: showDot, padH: padH)
        let gap: CGFloat = rows[r].isEmpty ? 0 : pillGap

        if used[r] + gap + pw <= fullRowWidth {
            used[r] += gap + pw
            rows[r].append(i)
        } else {
            r += 1
            if r >= maxRows {
                overflowed = true
                rows[maxRows - 1].append(i)
            } else {
                used[r] = pw
                rows[r].append(i)
            }
        }
    }

    return (rows, overflowed)
}

// Pure fit decision: given pill data, screen geometry, and layout mode — returns layout.
// `lastRows` is the only retained state (hysteresis for expand mode). Pass 1 on first call.
// Modes:
//   .shrink (default) — always 1 row; binary-search the largest label cap that fits.
//   .expand           — full labels (-1); grow 1..FIT_MAX_ROWS until pills fit (with hysteresis).
// In fullscreen+notch, row 0 is split around the notch: row0Split gives the left-segment count.
func decideFit(pills: [(ws: String, fullName: String, isFocused: Bool)],
               screenW: CGFloat,
               notchMinX: CGFloat?, notchMaxX: CGFloat?,
               isFullscreen: Bool, focused: String,
               claudeAlert: Set<String>, claudeActive: Set<String>,
               mode: HubBarState.LayoutMode,
               lastRows: Int) -> FitDecision {

    let leadingInset: CGFloat = 8
    let trailingInset: CGFloat = 8

    // When fullscreen+notch, pills use BOTH sides of the notch (left segment + right segment).
    // The combined total drives the cap binary-search → one global cap → balanced truncation.
    // Rendering splits pills into two clip-view stacks via row0Split.
    let leftSegW: CGFloat
    let rightSegW: CGFloat
    let row0W: CGFloat
    if isFullscreen, let nMin = notchMinX, let nMax = notchMaxX {
        leftSegW = (nMin - 2) - leadingInset
        rightSegW = max(0, (screenW - trailingInset) - (nMax + 2))
        row0W = leftSegW + rightSegW
    } else {
        leftSegW = screenW - leadingInset - trailingInset
        rightSegW = 0
        row0W = screenW - leadingInset - trailingInset
    }
    let fullRowW = screenW - leadingInset - trailingInset

    let hasNotchSplit = isFullscreen && notchMinX != nil && notchMaxX != nil

    func makeSplit(_ assignment: [[Int]], cap: Int, padH: CGFloat) -> Int? {
        guard hasNotchSplit, let row0 = assignment.first else { return nil }
        return splitRow0AroundNotch(row0Indices: row0, pills: pills, cap: cap,
                                    claudeAlert: claudeAlert, claudeActive: claudeActive,
                                    padH: padH,
                                    leftSegW: leftSegW)
    }

    switch mode {
    case .shrink:
        // Always 1 row. Prefer roomy pill padding, shrink that padding first, then
        // binary-search the largest label cap (0..60) at the minimum padding.
        //
        // In notch mode the pills are split greedily — left segment first, then the rest go
        // right — so a cap that fits the COMBINED width can still overflow the right segment
        // (e.g. short labels fill the left, long ones pile into a too-narrow right). The fit
        // check must therefore validate the actual two-segment partition, not just the sum.
        //
        // Floor: cap=0 (index badge only). If even that overflows, the clip-views clip the
        // excess rather than leaving pills rendered off-screen.
        let allIndices = Array(0..<pills.count)
        let maxCap = 60

        let minPad = pillPadH
        let maxPad = preferredPillPadH()

        func fitsOneRow(cap: Int, padH: CGFloat) -> Bool {
            if hasNotchSplit {
                return fitNotchSplit(pills: pills, cap: cap,
                                     claudeAlert: claudeAlert, claudeActive: claudeActive,
                                     padH: padH,
                                     leftSegW: leftSegW, rightSegW: rightSegW) != nil
            } else {
                let (_, overflowed) = greedyPack(
                    pills: pills, cap: cap, focused: focused,
                    claudeAlert: claudeAlert, claudeActive: claudeActive,
                    padH: padH,
                    row0Width: row0W, fullRowWidth: fullRowW, maxRows: 1)
                return !overflowed
            }
        }

        func largestFittingPad(cap: Int, floor: CGFloat, ceiling: CGFloat) -> CGFloat {
            if fitsOneRow(cap: cap, padH: ceiling) { return ceiling }
            guard fitsOneRow(cap: cap, padH: floor) else { return floor }

            var lo = floor
            var hi = ceiling
            var best = floor
            for _ in 0..<24 {
                let mid = (lo + hi) / 2
                if fitsOneRow(cap: cap, padH: mid) {
                    best = mid
                    lo = mid
                } else {
                    hi = mid
                }
            }
            return best
        }

        let bestCap: Int
        let bestPad: CGFloat
        if fitsOneRow(cap: maxCap, padH: maxPad) {
            bestCap = maxCap
            bestPad = maxPad
        } else if fitsOneRow(cap: maxCap, padH: minPad) {
            bestCap = maxCap
            bestPad = largestFittingPad(cap: maxCap, floor: minPad, ceiling: maxPad)
        } else {
            bestPad = minPad
            var lo = 0, hi = maxCap
            var cap = 0
            while lo <= hi {
                let mid = (lo + hi) / 2
                if fitsOneRow(cap: mid, padH: minPad) {
                    cap = mid
                    lo = mid + 1
                } else {
                    hi = mid - 1
                }
            }
            bestCap = cap
        }

        let split = makeSplit([allIndices], cap: bestCap, padH: bestPad)
        var fit = FitDecision(rows: 1, rowAssignment: [allIndices], effectiveCap: bestCap,
                              effectivePadH: bestPad, row0Split: split)

        func relaxedPad(pills segmentPills: [(ws: String, fullName: String, isFocused: Bool)],
                        cap: Int,
                        segmentWidth: CGFloat) -> CGFloat {
            guard bestPad < maxPad else { return bestPad }
            let maxWidth = stripWidth(pills: segmentPills, cap: cap, focused: focused,
                                      claudeAlert: claudeAlert, claudeActive: claudeActive,
                                      padH: maxPad)
            if maxWidth <= segmentWidth { return maxPad }

            var lo = bestPad
            var hi = maxPad
            var relaxed = bestPad
            for _ in 0..<24 {
                let mid = (lo + hi) / 2
                let w = stripWidth(pills: segmentPills, cap: cap, focused: focused,
                                   claudeAlert: claudeAlert, claudeActive: claudeActive,
                                   padH: mid)
                if w <= segmentWidth {
                    relaxed = mid
                    lo = mid
                } else {
                    hi = mid
                }
            }
            return relaxed
        }

        // Post-layout left relaxation: the global fit is constrained by the tighter of the
        // two segments. Grow only the already-assigned side: first restore padding toward the
        // preferred value, then relax labels as before. The split and opposite segment are
        // untouched.
        if hasNotchSplit, let split = split, split > 0, bestCap >= 0 {
            let leftPills = Array(pills[0..<min(split, pills.count)])
            let bestLeftPad = relaxedPad(pills: leftPills, cap: bestCap, segmentWidth: leftSegW)
            var bestLeftCap = bestCap
            var llo = bestCap + 1, lhi = maxCap
            while llo <= lhi {
                let mid = (llo + lhi) / 2
                let w = stripWidth(pills: leftPills, cap: mid, focused: focused,
                                   claudeAlert: claudeAlert, claudeActive: claudeActive,
                                   padH: bestLeftPad)
                if w <= leftSegW { bestLeftCap = mid; llo = mid + 1 } else { lhi = mid - 1 }
            }
            if bestLeftPad > bestPad + 0.01 || bestLeftCap > bestCap {
                if bestLeftPad > bestPad + 0.01 { fit.leftPadH = bestLeftPad }
                fit.leftCap = bestLeftCap
                fit.leftWsIDs = Set(leftPills.map { $0.ws })
            }
        }

        // Symmetric post-layout relaxation for the right segment. The global cap may be
        // constrained by the left side of the notch; when that happens, grow only the
        // already-assigned right-side labels up to the right segment's available width.
        if hasNotchSplit, let split = split, split < pills.count, bestCap >= 0 {
            let rightPills = Array(pills[min(split, pills.count)...])
            let bestRightPad = relaxedPad(pills: rightPills, cap: bestCap, segmentWidth: rightSegW)
            var bestRightCap = bestCap
            var rlo = bestCap + 1, rhi = maxCap
            while rlo <= rhi {
                let mid = (rlo + rhi) / 2
                let w = stripWidth(pills: rightPills, cap: mid, focused: focused,
                                   claudeAlert: claudeAlert, claudeActive: claudeActive,
                                   padH: bestRightPad)
                if w <= rightSegW { bestRightCap = mid; rlo = mid + 1 } else { rhi = mid - 1 }
            }
            if bestRightPad > bestPad + 0.01 || bestRightCap > bestCap {
                if bestRightPad > bestPad + 0.01 { fit.rightPadH = bestRightPad }
                fit.rightCap = bestRightCap
                fit.rightWsIDs = Set(rightPills.map { $0.ws })
            }
        }
        return fit

    case .expand:
        // Full labels (cap = -1). Grow rows 1..FIT_MAX_ROWS until it fits; apply hysteresis.
        let cap = -1
        let minPad = pillPadH
        let maxPad = preferredPillPadH()

        func pack(rows: Int, padH: CGFloat) -> (assignment: [[Int]], overflowed: Bool) {
            if hasNotchSplit {
                return greedyPackNotchRows(
                    pills: pills, cap: cap, focused: focused,
                    claudeAlert: claudeAlert, claudeActive: claudeActive,
                    padH: padH,
                    leftSegW: leftSegW, rightSegW: rightSegW,
                    fullRowWidth: fullRowW, maxRows: rows)
            }
            return greedyPack(
                pills: pills, cap: cap, focused: focused,
                claudeAlert: claudeAlert, claudeActive: claudeActive,
                padH: padH,
                row0Width: row0W, fullRowWidth: fullRowW, maxRows: rows)
        }

        func largestFittingPad(rows: Int) -> CGFloat {
            if !pack(rows: rows, padH: maxPad).overflowed { return maxPad }
            guard !pack(rows: rows, padH: minPad).overflowed else { return minPad }

            var lo = minPad
            var hi = maxPad
            var best = minPad
            for _ in 0..<24 {
                let mid = (lo + hi) / 2
                if !pack(rows: rows, padH: mid).overflowed {
                    best = mid
                    lo = mid
                } else {
                    hi = mid
                }
            }
            return best
        }

        for r in 1...FIT_MAX_ROWS {
            let (_, overflowed) = pack(rows: r, padH: minPad)
            if !overflowed {
                let effectiveRows: Int
                if r < lastRows {
                    let (_, stillOverflows) = pack(rows: lastRows - 1, padH: minPad)
                    effectiveRows = stillOverflows ? lastRows : r
                } else { effectiveRows = r }
                let padH = largestFittingPad(rows: effectiveRows)
                let (finalAssignment, _) = pack(rows: effectiveRows, padH: padH)
                return FitDecision(rows: effectiveRows, rowAssignment: finalAssignment,
                                   effectiveCap: cap,
                                   effectivePadH: padH,
                                   row0Split: makeSplit(finalAssignment, cap: cap, padH: padH))
            }
        }
        // Still overflows at FIT_MAX_ROWS: park overflow in the last row (ellipsized by per-pill maxwidth).
        let (asgn, _) = pack(rows: FIT_MAX_ROWS, padH: minPad)
        return FitDecision(rows: FIT_MAX_ROWS, rowAssignment: asgn, effectiveCap: cap,
                           effectivePadH: minPad,
                           row0Split: makeSplit(asgn, cap: cap, padH: minPad))
    }
}

// ──────────────────────────────────────────────────────────────────────────────
// MARK: – HubBarBackgroundView (gradient + highlight + border)
// ──────────────────────────────────────────────────────────────────────────────

class HubBarBackgroundView: NSView {
    private let gradLayer = CAGradientLayer()
    private let highlightLayer = CALayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        // gradient
        gradLayer.colors = [
            NSColor(argb: GRAD_TOP).cgColor,
            NSColor(argb: GRAD_BOT).cgColor,
        ]
        // CALayer y=0 is bottom; gradient start=(0,1)=top, end=(0,0)=bottom
        gradLayer.startPoint = CGPoint(x: 0.5, y: 1)
        gradLayer.endPoint   = CGPoint(x: 0.5, y: 0)
        layer!.addSublayer(gradLayer)
        // 1px top highlight
        highlightLayer.backgroundColor = NSColor(argb: 0x0DFFFFFF).cgColor
        layer!.addSublayer(highlightLayer)
        // 1px bottom border
        layer!.borderWidth = 1
        layer!.borderColor = NSColor(argb: 0x0FFFFFFF).cgColor
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        gradLayer.frame = bounds
        highlightLayer.frame = NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1)
        CATransaction.commit()
    }
}

// ──────────────────────────────────────────────────────────────────────────────
// MARK: – HubBarClickView
// ──────────────────────────────────────────────────────────────────────────────

class HubBarClickView: NSView {
    var onPress: (() -> Void)?
    var hoverBG: NSColor = NSColor(argb: HOVER_BG)
    var normalBG: NSColor = .clear

    override func mouseDown(with event: NSEvent) { onPress?() }
    override func mouseEntered(with event: NSEvent) { layer?.backgroundColor = hoverBG.cgColor }
    override func mouseExited(with event: NSEvent)  { layer?.backgroundColor = normalBG.cgColor }
    override var acceptsFirstResponder: Bool { false }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil))
    }
}

// ──────────────────────────────────────────────────────────────────────────────
// MARK: – WorkspacePill (two-span idx + name + optional dot, with glow)
// ──────────────────────────────────────────────────────────────────────────────

class WorkspacePill: NSView {
    let wsID: String
    var isFocused = false
    var pulseBright = true
    private var baseBG: CGColor = NSColor.clear.cgColor
    var fullNameText: String = ""
    var cappedNameText: String = ""
    var canExpandOnHover: Bool = false
    var showDotState: Bool = false
    var padHState: CGFloat = pillPadH
    var widthConstraint: NSLayoutConstraint?
    var onHoverChanged: ((String, Bool) -> Void)?
    private var isHovered = false

    // Inner rounded-rect view (masked) — holds the visible content
    private let innerView = NSView()
    private let idxField  = NSTextField(labelWithString: "")
    private let nameField = NSTextField(labelWithString: "")
    let dotView = NSView()
    private let innerStack = NSStackView()
    private var innerLeadingConstraint: NSLayoutConstraint?
    private var innerTrailingConstraint: NSLayoutConstraint?
    var onPress: (() -> Void)?

    // Track hover for click areas
    private var trackArea: NSTrackingArea?

    init(wsID: String) {
        self.wsID = wsID
        super.init(frame: .zero)

        // Outer: shadow layer (unmasked so glow escapes rounded clip)
        wantsLayer = true
        layer?.masksToBounds = false

        // Inner: rounded, clipped
        innerView.wantsLayer = true
        innerView.layer?.cornerRadius = pillRadius
        innerView.layer?.masksToBounds = true
        innerView.translatesAutoresizingMaskIntoConstraints = false

        // idx field
        idxField.isEditable = false; idxField.isBordered = false; idxField.backgroundColor = .clear
        idxField.font = NSFontManager.shared.font(withFamily: "Hack Nerd Font", traits: .boldFontMask, weight: 9, size: 11)
                        ?? monoFont11
        idxField.lineBreakMode = .byClipping; idxField.setContentCompressionResistancePriority(.required, for: .horizontal)
        idxField.setContentHuggingPriority(.required, for: .horizontal)

        // name field — width is governed by the layout cap (shrink binary-search / expand wrapping)
        // and visually contained by the row-0 clipView. No hard per-pill cap, so labels use all
        // available room and the analytical width helpers match what renders.
        nameField.isEditable = false; nameField.isBordered = false; nameField.backgroundColor = .clear
        nameField.font = monoFont13
        nameField.lineBreakMode = .byTruncatingTail
        nameField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        nameField.setContentHuggingPriority(.required, for: .horizontal)

        // dot
        dotView.wantsLayer = true
        dotView.layer?.cornerRadius = 3
        dotView.isHidden = true

        // inner horizontal stack
        innerStack.orientation = .horizontal
        innerStack.spacing = 4
        innerStack.alignment = .centerY
        innerStack.translatesAutoresizingMaskIntoConstraints = false
        innerStack.setContentHuggingPriority(.required, for: .horizontal)
        innerStack.setContentCompressionResistancePriority(.required, for: .horizontal)
        innerStack.addArrangedSubview(idxField)
        innerStack.addArrangedSubview(nameField)
        innerStack.addArrangedSubview(dotView)

        innerView.addSubview(innerStack)
        addSubview(innerView)

        let innerLeading = innerStack.leadingAnchor.constraint(equalTo: innerView.leadingAnchor, constant: pillPadH)
        let innerTrailing = innerStack.trailingAnchor.constraint(equalTo: innerView.trailingAnchor, constant: -pillPadH)
        innerLeadingConstraint = innerLeading
        innerTrailingConstraint = innerTrailing

        NSLayoutConstraint.activate([
            innerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            innerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            innerView.topAnchor.constraint(equalTo: topAnchor),
            innerView.bottomAnchor.constraint(equalTo: bottomAnchor),

            innerStack.centerYAnchor.constraint(equalTo: innerView.centerYAnchor),
            innerLeading,
            innerTrailing,

            dotView.widthAnchor.constraint(equalToConstant: 6),
            dotView.heightAnchor.constraint(equalToConstant: 6),
        ])

        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)

        onPress = { [weak self] in
            guard let self = self, !self.isFocused else { return }
            let aero = FileManager.default.fileExists(atPath: "/opt/homebrew/bin/aerospace")
                ? "/opt/homebrew/bin/aerospace" : "/usr/local/bin/aerospace"
            Process.launchedProcess(launchPath: aero, arguments: ["workspace", wsID])
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    override func mouseDown(with event: NSEvent) { onPress?() }

    func setPadding(_ padH: CGFloat) {
        padHState = padH
        innerLeadingConstraint?.constant = padH
        innerTrailingConstraint?.constant = -padH
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackArea { removeTrackingArea(t) }
        trackArea = NSTrackingArea(rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(trackArea!)
    }
    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        applyHoverBackground()
        onHoverChanged?(wsID, true)
    }
    override func mouseExited(with event: NSEvent) {
        isHovered = false
        applyHoverBackground()
        onHoverChanged?(wsID, false)
    }

    private func applyHoverBackground() {
        if isHovered {
            innerView.layer?.backgroundColor = isFocused
                ? NSColor(argb: PILL_HOVER_FOCUSED_BG).cgColor
                : NSColor(argb: PILL_HOVER_BG).cgColor
        } else {
            innerView.layer?.backgroundColor = baseBG
        }
    }

    func apply(bg: UInt32, idxColor: UInt32, nameColor: UInt32,
               idx: String, name: String,
               showDot: Bool, dotColor: UInt32,
               glowColor: UInt32?, glowRadius: CGFloat) {
        baseBG = NSColor(argb: bg).cgColor
        applyHoverBackground()
        idxField.stringValue = idx
        idxField.textColor = NSColor(argb: idxColor)
        nameField.stringValue = name
        nameField.invalidateIntrinsicContentSize()
        innerStack.invalidateIntrinsicContentSize()
        innerStack.needsLayout = true
        nameField.isHidden = name.isEmpty
        nameField.textColor = NSColor(argb: nameColor)
        dotView.isHidden = !showDot
        if showDot { dotView.layer?.backgroundColor = NSColor(argb: dotColor).cgColor }
        // glow on outer (unmasked) layer
        if let gc = glowColor {
            layer?.shadowColor = NSColor(argb: gc).cgColor
            layer?.shadowOpacity = 0.55
            layer?.shadowRadius = glowRadius
            layer?.shadowOffset = .zero
        } else {
            layer?.shadowOpacity = 0
        }
    }

    func updatePulse(bright: Bool) {
        pulseBright = bright
        guard !dotView.isHidden else { return }
        dotView.layer?.opacity = bright ? 1.0 : 0.3
    }
}

// ──────────────────────────────────────────────────────────────────────────────
// MARK: – AppSlotView (launcher icon)
// ──────────────────────────────────────────────────────────────────────────────

class AppSlotView: HubBarClickView {
    let imageView = NSImageView()
    let dotView   = NSView()
    let tipLabel  = NSTextField(labelWithString: "")

    init(slot: Int) {
        super.init(frame: .zero)
        wantsLayer = true; layer?.cornerRadius = 6; normalBG = .clear

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.imageScaling = .scaleProportionallyUpOrDown
        dotView.translatesAutoresizingMaskIntoConstraints = false
        dotView.wantsLayer = true; dotView.layer?.cornerRadius = 3
        dotView.layer?.backgroundColor = NSColor(argb: C_GREEN).cgColor
        tipLabel.translatesAutoresizingMaskIntoConstraints = false
        tipLabel.font = NSFont(name: "Hack Nerd Font", size: 9) ?? NSFont.systemFont(ofSize: 9)
        tipLabel.textColor = NSColor(white: 1, alpha: 0.67)
        tipLabel.isEditable = false; tipLabel.isBordered = false; tipLabel.backgroundColor = .clear

        addSubview(imageView); addSubview(dotView); addSubview(tipLabel)
        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -3),
            imageView.widthAnchor.constraint(equalToConstant: appIconSize),
            imageView.heightAnchor.constraint(equalToConstant: appIconSize),
            dotView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
            dotView.centerXAnchor.constraint(equalTo: centerXAnchor),
            dotView.widthAnchor.constraint(equalToConstant: 5),
            dotView.heightAnchor.constraint(equalToConstant: 5),
            tipLabel.topAnchor.constraint(equalTo: topAnchor, constant: 1),
            tipLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -1),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func setIcon(bundleID: String) {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            imageView.image = NSWorkspace.shared.icon(forFile: url.path)
        }
    }
    func setIconByName(_ appName: String) {
        imageView.image = NSWorkspace.shared.icon(forFile: "/Applications/\(appName).app")
    }
}

// ──────────────────────────────────────────────────────────────────────────────
// MARK: – ActionSlotView (text launcher)
// ──────────────────────────────────────────────────────────────────────────────

class ActionSlotView: HubBarClickView {
    let label = NSTextField(labelWithString: "")

    init(slug: String) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.masksToBounds = true
        normalBG = .clear

        label.stringValue = slug
        label.font = monoFont12
        label.textColor = NSColor(argb: C_WHITE)
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.isEditable = false
        label.isBordered = false
        label.backgroundColor = .clear
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        let width = max(CGFloat(slug.count * 8 + 14), 30)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: min(width, 58)),
            heightAnchor.constraint(equalToConstant: appIconSize + 4),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 5),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -5),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
}

// ──────────────────────────────────────────────────────────────────────────────
// MARK: – WsWinSlotView
// ──────────────────────────────────────────────────────────────────────────────

class WsWinSlotView: HubBarClickView {
    let imageView = NSImageView()
    var windowIDs: [Int] = []; var rotateIdx = 0

    init() {
        super.init(frame: .zero)
        wantsLayer = true; layer?.cornerRadius = 6; normalBG = .clear
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -2),
            imageView.widthAnchor.constraint(equalToConstant: appIconSize),
            imageView.heightAnchor.constraint(equalToConstant: appIconSize),
        ])
        onPress = { [weak self] in
            guard let self = self, !self.windowIDs.isEmpty else { return }
            let wid = self.windowIDs[self.rotateIdx % self.windowIDs.count]
            self.rotateIdx += 1
            Process.launchedProcess(launchPath: FileManager.default.fileExists(atPath: "/opt/homebrew/bin/aerospace")
                ? "/opt/homebrew/bin/aerospace" : "/usr/local/bin/aerospace",
                arguments: ["focus", "--window-id", "\(wid)"])
        }
    }
    required init?(coder: NSCoder) { fatalError() }
}

// ──────────────────────────────────────────────────────────────────────────────
// MARK: – System processes filter
// ──────────────────────────────────────────────────────────────────────────────

private let SYSTEM_PROCS: Set<String> = [
    "SecurityAgent","UserNotificationCenter","ScreenSaverEngine",
    "System Preferences","System Settings","Finder","universalaccessd","loginwindow"
]
func isSystemProc(_ name: String) -> Bool { name.contains(".") || SYSTEM_PROCS.contains(name) }

// ──────────────────────────────────────────────────────────────────────────────
// MARK: – Volume popup window
// ──────────────────────────────────────────────────────────────────────────────

class VolumePopupWindow: NSWindow {
    var globalMonitor: Any?
    override init(contentRect: NSRect, styleMask: NSWindow.StyleMask,
                  backing: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: styleMask, backing: backing, defer: flag)
    }
    func installDismissMonitor() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in self?.dismiss() }
    }
    func dismiss() {
        if let m = globalMonitor { NSEvent.removeMonitor(m); globalMonitor = nil }
        orderOut(nil)
    }
}

// ──────────────────────────────────────────────────────────────────────────────
// MARK: – HubBarWindow (one per NSScreen)
// ──────────────────────────────────────────────────────────────────────────────

class HubBarWindow: NSWindow {
    let barScreen: NSScreen
    var monitorIndex: Int = 1
    // Transient state: true while the macOS menu bar is being revealed by cursor-at-top
    // in hub fullscreen mode. When true we drop the bar below the menu-bar strip.
    var menuBarRevealedInFullscreen: Bool = false
    
    // Track whether notifications are currently visible
    private var hasNotifications: Bool = false
    
    // Timer for checking notifications
    private var notificationCheckTimer: Timer?

    // Pill views keyed by ws id
    var wsPills: [String: WorkspacePill] = [:]
    var appSlots:   [AppSlotView]   = []
    var wsWinSlots: [WsWinSlotView] = []
    var volPopup: VolumePopupWindow?

    // Widget label refs for updates (cluster overlay)
    var clockLabel: NSTextField?
    var battLabel:  NSTextField?
    var battIcon:   NSTextField?
    var volLabel:   NSTextField?
    var volIcon:    NSTextField?
    var serviceModeLabel: NSView?

    // Cluster overlay (app icons + clock/battery/volume) — shown on demand
    var clusterOverlay: ClusterOverlayWindow?
    var clusterHideTimer: Timer?

    // Last fit decision, for applyRefresh change-detection
    var lastFitRows: Int = 0
    var lastFitCap: Int = -2  // sentinel "unknown"
    var lastFitDecision: FitDecision?
    var lastVisiblePillIDs: [String] = []
    var lastRenderedState: HubBarState = HubBarState()
    private var hoveredTruncatedWsID: String?
    private var hoverCollapseWorkItem: DispatchWorkItem?

    static let normalWindowLevel = NSWindow.Level.statusBar
    static let fullscreenWindowLevel = NSWindow.Level.statusBar // 21 — same as macOS notifications; allows notifications to appear above the bar while keeping it pinned at top edge

    static func isHubFullscreen() -> Bool {
        FileManager.default.fileExists(atPath: NSHomeDirectory() + "/.config/hub/fullscreen")
    }

    static func menuBarRevealInset(screen: NSScreen, sf: NSRect, vf: NSRect) -> CGFloat {
        let visibleInset = sf.maxY - vf.maxY
        if visibleInset > 1 { return visibleInset }

        if #available(macOS 12.0, *) {
            if let left = screen.auxiliaryTopLeftArea, left.height > 1 { return left.height }
            if let right = screen.auxiliaryTopRightArea, right.height > 1 { return right.height }
        }

        let statusBarInset = NSStatusBar.system.thickness
        return statusBarInset > 1 ? statusBarInset : 24
    }

    static func menuBarRevealClearance(screen: NSScreen, sf: NSRect, vf: NSRect) -> CGFloat {
        let inset = menuBarRevealInset(screen: screen, sf: sf, vf: vf)
        return inset > 0 ? inset + revealedMenuBarHubGap(forMajorOSVersion: currentMajorOSVersion()) : 0
    }

    // Bar top anchor in screen coords.
    // - Normal mode: align to visibleFrame.maxY (below persistent menu bar).
    // - Hub fullscreen + menu bar hidden: align to absolute screen top (sf.maxY).
    // - Hub fullscreen + transient menu bar revealed (cursor at top): subtract a measured
    //   menu-bar inset. visibleFrame often still equals frame while auto-hide is active.
    static func barTopY(screen: NSScreen, menuBarRevealedInFullscreen: Bool) -> CGFloat {
        let sf = screen.frame
        let vf = screen.visibleFrame
        if !isHubFullscreen() { return min(sf.maxY, vf.maxY + normalMenuBarOverlap) }
        if !menuBarRevealedInFullscreen { return sf.maxY }
        return sf.maxY - menuBarRevealClearance(screen: screen, sf: sf, vf: vf)
    }

    func applyWindowLevel(isFullscreen: Bool) {
        // Aggressive solution for notification overlap issue
        // In fullscreen mode, drop significantly below notifications
        // kCGNormalWindowLevel = 0, notifications typically use 21+, 
        // so we use a negative value to ensure we stay below everything
        level = isFullscreen 
            ? NSWindow.Level(rawValue: -1)  // Well below normal windows
            : HubBarWindow.normalWindowLevel
    }

    // Notch rect in window-local x coordinates (nil if no notch or not fullscreen)
    func notchRange(isFullscreen: Bool) -> (minX: CGFloat, maxX: CGFloat)? {
        guard isFullscreen else { return nil }
        if #available(macOS 12.0, *) {
            guard let l = barScreen.auxiliaryTopLeftArea,
                  let r = barScreen.auxiliaryTopRightArea else { return nil }
            let sf = barScreen.frame
            // Convert screen x to window-local x (window spans full screen width starting at sf.minX)
            return (minX: l.maxX - sf.minX, maxX: r.minX - sf.minX)
        }
        return nil
    }

    init(screen: NSScreen) {
        self.barScreen = screen
        let sf = screen.frame
        let topY = HubBarWindow.barTopY(screen: screen, menuBarRevealedInFullscreen: false)
        let isFullscreen = HubBarWindow.isHubFullscreen()
        let r = NSRect(x: sf.minX, y: topY - barHeightNormal, width: sf.width, height: barHeightNormal)
        super.init(contentRect: r, styleMask: .borderless, backing: .buffered, defer: false)
        // Normal mode: stay at floating level — above app windows, below macOS system UI.
        // In fullscreen the menu bar is auto-hidden and the bar owns the
        // notch row, so raise to shielding+1 so macOS doesn't clamp it below the top 32pt strip.
        applyWindowLevel(isFullscreen: isFullscreen)
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        ignoresMouseEvents = false
        isReleasedWhenClosed = false  // ARC owns lifetime; prevent double-free on close()
        // Join normal Spaces, but do not opt into native macOS full-screen Spaces.
        // Hub fullscreen mode is not a native full-screen Space, so it does not need
        // .fullScreenAuxiliary; including it lets the bar cover apps like Slack.
        collectionBehavior = [.canJoinAllSpaces, .stationary]
    }

    // Install timer for checking notifications
    func installNotificationMonitor() {
        // Check immediately on start
        checkForNotifications()
        
        // Then check periodically
        notificationCheckTimer?.invalidate()
        notificationCheckTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkForNotifications()
        }
    }
    
    // Check for active notifications and update window level accordingly
    func checkForNotifications() {
        let newHasNotifications = hasActiveNotifications()
        
        if newHasNotifications != hasNotifications {
            hasNotifications = newHasNotifications
            
            // Re-apply window level with the new notification state
            let isFullscreen = HubBarWindow.isHubFullscreen()
            applyWindowLevel(isFullscreen: isFullscreen)
            
            if hasNotifications {
                // When notifications appear, trigger a subtle visual feedback
                let originalAlpha = alphaValue
                alphaValue = 0.9
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    self.alphaValue = originalAlpha
                }
            }
        }
    }

    func buildContents(state: HubBarState, lastRows: Int = 1, writeBarMetrics: Bool = true) {
        lastRenderedState = state
        let cv = contentView!
        cv.subviews.forEach { $0.removeFromSuperview() }
        wsPills.removeAll(); appSlots.removeAll(); wsWinSlots.removeAll(); volPopup = nil
        clockLabel = nil; battLabel = nil; battIcon = nil; volLabel = nil; volIcon = nil
        serviceModeLabel = nil

        let sf = barScreen.frame
        let vf = barScreen.visibleFrame
        let topY = HubBarWindow.barTopY(screen: barScreen, menuBarRevealedInFullscreen: menuBarRevealedInFullscreen)
        // Keep fullscreen-specific layout (e.g. notch splitting) active even while the bar is
        // temporarily dropped below the revealed macOS menu bar.
        let isFullscreen = HubBarWindow.isHubFullscreen()
        applyWindowLevel(isFullscreen: isFullscreen)

        let monitorWs = state.monitorWorkspaces[monitorIndex]
        let pills = state.visiblePillInfos(monitorWs: monitorWs)
        lastVisiblePillIDs = pills.map { $0.ws }

        let notch = notchRange(isFullscreen: isFullscreen)
        let fit = decideFit(
            pills: pills, screenW: sf.width,
            notchMinX: notch?.minX, notchMaxX: notch?.maxX,
            isFullscreen: isFullscreen, focused: state.focused,
            claudeAlert: state.claudeAlert, claudeActive: state.claudeActive,
            mode: state.layoutMode,
            lastRows: lastRows)

        lastFitRows = fit.rows
        lastFitCap  = fit.effectiveCap
        lastFitDecision = fit
        if let hovered = hoveredTruncatedWsID {
            let hoveredPill = pills.first { $0.ws == hovered }
            if hoveredPill == nil || hoveredPill!.fullName.isEmpty {
                hoveredTruncatedWsID = nil
            }
        }

        // ── Resize window to match row count ───────────────────────────────
        let barH = barHeightNormal * CGFloat(fit.rows)
        setFrame(NSRect(x: sf.minX, y: topY - barH, width: sf.width, height: barH), display: true)

        // Write bar height for bar-sync (primary screen only to avoid multi-monitor flapping)
        let isPrimary = barScreen == NSScreen.screens.first
        if isPrimary && writeBarMetrics {
            let menuInset = topY >= sf.maxY ? 0 : Int(sf.maxY - vf.maxY)
            let home = NSHomeDirectory()
            // hub_bar_height drives AeroSpace's outer.top, which AeroSpace measures DOWN from
            // visibleFrame.maxY. The bar bottom sits at (topY - barH). In fullscreen the bar
            // top is at sf.maxY — above vf.maxY by (topY - vf.maxY) — so the bar bottom is only
            // (barH - that offset) below vf.maxY. Subtracting the offset keeps the visible gap
            // constant in both modes; in normal mode topY == vf.maxY so the offset is 0.
            let vfDrop = Int(topY - vf.maxY)
            try? "\(Int(barH) - vfDrop)".write(toFile: home + "/.config/hub/hub_bar_height", atomically: true, encoding: .utf8)
            // hub_bar_outer_top is the distance from the ABSOLUTE screen top to the bar bottom
            // (consumed by float_nudge, which works in top-left origin coords) — unchanged.
            try? "\(Int(barH) + menuInset)".write(toFile: home + "/.config/hub/hub_bar_outer_top", atomically: true, encoding: .utf8)
            if let hub = hubScriptPath() {
                Process.launchedProcess(launchPath: "/bin/sh",
                    arguments: ["-c", "'\(hub)' bar-sync >/dev/null 2>&1 &"])
            }
        }

        // ── Background (full-width; single continuous panel — notch is opaque black hardware) ──
        let bg = HubBarBackgroundView(frame: cv.bounds)
        bg.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(bg)
        NSLayoutConstraint.activate([
            bg.leadingAnchor.constraint(equalTo: cv.leadingAnchor),
            bg.trailingAnchor.constraint(equalTo: cv.trailingAnchor),
            bg.topAnchor.constraint(equalTo: cv.topAnchor),
            bg.bottomAnchor.constraint(equalTo: cv.bottomAnchor),
        ])

        // ── Build layout ────────────────────────────────────────────────────
        buildRowLayout(cv: cv, state: state, fit: fit,
                       notch: notch, isFullscreen: isFullscreen, pills: pills)
    }

    // ── Multi-row layout ─────────────────────────────────────────────────────

    func buildRowLayout(cv: NSView, state: HubBarState, fit: FitDecision,
                        notch: (minX: CGFloat, maxX: CGFloat)?,
                        isFullscreen: Bool, pills: [(ws: String, fullName: String, isFocused: Bool)]) {
        let rows = fit.rows
        let rowH = barHeightNormal

        // Service-mode pill: stays inline as a safety indicator (always visible).
        // Pinned to the right edge of row 0 — only built/shown when serviceMode is active.
        var servicePillTrailingX: CGFloat? = nil
        if state.serviceMode {
            let pill = makeServicePill()
            pill.translatesAutoresizingMaskIntoConstraints = false
            pill.isHidden = false
            serviceModeLabel = pill
            cv.addSubview(pill)
            NSLayoutConstraint.activate([
                pill.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -8),
                pill.centerYAnchor.constraint(equalTo: cv.topAnchor, constant: rowH / 2),
            ])
            // 30px pill + 8px trailing + 4px gap before pills
            servicePillTrailingX = 30 + 8 + 4
        }

        // Build one pill stack per row
        for r in 0..<rows {
            let pillIndices = r < fit.rowAssignment.count ? fit.rowAssignment[r] : []
            let rowPills = pillIndices.map { pills[$0] }

            if r > 0 {
                // Horizontal divider above rows 1+
                let div = NSView()
                div.wantsLayer = true
                div.layer?.backgroundColor = NSColor(argb: 0x0FFFFFFF).cgColor
                div.translatesAutoresizingMaskIntoConstraints = false
                cv.addSubview(div)
                NSLayoutConstraint.activate([
                    div.leadingAnchor.constraint(equalTo: cv.leadingAnchor),
                    div.trailingAnchor.constraint(equalTo: cv.trailingAnchor),
                    div.heightAnchor.constraint(equalToConstant: 1),
                    div.topAnchor.constraint(equalTo: cv.topAnchor, constant: rowH * CGFloat(r)),
                ])
            }

            let rowCenterY = rowH * CGFloat(r) + rowH / 2

            if r == 0 {
                if let split = fit.row0Split, let notchCoords = notch {
                    // Fullscreen+notch: two clip-view stacks around the notch gap.
                    buildTopRowPillsSplit(cv: cv, state: state, fit: fit,
                                         pills: rowPills, split: split,
                                         notch: notchCoords,
                                         servicePillTrailingX: servicePillTrailingX)
                } else {
                    // Normal / non-notch: single full-width pill stack.
                    buildTopRowPillsSingle(cv: cv, state: state, fit: fit,
                                           pills: rowPills,
                                           servicePillTrailingX: servicePillTrailingX)
                }
            } else {
                // Full-width rows below row 0 — no notch constraint.
                buildFullRow(cv: cv, state: state, fit: fit,
                             pills: rowPills, centerY: rowCenterY)
            }
        }

        // Hot right-edge zone: hover into the rightmost 8px of the bar to reveal the cluster overlay.
        // Uses a hover-only NSView (hitTest returns nil so clicks pass through to pills/service pill).
        let hotEdge = HotEdgeView()
        hotEdge.translatesAutoresizingMaskIntoConstraints = false
        hotEdge.onEnter = { [weak self] in self?.showClusterOverlay() }
        hotEdge.onExit  = { [weak self] in self?.scheduleHideClusterOverlay() }
        cv.addSubview(hotEdge)
        NSLayoutConstraint.activate([
            hotEdge.trailingAnchor.constraint(equalTo: cv.trailingAnchor),
            hotEdge.topAnchor.constraint(equalTo: cv.topAnchor),
            hotEdge.bottomAnchor.constraint(equalTo: cv.topAnchor, constant: rowH),
            hotEdge.widthAnchor.constraint(equalToConstant: 8),
        ])
    }

    // Single pill stack for row 0 (no notch split — normal mode or non-notched screen).
    private func buildTopRowPillsSingle(cv: NSView, state: HubBarState, fit: FitDecision,
                                        pills: [(ws: String, fullName: String, isFocused: Bool)],
                                        servicePillTrailingX: CGFloat?) {
        let clipView = NSView()
        clipView.wantsLayer = true; clipView.layer?.masksToBounds = true
        clipView.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(clipView)

        NSLayoutConstraint.activate([
            clipView.leadingAnchor.constraint(equalTo: cv.leadingAnchor),
            clipView.topAnchor.constraint(equalTo: cv.topAnchor),
            clipView.heightAnchor.constraint(equalToConstant: barHeightNormal),
        ])
        if let svcRightInset = servicePillTrailingX {
            clipView.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -svcRightInset).isActive = true
        } else {
            clipView.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -8).isActive = true
        }

        let stack = makeRowStack()
        clipView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: clipView.leadingAnchor, constant: 8),
            stack.centerYAnchor.constraint(equalTo: clipView.centerYAnchor),
            stack.heightAnchor.constraint(equalToConstant: pillH),
        ])
        populateStack(stack, pills: pills, state: state, fit: fit)
    }

    // Two pill stacks for row 0 in fullscreen+notch: left segment (before notch) and
    // right segment (after notch). Pills never straddle the notch.
    private func buildTopRowPillsSplit(cv: NSView, state: HubBarState, fit: FitDecision,
                                       pills: [(ws: String, fullName: String, isFocused: Bool)],
                                       split: Int,
                                       notch: (minX: CGFloat, maxX: CGFloat),
                                       servicePillTrailingX: CGFloat?) {
        let leftPills  = Array(pills[0..<min(split, pills.count)])
        let rightPills = Array(pills[min(split, pills.count)...])

        // Left clip-view: from leading edge to left side of notch
        let leftClip = NSView()
        leftClip.wantsLayer = true; leftClip.layer?.masksToBounds = true
        leftClip.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(leftClip)
        NSLayoutConstraint.activate([
            leftClip.leadingAnchor.constraint(equalTo: cv.leadingAnchor),
            leftClip.topAnchor.constraint(equalTo: cv.topAnchor),
            leftClip.heightAnchor.constraint(equalToConstant: barHeightNormal),
            leftClip.trailingAnchor.constraint(equalTo: cv.leadingAnchor, constant: notch.minX - 2),
        ])
        if !leftPills.isEmpty {
            let stack = makeRowStack()
            leftClip.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: leftClip.leadingAnchor, constant: 8),
                stack.centerYAnchor.constraint(equalTo: leftClip.centerYAnchor),
                stack.heightAnchor.constraint(equalToConstant: pillH),
            ])
            populateStack(stack, pills: leftPills, state: state, fit: fit)
        }

        // Right clip-view: from right side of notch to trailing edge
        if !rightPills.isEmpty {
            let rightClip = NSView()
            rightClip.wantsLayer = true; rightClip.layer?.masksToBounds = true
            rightClip.translatesAutoresizingMaskIntoConstraints = false
            cv.addSubview(rightClip)
            NSLayoutConstraint.activate([
                rightClip.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: notch.maxX + 2),
                rightClip.topAnchor.constraint(equalTo: cv.topAnchor),
                rightClip.heightAnchor.constraint(equalToConstant: barHeightNormal),
            ])
            if let svcRightInset = servicePillTrailingX {
                rightClip.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -svcRightInset).isActive = true
            } else {
                rightClip.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -8).isActive = true
            }
            let stack = makeRowStack()
            rightClip.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: rightClip.leadingAnchor, constant: 4),
                stack.centerYAnchor.constraint(equalTo: rightClip.centerYAnchor),
                stack.heightAnchor.constraint(equalToConstant: pillH),
            ])
            populateStack(stack, pills: rightPills, state: state, fit: fit)
        }
    }

    // Full-width row (rows 1+)
    private func buildFullRow(cv: NSView, state: HubBarState, fit: FitDecision,
                              pills: [(ws: String, fullName: String, isFocused: Bool)],
                              centerY: CGFloat) {
        let stack = makeRowStack()
        cv.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: cv.trailingAnchor, constant: -8),
            stack.centerYAnchor.constraint(equalTo: cv.topAnchor, constant: centerY),
            stack.heightAnchor.constraint(equalToConstant: pillH),
        ])
        populateStack(stack, pills: pills, state: state, fit: fit)
    }

    private func makeRowStack() -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = pillGap
        stack.alignment = .centerY
        stack.setContentHuggingPriority(.required, for: .horizontal)
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    private func populateStack(_ stack: NSStackView,
                                pills: [(ws: String, fullName: String, isFocused: Bool)],
                                state: HubBarState, fit: FitDecision) {
        for p in pills {
            let pill = wsPills[p.ws] ?? {
                let newPill = WorkspacePill(wsID: p.ws)
                newPill.translatesAutoresizingMaskIntoConstraints = false
                newPill.heightAnchor.constraint(equalToConstant: pillH).isActive = true
                let w = newPill.widthAnchor.constraint(equalToConstant: analyticalPillWidth(idx: p.ws, name: "", showDot: false))
                w.isActive = true
                newPill.widthConstraint = w
                newPill.onHoverChanged = { [weak self] wsID, isHovered in
                    self?.handlePillHover(wsID: wsID, isHovered: isHovered)
                }
                wsPills[p.ws] = newPill
                return newPill
            }()
            stack.addArrangedSubview(pill)
        }
        applyWorkspaceState(state: state, fit: fit, animateWidths: false)
    }

    // ── Workspace strip ──────────────────────────────────────────────────────

    func applyWorkspaceState(state: HubBarState, fit: FitDecision, animateWidths: Bool = false) {
        let hoveredWs = hoveredTruncatedWsID
        for ws in ALL_WS {
            guard let pill = wsPills[ws] else { continue }
            let isActive  = state.active.contains(ws) || ws == state.focused
            let isFocused = ws == state.focused
            let isLabeled = state.wsInfo[ws] != nil
            pill.isFocused = isFocused

            let hasAlert  = state.claudeAlert.contains(ws)
            let hasActive = state.claudeActive.contains(ws)
            let showDot   = hasAlert || hasActive
            let dotColor: UInt32 = hasActive ? DOT_BLUE : DOT_ORANGE
            // On the focused (teal) pill the blue dot blends in — use white instead.
            let focusedDotColor: UInt32 = hasActive ? 0xFFFFFFFF : DOT_ORANGE

            // Left-segment pills may use a relaxed cap (capFor); everyone else uses effectiveCap.
            let cap = fit.capFor(ws)
            let padH = fit.padFor(ws)
            let (idxStr, cappedName) = state.spansFor(ws: ws, cap: cap)
            let fullName = state.spansFor(ws: ws, cap: -1).1
            let canExpandOnHover = !fullName.isEmpty && cappedName != fullName
            let showExpandedName = hoveredWs == ws && !fullName.isEmpty
            let displayName = showExpandedName ? fullName : cappedName

            pill.setPadding(padH)
            pill.fullNameText = fullName
            pill.cappedNameText = cappedName
            pill.canExpandOnHover = canExpandOnHover
            pill.showDotState = showDot

            if isFocused {
                pill.apply(bg: ACCENT, idxColor: PILL_IDX_ACT, nameColor: PILL_NAME_ACT,
                           idx: idxStr, name: displayName, showDot: showDot, dotColor: focusedDotColor,
                           glowColor: ACCENT, glowRadius: 8)
                pill.isHidden = false
            } else if isActive {
                pill.apply(bg: PILL_IDLE_BG, idxColor: PILL_IDX_IDLE, nameColor: PILL_NAME_IDLE,
                           idx: idxStr, name: displayName, showDot: showDot, dotColor: dotColor,
                           glowColor: showDot ? dotColor : nil, glowRadius: 5)
                pill.isHidden = false
            } else if isLabeled {
                pill.apply(bg: PILL_IDLE_BG, idxColor: PILL_IDX_IDLE, nameColor: 0x55FFFFFF,
                           idx: idxStr, name: displayName, showDot: showDot, dotColor: dotColor,
                           glowColor: showDot ? dotColor : nil, glowRadius: 5)
                pill.isHidden = false
            } else {
                pill.isHidden = true
            }
        }

        layoutWorkspaceWidths(animated: animateWidths)
    }

    func makeServicePill() -> NSView {
        let pill = NSView()
        pill.wantsLayer = true
        pill.layer?.backgroundColor = NSColor(argb: SERVICE_BG).cgColor
        pill.layer?.cornerRadius = cornerRadius
        pill.layer?.masksToBounds = true
        pill.heightAnchor.constraint(equalToConstant: pillH).isActive = true
        pill.widthAnchor.constraint(equalToConstant: 30).isActive = true
        let lbl = NSTextField(labelWithString: "S")
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.font = nerdFont13; lbl.textColor = .white
        lbl.isEditable = false; lbl.isBordered = false; lbl.backgroundColor = .clear
        lbl.alignment = .center
        pill.addSubview(lbl)
        NSLayoutConstraint.activate([
            lbl.centerXAnchor.constraint(equalTo: pill.centerXAnchor),
            lbl.centerYAnchor.constraint(equalTo: pill.centerYAnchor),
        ])
        return pill
    }

    func applyRefresh(state: HubBarState, fit: FitDecision) {
        lastRenderedState = state
        lastFitDecision = fit
        let monitorWs = state.monitorWorkspaces[monitorIndex]
        lastVisiblePillIDs = state.visiblePillInfos(monitorWs: monitorWs).map { $0.ws }
        applyWorkspaceState(state: state, fit: fit)
        serviceModeLabel?.isHidden = !state.serviceMode
    }

    private func handlePillHover(wsID: String, isHovered: Bool) {
        hoverCollapseWorkItem?.cancel()
        if isHovered {
            hoveredTruncatedWsID = wsID
            guard let fit = lastFitDecision else { return }
            applyWorkspaceState(state: lastRenderedState, fit: fit, animateWidths: true)
            return
        }

        guard hoveredTruncatedWsID == wsID else { return }
        let collapse = DispatchWorkItem { [weak self] in
            guard let self = self, self.hoveredTruncatedWsID == wsID else { return }
            if let pill = self.wsPills[wsID], self.isPointerInsidePill(pill) {
                return
            }
            self.hoveredTruncatedWsID = nil
            guard let fit = self.lastFitDecision else { return }
            self.applyWorkspaceState(state: self.lastRenderedState, fit: fit, animateWidths: true)
        }
        hoverCollapseWorkItem = collapse
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10, execute: collapse)
    }

    private func isPointerInsidePill(_ pill: WorkspacePill) -> Bool {
        let pointInWindow = mouseLocationOutsideOfEventStream
        let pointInPill = pill.convert(pointInWindow, from: nil)
        return pill.bounds.contains(pointInPill)
    }

    private func layoutWorkspaceWidths(animated: Bool) {
        contentView?.layoutSubtreeIfNeeded()
        let expandedWs = hoveredTruncatedWsID
        var stacksByID: [ObjectIdentifier: NSStackView] = [:]
        for pill in wsPills.values {
            guard let stack = pill.superview as? NSStackView else { continue }
            stacksByID[ObjectIdentifier(stack)] = stack
        }

        for stack in stacksByID.values {
            guard let clipView = stack.superview else { continue }

            let rowPills = stack.arrangedSubviews
                .compactMap { $0 as? WorkspacePill }
                .filter { !$0.isHidden }
            guard !rowPills.isEmpty else { continue }

            let hoveredPill = rowPills.first {
                $0.wsID == expandedWs && !$0.fullNameText.isEmpty && $0.canExpandOnHover
            }
            let leadingInset = max(0, stack.frame.minX)
            let available = max(0, clipView.bounds.width - leadingInset)
            let gapTotal = pillGap * CGFloat(max(0, rowPills.count - 1))

            var targetWidths: [String: CGFloat] = [:]
            for pill in rowPills {
                if pill.wsID == hoveredPill?.wsID {
                    targetWidths[pill.wsID] = hoverExpandedPillWidth(
                        idx: pill.wsID,
                        fullName: pill.fullNameText,
                        cappedName: pill.cappedNameText,
                        showDot: pill.showDotState,
                        padH: pill.padHState)
                } else {
                    targetWidths[pill.wsID] = normalPillWidth(
                        idx: pill.wsID,
                        fullName: pill.fullNameText,
                        displayName: pill.cappedNameText,
                        showDot: pill.showDotState,
                        padH: pill.padHState)
                }
            }

            var total = gapTotal + rowPills.reduce(0) { $0 + (targetWidths[$1.wsID] ?? 0) }
            let deficit = total - available
            if deficit > 0.5, hoveredPill != nil {
                let shrinkable = rowPills
                    .filter { $0.wsID != hoveredPill!.wsID }
                    .map { pill -> (pill: WorkspacePill, minWidth: CGFloat, shrinkable: CGFloat) in
                        let current = targetWidths[pill.wsID] ?? 0
                        let minW = analyticalPillWidth(idx: pill.wsID, name: "", showDot: pill.showDotState, padH: pill.padHState)
                        return (pill, minW, max(0, current - minW))
                    }

                let totalShrinkable = shrinkable.reduce(0) { $0 + $1.shrinkable }
                if totalShrinkable > 0 {
                    let scale = min(1, deficit / totalShrinkable)
                    var residual = deficit
                    for item in shrinkable {
                        let reduction = item.shrinkable * scale
                        let current = targetWidths[item.pill.wsID] ?? item.minWidth
                        let reduced = max(item.minWidth, current - reduction)
                        targetWidths[item.pill.wsID] = reduced
                        residual -= (current - reduced)
                    }
                    if residual > 0.5 {
                        for item in shrinkable.sorted(by: { $0.shrinkable > $1.shrinkable }) {
                            guard residual > 0.5 else { break }
                            let current = targetWidths[item.pill.wsID] ?? item.minWidth
                            let extra = min(current - item.minWidth, residual)
                            if extra > 0 {
                                targetWidths[item.pill.wsID] = current - extra
                                residual -= extra
                            }
                        }
                    }
                }
            }

            total = gapTotal + rowPills.reduce(0) { $0 + (targetWidths[$1.wsID] ?? 0) }
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = animated ? 0.16 : 0
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.20, 0.85, 0.20, 1.0)
                for pill in rowPills {
                    guard let target = targetWidths[pill.wsID] else { continue }
                    pill.widthConstraint?.animator().constant = target
                }
                clipView.layoutSubtreeIfNeeded()
            }
        }
    }

    // ── Volume popup (kept from original) ───────────────────────────────────

    func toggleVolumePopup() {
        if let p = volPopup, p.isVisible { p.dismiss(); volPopup = nil; return }
        let popW: CGFloat = 220, popH: CGFloat = 44
        let barFrame = frame
        let popX = barFrame.maxX - 300
        let popY = barFrame.minY - popH - 4
        let popup = VolumePopupWindow(
            contentRect: NSRect(x: popX, y: popY, width: popW, height: popH),
            styleMask: .borderless, backing: .buffered, defer: false)
        popup.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)
        popup.backgroundColor = NSColor(argb: ITEM_BG)
        popup.isOpaque = false; popup.hasShadow = true
        popup.collectionBehavior = [.canJoinAllSpaces, .stationary]
        let cv = popup.contentView!
        cv.wantsLayer = true; cv.layer?.cornerRadius = cornerRadius
        cv.layer?.masksToBounds = true; cv.layer?.borderWidth = borderWidth
        cv.layer?.borderColor = NSColor(argb: ITEM_BG2).cgColor

        let muteIcon = NSTextField(labelWithString: "󰖁")
        muteIcon.translatesAutoresizingMaskIntoConstraints = false
        muteIcon.font = nerdFont13; muteIcon.textColor = NSColor(argb: C_WHITE)
        muteIcon.isEditable = false; muteIcon.isBordered = false; muteIcon.backgroundColor = .clear

        let slider = NSSlider(value: 0.5, minValue: 0, maxValue: 1, target: nil, action: nil)
        slider.translatesAutoresizingMaskIntoConstraints = false; slider.isContinuous = true

        let maxIcon = NSTextField(labelWithString: "󰕾")
        maxIcon.translatesAutoresizingMaskIntoConstraints = false
        maxIcon.font = nerdFont13; maxIcon.textColor = NSColor(argb: C_WHITE)
        maxIcon.isEditable = false; maxIcon.isBordered = false; maxIcon.backgroundColor = .clear

        cv.addSubview(muteIcon); cv.addSubview(slider); cv.addSubview(maxIcon)
        NSLayoutConstraint.activate([
            muteIcon.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 10),
            muteIcon.centerYAnchor.constraint(equalTo: cv.centerYAnchor),
            slider.leadingAnchor.constraint(equalTo: muteIcon.trailingAnchor, constant: 6),
            slider.trailingAnchor.constraint(equalTo: maxIcon.leadingAnchor, constant: -6),
            slider.centerYAnchor.constraint(equalTo: cv.centerYAnchor),
            maxIcon.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -10),
            maxIcon.centerYAnchor.constraint(equalTo: cv.centerYAnchor),
        ])

        var deviceID = AudioDeviceID(0)
        var sz = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &sz, &deviceID)
        var vol: Float32 = 0; sz = UInt32(MemoryLayout<Float32>.size)
        var volAddr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyData(deviceID, &volAddr, 0, nil, &sz, &vol)
        slider.doubleValue = Double(vol)

        let target = VolumeSliderTarget(deviceID: deviceID) { [weak self] in self?.clusterOverlay?.updateVolume() }
        slider.target = target; slider.action = #selector(VolumeSliderTarget.sliderChanged(_:))
        objc_setAssociatedObject(popup, "sliderTarget", target, .OBJC_ASSOCIATION_RETAIN)

        let muteBtn = HubBarClickView(frame: .zero)
        muteBtn.translatesAutoresizingMaskIntoConstraints = false
        muteBtn.onPress = { [weak self] in
            var mut: UInt32 = 0; var mutSz = UInt32(MemoryLayout<UInt32>.size)
            var mutAddr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute,
                mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
            AudioObjectGetPropertyData(deviceID, &mutAddr, 0, nil, &mutSz, &mut)
            mut = mut == 0 ? 1 : 0
            AudioObjectSetPropertyData(deviceID, &mutAddr, 0, nil, mutSz, &mut)
            self?.clusterOverlay?.updateVolume()
        }
        cv.addSubview(muteBtn)
        NSLayoutConstraint.activate([
            muteBtn.leadingAnchor.constraint(equalTo: cv.leadingAnchor),
            muteBtn.widthAnchor.constraint(equalTo: muteIcon.widthAnchor, constant: 20),
            muteBtn.topAnchor.constraint(equalTo: cv.topAnchor),
            muteBtn.bottomAnchor.constraint(equalTo: cv.bottomAnchor),
        ])
        popup.orderFrontRegardless(); popup.installDismissMonitor(); volPopup = popup
    }

    // ── Cluster overlay ──────────────────────────────────────────────────────

    func showClusterOverlay() {
        clusterHideTimer?.invalidate(); clusterHideTimer = nil
        if let ov = clusterOverlay, ov.isVisible { return }
        clusterOverlay?.close(); clusterOverlay = nil

        guard let ctrl = (NSApp.delegate as? AppDelegate)?.controller else { return }
        let state = ctrl.lastState
        let ov = ClusterOverlayWindow(barWindow: self, state: state)
        ov.onMouseEnteredOverlay = { [weak self] in
            self?.clusterHideTimer?.invalidate(); self?.clusterHideTimer = nil
        }
        ov.onMouseExitedOverlay = { [weak self] in
            self?.scheduleHideClusterOverlay()
        }
        ov.dismissAction = { [weak self] in
            self?.clusterOverlay = nil
        }
        clusterOverlay = ov
        ov.orderFrontRegardless()
        ov.installDismissMonitor()
    }

    func scheduleHideClusterOverlay() {
        clusterHideTimer?.invalidate()
        clusterHideTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: false) { [weak self] _ in
            self?.hideClusterOverlay()
        }
    }

    func hideClusterOverlay() {
        clusterHideTimer?.invalidate(); clusterHideTimer = nil
        clusterOverlay?.dismiss()
        clusterOverlay = nil
    }
}

// ──────────────────────────────────────────────────────────────────────────────
// MARK: – HotEdgeView (hover-only; hitTest returns nil so clicks pass through)
// ──────────────────────────────────────────────────────────────────────────────

class HotEdgeView: NSView {
    var onEnter: (() -> Void)?
    var onExit:  (() -> Void)?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }  // clicks pass through

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil))
    }
    override func mouseEntered(with event: NSEvent) { onEnter?() }
    override func mouseExited(with event: NSEvent)  { onExit?() }
}

// ──────────────────────────────────────────────────────────────────────────────
// MARK: – CPU & Memory helpers
// ──────────────────────────────────────────────────────────────────────────────

// Previous CPU tick snapshot for delta-based instantaneous usage.
private var prevCPUUser:   Int32 = 0
private var prevCPUSystem: Int32 = 0
private var prevCPUIdle:   Int32 = 0

func cpuUsagePercent() -> Int {
    var numCPUs: natural_t = 0
    var cpuInfo: processor_info_array_t?
    var numCPUInfo: mach_msg_type_number_t = 0
    let err = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &numCPUs, &cpuInfo, &numCPUInfo)
    guard err == KERN_SUCCESS, let info = cpuInfo else { return 0 }
    defer {
        vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info),
                      vm_size_t(numCPUInfo) * vm_size_t(MemoryLayout<integer_t>.stride))
    }
    var totalUser: Int32 = 0; var totalSystem: Int32 = 0; var totalIdle: Int32 = 0
    let stride = Int(CPU_STATE_MAX)
    for i in 0..<Int(numCPUs) {
        totalUser   += info[i * stride + Int(CPU_STATE_USER)]
        totalSystem += info[i * stride + Int(CPU_STATE_SYSTEM)]
        totalIdle   += info[i * stride + Int(CPU_STATE_IDLE)]
    }
    let dUser   = totalUser   - prevCPUUser
    let dSystem = totalSystem - prevCPUSystem
    let dIdle   = totalIdle   - prevCPUIdle
    prevCPUUser = totalUser; prevCPUSystem = totalSystem; prevCPUIdle = totalIdle
    let dTotal = dUser + dSystem + dIdle
    guard dTotal > 0 else { return 0 }
    return Int(Double(dUser + dSystem) / Double(dTotal) * 100)
}

func memoryUsagePercent() -> Int {
    var vmStats = vm_statistics64_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
    let result = withUnsafeMutablePointer(to: &vmStats) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
        }
    }
    guard result == KERN_SUCCESS else { return 0 }
    let pageSize = UInt64(vm_kernel_page_size)
    let active   = UInt64(vmStats.active_count)   * pageSize
    let inactive = UInt64(vmStats.inactive_count) * pageSize
    let wired    = UInt64(vmStats.wire_count)      * pageSize
    let free     = UInt64(vmStats.free_count)      * pageSize
    let compressed = UInt64(vmStats.compressor_page_count) * pageSize
    let total = active + inactive + wired + free + compressed
    guard total > 0 else { return 0 }
    return Int(Double(active + wired + compressed) / Double(total) * 100)
}

func resourceColor(pct: Int) -> UInt32 {
    if pct >= 80 { return C_RED }
    if pct >= 60 { return C_YELLOW }
    return C_GREEN
}

// ──────────────────────────────────────────────────────────────────────────────
// MARK: – ClusterOverlayWindow (app launcher + widgets, shown on demand)
// ──────────────────────────────────────────────────────────────────────────────

class ClusterOverlayWindow: NSWindow {
    var globalMouseMonitor: Any?
    var dismissAction: (() -> Void)?
    var onMouseEnteredOverlay: (() -> Void)?
    var onMouseExitedOverlay:  (() -> Void)?

    // Widget refs for periodic updates
    var clockLabel: NSTextField?
    var battLabel:  NSTextField?
    var battIcon:   NSTextField?
    var volLabel:   NSTextField?
    var volIcon:    NSTextField?
    var cpuLabel:   NSTextField?
    var memLabel:   NSTextField?
    var appSlots:   [AppSlotView]   = []
    var wsWinSlots: [WsWinSlotView] = []

    init(barWindow: HubBarWindow, state: HubBarState) {
        let overlayH: CGFloat = 52
        let barFrame = barWindow.frame
        // Start with a generous placeholder width; we resize to fit after content is built.
        super.init(contentRect: NSRect(x: 0, y: 0, width: 600, height: overlayH),
                   styleMask: .borderless, backing: .buffered, defer: false)
        level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        ignoresMouseEvents = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        buildContent(state: state)

        // Resize to natural content width now that labels are populated.
        contentView?.layoutSubtreeIfNeeded()
        let naturalW = contentView?.fittingSize.width ?? 400
        let overlayW = naturalW
        let popX = barFrame.maxX - overlayW - 8
        let popY = barFrame.minY - overlayH - 4
        setFrame(NSRect(x: popX, y: popY, width: overlayW, height: overlayH), display: false)

        installTrackingArea()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func buildContent(state: HubBarState) {
        let cv = contentView!
        cv.wantsLayer = true
        cv.layer?.cornerRadius = cornerRadius
        cv.layer?.masksToBounds = true
        cv.layer?.backgroundColor = NSColor(argb: ITEM_BG).cgColor
        cv.layer?.borderWidth = 1
        cv.layer?.borderColor = NSColor(argb: ITEM_BG2).cgColor

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(stack)
        // The trailing constraint drives fittingSize: cv must be wide enough to hold
        // the stack + 30pt clearance for the ✕ button.
        let trailingConstraint = cv.trailingAnchor.constraint(greaterThanOrEqualTo: stack.trailingAnchor, constant: 30)
        trailingConstraint.priority = .required
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 10),
            stack.centerYAnchor.constraint(equalTo: cv.centerYAnchor),
            trailingConstraint,
        ])

        // Layout mode icon (expand → shows compress icon to return to shrink)
        if state.layoutMode == .expand {
            let icon = NSTextField(labelWithString: "\u{F066}")
            icon.font = nerdFont13; icon.textColor = NSColor(argb: C_ORANGE)
            icon.isEditable = false; icon.isBordered = false; icon.backgroundColor = .clear
            let click = HubBarClickView(frame: .zero)
            click.onPress = { [weak self] in
                guard let hub = hubScriptPath() else { return }
                Process.launchedProcess(launchPath: "/bin/sh",
                    arguments: ["-c", "'\(hub)' bar-layout shrink >/dev/null 2>&1 &"])
                self?.dismiss()
            }
            let wrap = NSView()
            wrap.translatesAutoresizingMaskIntoConstraints = false
            icon.translatesAutoresizingMaskIntoConstraints = false
            click.translatesAutoresizingMaskIntoConstraints = false
            wrap.addSubview(icon); wrap.addSubview(click)
            NSLayoutConstraint.activate([
                icon.leadingAnchor.constraint(equalTo: wrap.leadingAnchor),
                icon.trailingAnchor.constraint(equalTo: wrap.trailingAnchor),
                icon.topAnchor.constraint(equalTo: wrap.topAnchor),
                icon.bottomAnchor.constraint(equalTo: wrap.bottomAnchor),
                click.leadingAnchor.constraint(equalTo: wrap.leadingAnchor),
                click.trailingAnchor.constraint(equalTo: wrap.trailingAnchor),
                click.topAnchor.constraint(equalTo: wrap.topAnchor),
                click.bottomAnchor.constraint(equalTo: wrap.bottomAnchor),
            ])
            stack.addArrangedSubview(wrap)
        }

        // App icon group — shown when apps are configured (the overlay is on-demand, so its
        // sections are always populated; there's no per-section toggle anymore).
        if !state.apps.isEmpty {
            let group = buildAppIconGroup(state: state)
            group.translatesAutoresizingMaskIntoConstraints = false
            stack.addArrangedSubview(group)
        }

        if !state.actions.isEmpty {
            let group = buildActionGroup(state: state)
            group.translatesAutoresizingMaskIntoConstraints = false
            stack.addArrangedSubview(group)
        }

        // Volume + battery + clock — always present in the overlay.
        stack.addArrangedSubview(makeHSpacer(4))
        buildCPUInto(stack)
        buildMemInto(stack)
        buildVolumeInto(stack)
        buildBatteryInto(stack)
        buildClockInto(stack)

        // ✕ dismiss button (AGENTS.md "Dismissable HUDs" pattern — uses Theme.makeDismissButton)
        let xBtn = Theme.makeDismissButton(onPress: { [weak self] in self?.dismiss() })
        cv.addSubview(xBtn)
        NSLayoutConstraint.activate([
            xBtn.topAnchor.constraint(equalTo: cv.topAnchor, constant: 4),
            xBtn.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -4),
            xBtn.widthAnchor.constraint(equalToConstant: 18),
            xBtn.heightAnchor.constraint(equalToConstant: 18),
        ])

        updateVolume(); updateBattery(); updateClock(); updateCPU(); updateMem()
    }

    private func buildAppIconGroup(state: HubBarState) -> NSView {
        let group = NSView()
        group.wantsLayer = true
        group.layer?.backgroundColor = NSColor(argb: APPGRP_BG).cgColor
        group.layer?.cornerRadius = APPGRP_RADIUS
        group.layer?.masksToBounds = true
        group.layer?.borderWidth = 1
        group.layer?.borderColor = NSColor(argb: APPGRP_BORDER).cgColor
        group.setContentHuggingPriority(.required, for: .horizontal)

        let inner = NSStackView()
        inner.orientation = .horizontal; inner.spacing = appGroupGap; inner.alignment = .centerY
        inner.translatesAutoresizingMaskIntoConstraints = false
        group.addSubview(inner)
        NSLayoutConstraint.activate([
            inner.centerYAnchor.constraint(equalTo: group.centerYAnchor),
            inner.leadingAnchor.constraint(equalTo: group.leadingAnchor, constant: 14),
            inner.trailingAnchor.constraint(equalTo: group.trailingAnchor, constant: -14),
            group.heightAnchor.constraint(equalToConstant: pillH + 8),
        ])

        let hub = hubScriptPath() ?? ""
        let launcherNames = Set(state.apps.compactMap { $0["name"] })
        for (i, app) in state.apps.enumerated() {
            let slot = i + 1
            let sv = AppSlotView(slot: slot)
            sv.translatesAutoresizingMaskIntoConstraints = false
            sv.widthAnchor.constraint(equalToConstant: appIconSize + 4).isActive = true
            sv.heightAnchor.constraint(equalToConstant: appIconSize + 4).isActive = true
            if let bid = app["bundle_id"] ?? app["bundleID"], !bid.isEmpty {
                sv.setIcon(bundleID: bid)
            } else if let name = app["name"], !name.isEmpty {
                if let running = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == name }),
                   let url = running.bundleURL {
                    sv.imageView.image = NSWorkspace.shared.icon(forFile: url.path)
                } else { sv.setIconByName(name) }
            }
            let appName = app["name"] ?? ""
            sv.dotView.isHidden = !state.currentWindows.contains { $0.app == appName }
            sv.onPress = { [weak sv] in
                guard !hub.isEmpty else { return }
                let mods = NSEvent.modifierFlags
                let force = mods.contains(.shift) ? " --force" : ""
                Process.launchedProcess(launchPath: "/bin/sh", arguments: ["-c", "'\(hub)' open \(slot)\(force)"])
                sv?.layer?.backgroundColor = NSColor(argb: CLICK_BG).withAlphaComponent(0.3).cgColor
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { sv?.layer?.backgroundColor = nil }
            }
            appSlots.append(sv)
            inner.addArrangedSubview(sv)
        }

        var seen = Set<String>()
        var extraApps: [(app: String, ids: [Int])] = []
        for win in state.currentWindows {
            let app = win.app
            if isSystemProc(app) || launcherNames.contains(app) { continue }
            if seen.contains(app) {
                if let idx = extraApps.firstIndex(where: { $0.app == app }) { extraApps[idx].ids.append(win.id) }
                continue
            }
            seen.insert(app)
            if extraApps.count < 5 { extraApps.append((app: app, ids: [win.id])) }
        }
        for entry in extraApps {
            let slot = WsWinSlotView()
            slot.translatesAutoresizingMaskIntoConstraints = false
            slot.widthAnchor.constraint(equalToConstant: appIconSize + 4).isActive = true
            slot.heightAnchor.constraint(equalToConstant: appIconSize + 4).isActive = true
            slot.windowIDs = entry.ids
            let appPath = "/Applications/\(entry.app).app"
            if FileManager.default.fileExists(atPath: appPath) {
                slot.imageView.image = NSWorkspace.shared.icon(forFile: appPath)
            } else if let running = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == entry.app }),
                      let url = running.bundleURL {
                slot.imageView.image = NSWorkspace.shared.icon(forFile: url.path)
            }
            wsWinSlots.append(slot)
            inner.addArrangedSubview(slot)
        }
        return group
    }

    private func buildActionGroup(state: HubBarState) -> NSView {
        let group = NSView()
        group.wantsLayer = true
        group.layer?.backgroundColor = NSColor(argb: APPGRP_BG).cgColor
        group.layer?.cornerRadius = APPGRP_RADIUS
        group.layer?.masksToBounds = true
        group.layer?.borderWidth = 1
        group.layer?.borderColor = NSColor(argb: APPGRP_BORDER).cgColor
        group.setContentHuggingPriority(.required, for: .horizontal)

        let inner = NSStackView()
        inner.orientation = .horizontal; inner.spacing = appGroupGap; inner.alignment = .centerY
        inner.translatesAutoresizingMaskIntoConstraints = false
        group.addSubview(inner)
        NSLayoutConstraint.activate([
            inner.centerYAnchor.constraint(equalTo: group.centerYAnchor),
            inner.leadingAnchor.constraint(equalTo: group.leadingAnchor, constant: 10),
            inner.trailingAnchor.constraint(equalTo: group.trailingAnchor, constant: -10),
            group.heightAnchor.constraint(equalToConstant: pillH + 8),
        ])

        let hub = hubScriptPath() ?? ""
        for action in state.actions {
            guard let slug = action["slug"], !slug.isEmpty else { continue }
            guard slug.range(of: "^[A-Za-z0-9_-]{1,21}$", options: .regularExpression) != nil else { continue }
            let sv = ActionSlotView(slug: slug)
            sv.translatesAutoresizingMaskIntoConstraints = false
            sv.onPress = { [weak sv] in
                guard !hub.isEmpty else { return }
                Process.launchedProcess(launchPath: "/bin/sh",
                    arguments: ["-c", "'\(hub)' actions run '\(slug)' >/dev/null 2>&1 &"])
                sv?.layer?.backgroundColor = NSColor(argb: CLICK_BG).withAlphaComponent(0.3).cgColor
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { sv?.layer?.backgroundColor = nil }
            }
            inner.addArrangedSubview(sv)
        }

        return group
    }

    private func makeHSpacer(_ w: CGFloat) -> NSView {
        let v = NSView(); v.translatesAutoresizingMaskIntoConstraints = false
        v.widthAnchor.constraint(equalToConstant: w).isActive = true; return v
    }

    private func buildVolumeInto(_ stack: NSStackView) {
        let s = NSStackView(); s.orientation = .horizontal; s.spacing = 4; s.alignment = .centerY
        let ic = NSTextField(labelWithString: "󰕾")
        ic.font = nerdFont16; ic.textColor = NSColor(argb: C_BLUE)
        ic.isEditable = false; ic.isBordered = false; ic.backgroundColor = .clear
        let lbl = NSTextField(labelWithString: "")
        lbl.font = monoFont12; lbl.textColor = NSColor(argb: 0xFFC9CDD6)
        lbl.isEditable = false; lbl.isBordered = false; lbl.backgroundColor = .clear
        s.addArrangedSubview(ic); s.addArrangedSubview(lbl)
        volIcon = ic; volLabel = lbl
        stack.addArrangedSubview(s)
    }

    private func buildCPUInto(_ stack: NSStackView) {
        let s = NSStackView(); s.orientation = .horizontal; s.spacing = 4; s.alignment = .centerY
        let ic = NSTextField(labelWithString: "󰘚")
        ic.font = nerdFont16; ic.textColor = NSColor(argb: C_GREEN)
        ic.isEditable = false; ic.isBordered = false; ic.backgroundColor = .clear
        let lbl = NSTextField(labelWithString: "")
        lbl.font = monoFont12; lbl.textColor = NSColor(argb: 0xFFC9CDD6)
        lbl.isEditable = false; lbl.isBordered = false; lbl.backgroundColor = .clear
        s.addArrangedSubview(ic); s.addArrangedSubview(lbl)
        cpuLabel = lbl
        stack.addArrangedSubview(s)
    }

    private func buildMemInto(_ stack: NSStackView) {
        let s = NSStackView(); s.orientation = .horizontal; s.spacing = 4; s.alignment = .centerY
        let ic = NSTextField(labelWithString: "󰍛")
        ic.font = nerdFont16; ic.textColor = NSColor(argb: C_GREEN)
        ic.isEditable = false; ic.isBordered = false; ic.backgroundColor = .clear
        let lbl = NSTextField(labelWithString: "")
        lbl.font = monoFont12; lbl.textColor = NSColor(argb: 0xFFC9CDD6)
        lbl.isEditable = false; lbl.isBordered = false; lbl.backgroundColor = .clear
        s.addArrangedSubview(ic); s.addArrangedSubview(lbl)
        memLabel = lbl
        stack.addArrangedSubview(s)
    }

    func updateCPU() {
        let pct = cpuUsagePercent()
        cpuLabel?.stringValue = "\(pct)%"
        cpuLabel?.textColor = NSColor(argb: resourceColor(pct: pct))
    }

    func updateMem() {
        let pct = memoryUsagePercent()
        memLabel?.stringValue = "\(pct)%"
        memLabel?.textColor = NSColor(argb: resourceColor(pct: pct))
    }

    private func buildBatteryInto(_ stack: NSStackView) {
        let s = NSStackView(); s.orientation = .horizontal; s.spacing = 4; s.alignment = .centerY
        let ic = NSTextField(labelWithString: "󰁹")
        ic.font = nerdFont16; ic.textColor = NSColor(argb: C_GREEN)
        ic.isEditable = false; ic.isBordered = false; ic.backgroundColor = .clear
        let lbl = NSTextField(labelWithString: "")
        lbl.font = monoFont12; lbl.textColor = NSColor(argb: 0xFFC9CDD6)
        lbl.isEditable = false; lbl.isBordered = false; lbl.backgroundColor = .clear
        s.addArrangedSubview(ic); s.addArrangedSubview(lbl)
        battIcon = ic; battLabel = lbl
        stack.addArrangedSubview(s)
    }

    private func buildClockInto(_ stack: NSStackView) {
        let pill = NSView()
        pill.wantsLayer = true
        pill.layer?.backgroundColor = NSColor(argb: ACCENT_SOFT).cgColor
        pill.layer?.cornerRadius = 8
        pill.layer?.masksToBounds = true
        let inner = NSStackView()
        inner.orientation = .horizontal; inner.spacing = 6; inner.alignment = .centerY
        inner.translatesAutoresizingMaskIntoConstraints = false
        let dot = NSView()
        dot.wantsLayer = true; dot.layer?.cornerRadius = 3
        dot.layer?.backgroundColor = NSColor(argb: ACCENT).cgColor
        dot.translatesAutoresizingMaskIntoConstraints = false
        dot.widthAnchor.constraint(equalToConstant: 6).isActive = true
        dot.heightAnchor.constraint(equalToConstant: 6).isActive = true
        let lbl = NSTextField(labelWithString: "")
        lbl.font = monoFont12; lbl.textColor = NSColor(argb: 0xFFE8EAF0)
        lbl.isEditable = false; lbl.isBordered = false; lbl.backgroundColor = .clear
        clockLabel = lbl
        inner.addArrangedSubview(dot); inner.addArrangedSubview(lbl)
        pill.addSubview(inner)
        NSLayoutConstraint.activate([
            inner.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 10),
            inner.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -10),
            inner.centerYAnchor.constraint(equalTo: pill.centerYAnchor),
            pill.heightAnchor.constraint(equalToConstant: pillH),
        ])
        pill.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(pill)
    }

    func updateClock() {
        let fmt = DateFormatter(); fmt.dateFormat = "EEE dd MMM  HH:mm"
        clockLabel?.stringValue = fmt.string(from: Date())
    }
    func updateBattery() {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef],
              let src = list.first,
              let desc = IOPSGetPowerSourceDescription(info, src)?.takeUnretainedValue() as? [String: Any]
        else { return }
        let pct = desc[kIOPSCurrentCapacityKey] as? Int ?? 0
        let charging = (desc[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
        let (icon, color): (String, UInt32) = {
            if charging { return ("󰂄", C_BLUE) }
            switch pct {
            case 90...100: return ("󰁹", C_GREEN); case 70...89: return ("󰂀", C_GREEN)
            case 50...69:  return ("󰁾", C_GREEN); case 30...49: return ("󰁼", C_ORANGE)
            case 10...29:  return ("󰁺", C_RED);   default:      return ("󰂃", C_RED)
            }
        }()
        battIcon?.stringValue = icon; battIcon?.textColor = NSColor(argb: color)
        battLabel?.stringValue = "\(pct)%"
    }
    func updateVolume() {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &deviceID)
        var muted: UInt32 = 0; size = UInt32(MemoryLayout<UInt32>.size)
        var muteAddr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyData(deviceID, &muteAddr, 0, nil, &size, &muted)
        var vol: Float32 = 0; size = UInt32(MemoryLayout<Float32>.size)
        var volAddr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyData(deviceID, &volAddr, 0, nil, &size, &vol)
        let pct = Int(vol * 100)
        if muted != 0 { volIcon?.stringValue = "󰖁" } else {
            switch pct {
            case 60...100: volIcon?.stringValue = "󰕾"
            case 30...59:  volIcon?.stringValue = "󰖀"
            case 1...29:   volIcon?.stringValue = "󰕿"
            default:       volIcon?.stringValue = "󰖁"
            }
        }
        volLabel?.stringValue = "\(pct)%"
    }

    private func installTrackingArea() {
        guard let cv = contentView else { return }
        let track = NSTrackingArea(rect: cv.bounds,
            options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        cv.addTrackingArea(track)
    }
    override func mouseEntered(with event: NSEvent) { onMouseEnteredOverlay?() }
    override func mouseExited(with event: NSEvent)  { onMouseExitedOverlay?() }

    func installDismissMonitor() {
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.dismiss()
        }
    }
    func dismiss() {
        if let m = globalMouseMonitor { NSEvent.removeMonitor(m); globalMouseMonitor = nil }
        dismissAction?()
        orderOut(nil)
    }
}

// ──────────────────────────────────────────────────────────────────────────────
// MARK: – Volume slider target (ObjC bridge)
// ──────────────────────────────────────────────────────────────────────────────

class VolumeSliderTarget: NSObject {
    let deviceID: AudioDeviceID; let onChange: () -> Void
    init(deviceID: AudioDeviceID, onChange: @escaping () -> Void) { self.deviceID = deviceID; self.onChange = onChange }
    @objc func sliderChanged(_ sender: NSSlider) {
        var vol = Float32(sender.doubleValue)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        let sz = UInt32(MemoryLayout<Float32>.size)
        AudioObjectSetPropertyData(deviceID, &addr, 0, nil, sz, &vol)
        onChange()
    }
}

// ──────────────────────────────────────────────────────────────────────────────
// MARK: – HubBarController
// ──────────────────────────────────────────────────────────────────────────────

class HubBarController: NSObject {
    var windows: [HubBarWindow] = []
    var clockTimer: Timer?; var batteryTimer: Timer?; var pulseTimer: Timer?
    var staleClaudeTimer: Timer?
    var menuBarRevealTimer: Timer?
    var nativeFullscreenTimer: Timer?
    var cpuMemTimer: Timer?
    var nativeFullscreenDisplayIDs = Set<CGDirectDisplayID>()
    var menuBarRevealGeneration: Int = 0
    var pulseBright = true; var lastState = HubBarState()
    var rightShiftWasDown = false
    var rightShiftTapArmed = false
    var lastRightShiftDownTime: CFAbsoluteTime = 0
    var flagsChangedEventTap: CFMachPort?

    func start() {
        removeTransientBarHeightOverride(sync: false)
        writePIDFile()
        buildWindows()
        installSignalSource()
        installClusterTriggers()
        startTimers()
        installMenuBarRevealMonitor()
        installNotificationMonitor()
    }

    func installClusterTriggers() {
        // Both-shift trigger and right-shift double-tap trigger via CGEventTap.
        // NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) is silently broken on
        // macOS 26 (Tahoe) even with Input Monitoring granted; CGEventTap works reliably.
        // NX_DEVICELSHIFTKEYMASK = 0x0002, NX_DEVICERSHIFTKEYMASK = 0x0004
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let tapMask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        flagsChangedEventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: tapMask,
            callback: { _, _, event, userInfo -> Unmanaged<CGEvent>? in
                if let userInfo = userInfo, let nsEv = NSEvent(cgEvent: event) {
                    let ctrl = Unmanaged<HubBarController>.fromOpaque(userInfo).takeUnretainedValue()
                    let raw = nsEv.modifierFlags.rawValue
                    let bothShift = (raw & 0x0002 != 0) && (raw & 0x0004 != 0)
                    let primaryWindow = ctrl.windows.first
                    if bothShift {
                        primaryWindow?.showClusterOverlay()
                    } else if primaryWindow?.clusterOverlay?.isVisible == true {
                        primaryWindow?.scheduleHideClusterOverlay()
                    }
                    ctrl.handleRightShiftTap(nsEv)
                }
                return Unmanaged.passRetained(event)
            },
            userInfo: selfPtr
        )
        if let tap = flagsChangedEventTap {
            let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
        } else {
            // Fallback: NSEvent monitor (works on pre-Tahoe without Input Monitoring issues)
            NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] ev in
                let raw = ev.modifierFlags.rawValue
                let bothShift = (raw & 0x0002 != 0) && (raw & 0x0004 != 0)
                guard let self = self else { return }
                let primaryWindow = self.windows.first
                if bothShift {
                    primaryWindow?.showClusterOverlay()
                } else if primaryWindow?.clusterOverlay?.isVisible == true {
                    primaryWindow?.scheduleHideClusterOverlay()
                }
                self.handleRightShiftTap(ev)
            }
        }

        // Right-shift double-tap trigger: toggles AeroSpace fullscreen. A global keyDown
        // monitor disarms the pending tap whenever a real key is struck in between,
        // so ordinary typing (e.g. Shift for "New York") never fires it.
        NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] _ in
            self?.rightShiftTapArmed = false
        }
    }

    private func shiftLog(_ msg: String) {
        let logPath = NSHomeDirectory() + "/.config/hub/hub.log"
        let line = "[shift-debug] \(msg)\n"
        if let data = line.data(using: .utf8),
           let fh = FileHandle(forWritingAtPath: logPath) {
            fh.seekToEndOfFile(); fh.write(data); fh.closeFile()
        }
    }

    // NX_DEVICELSHIFTKEYMASK = 0x0002, NX_DEVICERSHIFTKEYMASK = 0x0004
    private func handleRightShiftTap(_ ev: NSEvent) {
        let raw = ev.modifierFlags.rawValue
        let mods = ev.modifierFlags
        let isolatedRightShift = (raw & 0x0004 != 0) && (raw & 0x0002 == 0)
            && mods.intersection([.control, .option, .command, .capsLock, .function]).isEmpty
        shiftLog(String(format: "raw=0x%08x rShift=%d lShift=%d isolated=%d wasDown=%d armed=%d",
            raw, (raw & 0x0004) != 0 ? 1 : 0, (raw & 0x0002) != 0 ? 1 : 0,
            isolatedRightShift ? 1 : 0, rightShiftWasDown ? 1 : 0, rightShiftTapArmed ? 1 : 0))
        if isolatedRightShift {
            if !rightShiftWasDown {
                let now = CFAbsoluteTimeGetCurrent()
                if rightShiftTapArmed && (now - lastRightShiftDownTime) < 0.4 {
                    rightShiftTapArmed = false
                    shiftLog("FIRE triggerFullscreenToggle")
                    triggerFullscreenToggle()
                } else {
                    rightShiftTapArmed = true
                    lastRightShiftDownTime = now
                    shiftLog("ARMED")
                }
            }
        } else if raw != 0 || !mods.isEmpty {
            shiftLog("DISARMED (raw != 0 or mods not empty)")
            rightShiftTapArmed = false
        }
        rightShiftWasDown = isolatedRightShift
    }

    private func triggerFullscreenToggle() {
        let aerospace = FileManager.default.fileExists(atPath: "/opt/homebrew/bin/aerospace")
            ? "/opt/homebrew/bin/aerospace" : "/usr/local/bin/aerospace"
        Process.launchedProcess(launchPath: aerospace, arguments: ["fullscreen"])
    }

    func installNotificationMonitor() {
        windows.forEach { $0.installNotificationMonitor() }
    }

    func writePIDFile() {
        let path = NSHomeDirectory() + "/.config/hub/hub_bar.pid"
        try? "\(ProcessInfo.processInfo.processIdentifier)\n".write(toFile: path, atomically: true, encoding: .utf8)
    }

    private func installMenuBarRevealMonitor() {
        menuBarRevealTimer?.invalidate()
        menuBarRevealTimer = Timer.scheduledTimer(withTimeInterval: 0.06, repeats: true) { [weak self] _ in
            self?.updateMenuBarRevealState()
        }
        RunLoop.main.add(menuBarRevealTimer!, forMode: .common)
        updateMenuBarRevealState()
    }

    private func transientBarHeightPath() -> String {
        NSHomeDirectory() + "/.config/hub/hub_bar_height_transient"
    }

    private func runBarSync(completion: (() -> Void)? = nil) {
        guard let hub = hubScriptPath() else {
            completion?()
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.launchPath = "/bin/sh"
            process.arguments = ["-c", "'\(hub)' bar-sync >/dev/null 2>&1"]
            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                // Best-effort sync; still let the UI continue if the helper failed to launch.
            }
            if let completion = completion {
                DispatchQueue.main.async(execute: completion)
            }
        }
    }

    private func removeTransientBarHeightOverride(sync: Bool, completion: (() -> Void)? = nil) {
        let path = transientBarHeightPath()
        let existed = FileManager.default.fileExists(atPath: path)
        try? FileManager.default.removeItem(atPath: path)
        if existed && sync {
            runBarSync(completion: completion)
        } else {
            completion?()
        }
    }

    private func updateTransientBarHeightOverride(completion: (() -> Void)? = nil) {
        let shouldOverride = HubBarWindow.isHubFullscreen()
            && windows.contains { $0.menuBarRevealedInFullscreen }
        guard shouldOverride else {
            removeTransientBarHeightOverride(sync: true, completion: completion)
            return
        }

        let rows = windows.map { max(1, $0.lastFitRows) }.max() ?? 1
        let revealInset = windows
            .filter { $0.menuBarRevealedInFullscreen }
            .map { window in
                HubBarWindow.menuBarRevealInset(
                    screen: window.barScreen,
                    sf: window.barScreen.frame,
                    vf: window.barScreen.visibleFrame)
            }
            .max() ?? 0
        let height = fullscreenTransientAerospaceMetric(rows: rows, menuBarRevealInset: revealInset)
        let path = transientBarHeightPath()
        let current = (try? String(contentsOfFile: path, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard current != "\(height)" else {
            completion?()
            return
        }

        try? "\(height)".write(toFile: path, atomically: true, encoding: .utf8)
        runBarSync(completion: completion)
    }

    private func applyMenuBarRevealGeometry(for window: HubBarWindow) {
        window.buildContents(state: lastState, lastRows: max(1, window.lastFitRows), writeBarMetrics: false)
        orderFrontUnlessNativeFullscreen(window)
    }

    private func applyRevealedMenuBarGeometry(generation: Int) {
        guard generation == menuBarRevealGeneration else { return }
        for w in windows where w.menuBarRevealedInFullscreen {
            applyMenuBarRevealGeometry(for: w)
        }
    }

    private func cgWindowBounds(_ info: [String: Any]) -> CGRect? {
        if let bounds = info[kCGWindowBounds as String] as? NSDictionary,
           let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary) {
            return rect
        }
        return nil
    }

    private func coversDisplayForNativeFullscreen(_ rect: CGRect, display: CGRect) -> Bool {
        let tolerance: CGFloat = 4
        let menuAllowance: CGFloat = max(40, NSStatusBar.system.thickness + 4)
        let leftAligned = abs(rect.minX - display.minX) <= tolerance
        let rightAligned = abs(rect.maxX - display.maxX) <= tolerance
        let bottomAligned = abs(rect.maxY - display.maxY) <= tolerance
        let topAtDisplay = abs(rect.minY - display.minY) <= tolerance
        let topBelowMenu = rect.minY >= display.minY - tolerance
            && rect.minY <= display.minY + menuAllowance
        return leftAligned && rightAligned && bottomAligned && (topAtDisplay || topBelowMenu)
    }

    private func visibleNativeFullscreenDisplayIDs() -> Set<CGDirectDisplayID> {
        var result = Set<CGDirectDisplayID>()
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]] else {
            return result
        }

        let ignoredOwners = Set(["borders", "hub_bar", "Dock", "Window Server", "Control Center"])
        for screen in NSScreen.screens {
            guard let did = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
                continue
            }

            let display = CGDisplayBounds(did)
            for info in list {
                guard let owner = info[kCGWindowOwnerName as String] as? String,
                      !ignoredOwners.contains(owner),
                      let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                      let bounds = cgWindowBounds(info) else { continue }

                if coversDisplayForNativeFullscreen(bounds, display: display) {
                    result.insert(did)
                    break
                }
            }
        }

        return result
    }

    private func isHiddenForNativeFullscreen(_ window: HubBarWindow) -> Bool {
        guard let did = window.barScreen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            return false
        }
        return nativeFullscreenDisplayIDs.contains(did)
    }

    private func orderFrontUnlessNativeFullscreen(_ window: HubBarWindow) {
        if isHiddenForNativeFullscreen(window) {
            window.orderOut(nil)
        } else {
            window.orderFrontRegardless()
        }
    }

    func updateVisibility() {
        nativeFullscreenDisplayIDs = visibleNativeFullscreenDisplayIDs()
        for w in windows {
            orderFrontUnlessNativeFullscreen(w)
        }
    }

    // In hub fullscreen mode, macOS reveals the menu bar when the cursor touches the top edge.
    // We can't reliably subscribe to a dedicated "menu bar revealed" event, so detect this
    // interaction directly from mouse position and temporarily drop the bar below the real menu
    // bar strip. NSScreen.contains excludes the max edge, so use explicit inclusive bounds here.
    private func updateMenuBarRevealState() {
        let hubFullscreen = HubBarWindow.isHubFullscreen()
        let mouse = NSEvent.mouseLocation
        let enterTopZone: CGFloat = 6.0

        var revealEntered = false
        var revealExited = false
        for w in windows {
            let sf = w.barScreen.frame
            let vf = w.barScreen.visibleFrame
            let mouseOnScreenX = mouse.x >= sf.minX && mouse.x <= sf.maxX
            let mouseOnScreenY = mouse.y >= sf.minY && mouse.y <= sf.maxY + 1
            let topDistance = sf.maxY - mouse.y
            let mouseOnScreen = mouseOnScreenX && mouseOnScreenY
            let revealInset = HubBarWindow.menuBarRevealInset(screen: w.barScreen, sf: sf, vf: vf)
            let exitTopZone = max(enterTopZone, revealInset + 8)
            let topZone = w.menuBarRevealedInFullscreen ? exitTopZone : enterTopZone
            let atTopEdge = mouseOnScreen && topDistance >= -1 && topDistance <= topZone
            let shouldReveal = hubFullscreen && atTopEdge
            if shouldReveal == w.menuBarRevealedInFullscreen { continue }

            w.menuBarRevealedInFullscreen = shouldReveal
            if shouldReveal {
                revealEntered = true
                w.applyWindowLevel(isFullscreen: hubFullscreen)
            } else {
                revealExited = true
                applyMenuBarRevealGeometry(for: w)
            }
        }

        if revealEntered || revealExited {
            menuBarRevealGeneration += 1
        }
        let generation = menuBarRevealGeneration

        if revealExited {
            updateTransientBarHeightOverride()
        }
        if revealEntered {
            updateTransientBarHeightOverride { [weak self] in
                self?.applyRevealedMenuBarGeometry(generation: generation)
            }
        }
    }

    func buildWindows() {
        windows.forEach { $0.close() }; windows.removeAll()
        DispatchQueue.global(qos: .userInitiated).async {
            let state = HubBarState.snapshot()
            let sortedScreens = NSScreen.screens.sorted { $0.frame.minX < $1.frame.minX }
            let monitorIDs = state.monitorWorkspaces.keys.sorted()
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.lastState = state
                for (i, screen) in sortedScreens.enumerated() {
                    let w = HubBarWindow(screen: screen)
                    w.monitorIndex = monitorIDs.indices.contains(i) ? monitorIDs[i] : (i + 1)
                    w.buildContents(state: state, lastRows: 1)
                    self.windows.append(w)
                }
                self.updateVisibility()
            }
        }
    }

    func installSignalSource() {
        signal(SIGUSR1, SIG_IGN)
        var debounce: DispatchWorkItem?
        let src = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
        src.setEventHandler { [weak self] in
            debounce?.cancel()
            let item = DispatchWorkItem { self?.refresh() }
            debounce = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.04, execute: item)
        }
        src.resume()
        objc_setAssociatedObject(self, "sigusr1src", src, .OBJC_ASSOCIATION_RETAIN)
    }

    func refresh() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let state = HubBarState.snapshot()
            DispatchQueue.main.async {
                guard let self = self else { return }
                let prevState = self.lastState
                self.lastState = state
                for w in self.windows {
                    // Re-run the fit decision with the new state to detect if rows/cap changed.
                    let sf = w.barScreen.frame
                    let isFullscreen = HubBarWindow.isHubFullscreen()
                    let notch = w.notchRange(isFullscreen: isFullscreen)
                    let monitorWs = state.monitorWorkspaces[w.monitorIndex]
                    let pills = state.visiblePillInfos(monitorWs: monitorWs)
                    let currentPillIDs = pills.map { $0.ws }

                    let newFit = decideFit(
                        pills: pills, screenW: sf.width,
                        notchMinX: notch?.minX, notchMaxX: notch?.maxX,
                        isFullscreen: isFullscreen, focused: state.focused,
                        claudeAlert: state.claudeAlert, claudeActive: state.claudeActive,
                        mode: state.layoutMode,
                        lastRows: w.lastFitRows)

                    let needsRebuild = refreshRequiresRebuild(
                        lastFitRows: w.lastFitRows,
                        lastFitCap: w.lastFitCap,
                        lastFitDecision: w.lastFitDecision,
                        lastVisiblePillIDs: w.lastVisiblePillIDs,
                        previousMode: prevState.layoutMode,
                        currentMode: state.layoutMode,
                        currentPillIDs: currentPillIDs,
                        existingPillIDs: Set(w.wsPills.keys),
                        newFit: newFit)

                    if ProcessInfo.processInfo.environment["HUB_BAR_DEBUG"] != nil {
                        let missingWs = pills.filter { w.wsPills[$0.ws] == nil }.map { $0.ws }
                        let visibleChanged = currentPillIDs != w.lastVisiblePillIDs
                        let structureChanged = !fitStructureMatchesForRefresh(w.lastFitDecision, newFit)
                        fputs("[DEBUG refresh] needsRebuild=\(needsRebuild) visibleChanged=\(visibleChanged) structureChanged=\(structureChanged) missingWs=\(missingWs) newCap=\(newFit.effectiveCap) lastCap=\(w.lastFitCap)\n", stderr)
                    }

                    if needsRebuild {
                        w.buildContents(state: state, lastRows: w.lastFitRows,
                                        writeBarMetrics: !w.menuBarRevealedInFullscreen)
                        self.orderFrontUnlessNativeFullscreen(w)
                        if w.menuBarRevealedInFullscreen {
                            self.updateTransientBarHeightOverride()
                        }
                    } else {
                        w.applyRefresh(state: state, fit: newFit)
                    }
                }
            }
        }
    }

    func startTimers() {
        clockTimer   = Timer.scheduledTimer(withTimeInterval: 10,  repeats: true) { [weak self] _ in
            self?.windows.forEach { $0.clusterOverlay?.updateClock() }
        }
        batteryTimer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in
            self?.windows.forEach { $0.clusterOverlay?.updateBattery() }
        }
        cpuMemTimer  = Timer.scheduledTimer(withTimeInterval: 3,   repeats: true) { [weak self] _ in
            self?.windows.forEach { $0.clusterOverlay?.updateCPU(); $0.clusterOverlay?.updateMem() }
        }
        staleClaudeTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            cleanupStaleClaudeActiveFlags()
        }
        nativeFullscreenTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateVisibility()
        }
        pulseTimer   = Timer.scheduledTimer(withTimeInterval: 0.75, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.pulseBright = !self.pulseBright
            let bright = self.pulseBright; let state = self.lastState
            for w in self.windows {
                for ws in state.claudeActive { if let pill = w.wsPills[ws] { pill.updatePulse(bright: bright) } }
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification,
            object: nil, queue: .main) { [weak self] _ in
                cleanupStaleClaudeActiveFlags()
                self?.windows.forEach { $0.clusterOverlay?.updateBattery() }
            }
        // Re-front bars when returning from a native full-screen Space.
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil, queue: .main) { [weak self] _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self?.updateVisibility() }
        }
        // Debounce screen parameter changes — Dock restart fires this notification multiple times
        // while geometry is still settling (e.g. during hub fullscreen toggle). Two rebuilds:
        // a quick one at 0.5s to pick up most changes, and a backstop at 3.0s to catch cases
        // where visibleFrame hasn't settled yet (e.g. menu-bar pref propagating after Dock restart).
        var screenDebounce: DispatchWorkItem?
        var screenBackstop: DispatchWorkItem?
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in
                screenDebounce?.cancel()
                screenBackstop?.cancel()
                let item = DispatchWorkItem { self?.buildWindows() }
                screenDebounce = item
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: item)
                let backstop = DispatchWorkItem { self?.buildWindows() }
                screenBackstop = backstop
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: backstop)
        }
    }
}

// ──────────────────────────────────────────────────────────────────────────────
// MARK: – Entry point
// ──────────────────────────────────────────────────────────────────────────────

class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = HubBarController()
    func applicationDidFinishLaunching(_ n: Notification) { controller.start() }
}

#if HUB_BAR_TEST
#else
// hub_bar_restart sends SIGUSR1 immediately after launch. Ignore it before the
// app publishes its PID so an early refresh cannot terminate a fresh process.
signal(SIGUSR1, SIG_IGN)

let pidFile = NSHomeDirectory() + "/.config/hub/hub_bar.pid"
if let existing = try? String(contentsOfFile: pidFile, encoding: .utf8),
   let existingPID = Int(existing.trimmingCharacters(in: .whitespacesAndNewlines)),
   existingPID != Int(ProcessInfo.processInfo.processIdentifier) {
    let alive = kill(pid_t(existingPID), 0) == 0
    if alive { fputs("hub_bar: another instance already running (pid \(existingPID))\n", stderr); exit(1) }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let delegate = AppDelegate()
app.delegate = delegate
app.run()
#endif
