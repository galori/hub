import Cocoa
import IOKit.ps
import CoreAudio

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
let PILL_IDX_IDLE:  UInt32 = 0xFF5A5D68
let PILL_NAME_IDLE: UInt32 = 0xFFAEB3BF
let PILL_IDX_ACT:   UInt32 = 0x73000000
let PILL_NAME_ACT:  UInt32 = 0xFF06201E

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
let pillH:           CGFloat = Theme.Metric.pillH
let pillRadius:      CGFloat = Theme.Radius.pill
let pillPadH:        CGFloat = Theme.Metric.pillPadH
let pillGap:         CGFloat = Theme.Metric.pillGap
let appIconSize:     CGFloat = Theme.Metric.appIconSize
let appGroupGap:     CGFloat = Theme.Metric.appGroupGap

// ── Fonts (via Theme for consistent fallback chain) ──
let monoFont11 = Theme.Font.mono(11)
let monoFont12 = Theme.Font.mono(12)
let monoFont13 = Theme.Font.mono(13)
let monoFont16 = Theme.Font.mono(16)
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
// MARK: – Aerospace runner
// ──────────────────────────────────────────────────────────────────────────────

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
    var repoPrefix: Bool = false
    var serviceMode: Bool = false
    var claudeAlert: Set<String> = []
    var claudeActive: Set<String> = []
    // Layout mode: shrink (default) = one row, binary-search label cap to fit.
    //              expand           = full labels, bar grows 1..FIT_MAX_ROWS rows.
    enum LayoutMode: String { case shrink, expand }
    var layoutMode: LayoutMode = .shrink
    // Visibility toggles (default hidden — "on" in the state file enables).
    var showLauncher: Bool = false
    var showWidgets: Bool = false

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

        // repo_prefix
        if let v = try? String(contentsOfFile: hub + "/repo_prefix", encoding: .utf8) {
            s.repoPrefix = v.trimmingCharacters(in: .whitespacesAndNewlines) == "on"
        }

        // Layout mode: shrink (default) | expand
        if let v = try? String(contentsOfFile: hub + "/layout_mode", encoding: .utf8),
           let m = LayoutMode(rawValue: v.trimmingCharacters(in: .whitespacesAndNewlines)) {
            s.layoutMode = m
        }
        // Visibility toggles (absent or "off" = hidden; "on" = visible)
        func readOn(_ name: String) -> Bool {
            (try? String(contentsOfFile: hub + "/" + name, encoding: .utf8))?
                .trimmingCharacters(in: .whitespacesAndNewlines) == "on"
        }
        s.showLauncher = readOn("show_launcher")
        s.showWidgets  = readOn("show_widgets")

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
        return (ws, cappedName(full: full, cap: cap, isFocused: ws == focused))
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

// Apply a label cap to a workspace name.
// cap == -1 → full name; cap == 0 → empty; cap > 0 → truncate non-focused names.
func cappedName(full: String, cap: Int, isFocused: Bool) -> String {
    if cap == 0 { return "" }
    if cap > 0, !isFocused, full.count > cap { return String(full.prefix(cap)) + "…" }
    return full
}

// Analytic pill width for a given (idx, name) pair — mirrors WorkspacePill layout constants.
// showDot adds 4(spacing)+6(dot) to the inner stack.
func analyticalPillWidth(idx: String, name: String, showDot: Bool) -> CGFloat {
    let idxFont = NSFontManager.shared.font(withFamily: "Hack Nerd Font", traits: .boldFontMask, weight: 9, size: 11)
                  ?? monoFont11
    var w = pillPadH * 2 + cachedTextWidth(idx, font: idxFont)
    if !name.isEmpty {
        w += 4 + cachedTextWidth(name, font: monoFont13)  // innerStack spacing=4
    }
    if showDot { w += 4 + 6 }  // spacing + dot width
    return ceil(w)
}

// Total strip width for a slice of pills at a given label cap.
func stripWidth(pills: [(ws: String, fullName: String, isFocused: Bool)],
                cap: Int, focused: String,
                claudeAlert: Set<String>, claudeActive: Set<String>) -> CGFloat {
    guard !pills.isEmpty else { return 0 }
    var total: CGFloat = 0
    for (i, p) in pills.enumerated() {
        if i > 0 { total += pillGap }
        let effCap = (cap == -1 || p.isFocused) ? -1 : cap
        let name = cappedName(full: p.fullName, cap: effCap, isFocused: p.isFocused)
        let showDot = claudeAlert.contains(p.ws) || claudeActive.contains(p.ws)
        total += analyticalPillWidth(idx: p.ws, name: name, showDot: showDot)
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
}

let FIT_MAX_ROWS = 4

// Greedy packing of pills into rows given row widths.
// Row 0 may have restricted capacity (notch / cluster); rows 1+ are full-width.
// Returns (rowAssignment, overflowed). overflowed=true means content didn't fit in maxRows.
private func greedyPack(pills: [(ws: String, fullName: String, isFocused: Bool)],
                        cap: Int, focused: String,
                        claudeAlert: Set<String>, claudeActive: Set<String>,
                        row0Width: CGFloat, fullRowWidth: CGFloat,
                        maxRows: Int) -> (assignment: [[Int]], overflowed: Bool) {
    var rows: [[Int]] = Array(repeating: [], count: maxRows)
    let rowWidths = [row0Width] + Array(repeating: fullRowWidth, count: maxRows - 1)
    var used: [CGFloat] = Array(repeating: 0, count: maxRows)
    var r = 0
    var overflowed = false

    for (i, p) in pills.enumerated() {
        let effCap = (cap == -1 || p.isFocused) ? -1 : cap
        let name = cappedName(full: p.fullName, cap: effCap, isFocused: p.isFocused)
        let showDot = claudeAlert.contains(p.ws) || claudeActive.contains(p.ws)
        let pw = analyticalPillWidth(idx: p.ws, name: name, showDot: showDot)
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

// Pure fit decision: given pill data, screen geometry, and layout mode — returns layout.
// `lastRows` is the only retained state (hysteresis for expand mode). Pass 1 on first call.
// Modes:
//   .shrink (default) — always 1 row; binary-search the largest label cap that fits.
//   .expand           — full labels (-1); grow 1..FIT_MAX_ROWS until pills fit (with hysteresis).
func decideFit(pills: [(ws: String, fullName: String, isFocused: Bool)],
               screenW: CGFloat, clusterW: CGFloat,
               notchMinX: CGFloat?,
               isFullscreen: Bool, focused: String,
               claudeAlert: Set<String>, claudeActive: Set<String>,
               mode: HubBarState.LayoutMode,
               lastRows: Int) -> FitDecision {

    let leadingInset: CGFloat = 8
    let trailingInset: CGFloat = 8
    let clusterGap: CGFloat = 4

    // Row 0 right edge: notch is a HARD WALL — pills never straddle it.
    // If fullscreen+notch, row 0 ends at the notch; overflow drops to a full-width row below.
    // The right-of-notch sliver is intentionally left empty on row 0.
    let row0RightEdge: CGFloat
    if isFullscreen, let nMin = notchMinX {
        row0RightEdge = nMin - 2  // 2px clearance from notch edge
    } else {
        row0RightEdge = screenW - clusterW - clusterGap - trailingInset
    }
    let row0W = row0RightEdge - leadingInset
    let fullRowW = screenW - leadingInset - trailingInset

    switch mode {
    case .shrink:
        // Always 1 row. Binary-search the largest cap (0..60) that packs everything into row 0.
        let maxCap = 60
        var lo = 0, hi = maxCap
        var bestCap = 0
        var bestAssignment: [[Int]] = [Array(0..<pills.count)]
        while lo <= hi {
            let mid = (lo + hi) / 2
            let (assignment, overflowed) = greedyPack(
                pills: pills, cap: mid, focused: focused,
                claudeAlert: claudeAlert, claudeActive: claudeActive,
                row0Width: row0W, fullRowWidth: fullRowW, maxRows: 1)
            if !overflowed { bestCap = mid; bestAssignment = assignment; lo = mid + 1 }
            else { hi = mid - 1 }
        }
        return FitDecision(rows: 1, rowAssignment: bestAssignment, effectiveCap: bestCap)

    case .expand:
        // Full labels (cap = -1). Grow rows 1..FIT_MAX_ROWS until it fits; apply hysteresis.
        let cap = -1
        for r in 1...FIT_MAX_ROWS {
            let (_, overflowed) = greedyPack(
                pills: pills, cap: cap, focused: focused,
                claudeAlert: claudeAlert, claudeActive: claudeActive,
                row0Width: row0W, fullRowWidth: fullRowW, maxRows: r)
            if !overflowed {
                let effectiveRows: Int
                if r < lastRows {
                    let (_, stillOverflows) = greedyPack(
                        pills: pills, cap: cap, focused: focused,
                        claudeAlert: claudeAlert, claudeActive: claudeActive,
                        row0Width: row0W, fullRowWidth: fullRowW, maxRows: lastRows - 1)
                    effectiveRows = stillOverflows ? lastRows : r
                } else { effectiveRows = r }
                let (finalAssignment, _) = greedyPack(
                    pills: pills, cap: cap, focused: focused,
                    claudeAlert: claudeAlert, claudeActive: claudeActive,
                    row0Width: row0W, fullRowWidth: fullRowW, maxRows: effectiveRows)
                return FitDecision(rows: effectiveRows, rowAssignment: finalAssignment, effectiveCap: cap)
            }
        }
        // Still overflows at FIT_MAX_ROWS: park overflow in the last row (ellipsized by per-pill maxwidth).
        let (asgn, _) = greedyPack(
            pills: pills, cap: cap, focused: focused,
            claudeAlert: claudeAlert, claudeActive: claudeActive,
            row0Width: row0W, fullRowWidth: fullRowW, maxRows: FIT_MAX_ROWS)
        return FitDecision(rows: FIT_MAX_ROWS, rowAssignment: asgn, effectiveCap: cap)
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

    // Inner rounded-rect view (masked) — holds the visible content
    private let innerView = NSView()
    private let idxField  = NSTextField(labelWithString: "")
    private let nameField = NSTextField(labelWithString: "")
    let dotView = NSView()
    private let innerStack = NSStackView()
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
        // available room and analyticalPillWidth (which measures full text) matches what renders.
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

        NSLayoutConstraint.activate([
            innerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            innerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            innerView.topAnchor.constraint(equalTo: topAnchor),
            innerView.bottomAnchor.constraint(equalTo: bottomAnchor),

            innerStack.centerYAnchor.constraint(equalTo: innerView.centerYAnchor),
            innerStack.leadingAnchor.constraint(equalTo: innerView.leadingAnchor, constant: pillPadH),
            innerStack.trailingAnchor.constraint(equalTo: innerView.trailingAnchor, constant: -pillPadH),

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

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackArea { removeTrackingArea(t) }
        trackArea = NSTrackingArea(rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(trackArea!)
    }
    override func mouseEntered(with event: NSEvent) {
        guard !isFocused else { return }
        innerView.layer?.backgroundColor = NSColor(argb: HOVER_BG).cgColor
    }
    override func mouseExited(with event: NSEvent) {
        innerView.layer?.backgroundColor = baseBG
    }

    func apply(bg: UInt32, idxColor: UInt32, nameColor: UInt32,
               idx: String, name: String,
               showDot: Bool, dotColor: UInt32,
               glowColor: UInt32?, glowRadius: CGFloat) {
        baseBG = NSColor(argb: bg).cgColor
        innerView.layer?.backgroundColor = baseBG
        idxField.stringValue = idx
        idxField.textColor = NSColor(argb: idxColor)
        nameField.stringValue = name
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

    // Pill views keyed by ws id
    var wsPills: [String: WorkspacePill] = [:]
    var appSlots:   [AppSlotView]   = []
    var wsWinSlots: [WsWinSlotView] = []
    var volPopup: VolumePopupWindow?

    // Widget label refs for updates
    var clockLabel: NSTextField?
    var battLabel:  NSTextField?
    var battIcon:   NSTextField?
    var volLabel:   NSTextField?
    var volIcon:    NSTextField?
    var serviceModeLabel: NSView?

    // Last fit decision, for applyRefresh change-detection
    var lastFitRows: Int = 0
    var lastFitCap: Int = -2  // sentinel "unknown"

    // In hub fullscreen mode the macOS menu bar is hidden (auto-hide), but visibleFrame still
    // reserves a ~32px inset for the auto-hide trigger zone. Use the absolute screen top instead.
    static func barTopY(sf: NSRect, vf: NSRect) -> CGFloat {
        let home = NSHomeDirectory()
        let isFullscreen = FileManager.default.fileExists(atPath: home + "/.config/hub/fullscreen")
        return isFullscreen ? sf.maxY : vf.maxY
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
        let vf = screen.visibleFrame
        let topY = HubBarWindow.barTopY(sf: sf, vf: vf)
        let r = NSRect(x: sf.minX, y: topY - barHeightNormal, width: sf.width, height: barHeightNormal)
        super.init(contentRect: r, styleMask: .borderless, backing: .buffered, defer: false)
        // Level 20 = Dock level. Notification banners (level 21) render above this, so they're
        // never obscured by the Hub Bar. Normal app windows are at level 0 so the bar still floats above them.
        level = NSWindow.Level(rawValue: 20)
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        ignoresMouseEvents = false
        isReleasedWhenClosed = false  // ARC owns lifetime; prevent double-free on close()
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
    }

    // Analytic cluster width estimate used by decideFit before the view is built.
    // Must mirror buildCluster exactly — every gate here must match a gate there.
    func analyticalClusterWidth(state: HubBarState) -> CGFloat {
        var w: CGFloat = 8 + 8  // leading cluster gap + trailing inset

        // Service pill (30px) — independent of show_launcher/show_widgets
        if state.serviceMode { w += 30 + 6 }

        // App icon group — only when showLauncher is on and apps are configured
        if state.showLauncher && !state.apps.isEmpty {
            let iconCount = state.apps.count
            // 14px inset each side + appIconSize per icon + appGroupGap between
            w += 14 * 2 + CGFloat(iconCount) * (appIconSize + 4) + CGFloat(max(0, iconCount - 1)) * appGroupGap + 6
        }

        // Layout mode icon — only visible in expand mode
        if state.layoutMode == .expand { w += 20 + 6 }

        // Spacer + volume + battery + clock — only when showWidgets is on
        if state.showWidgets {
            w += 4 + 6  // spacer

            // Volume: icon + "100%" label
            w += cachedTextWidth("\u{F057E}", font: nerdFont16) + 4 + cachedTextWidth("100%", font: monoFont12) + 6

            // Battery: icon + "100%" label
            w += cachedTextWidth("\u{F0079}", font: nerdFont16) + 4 + cachedTextWidth("100%", font: monoFont12) + 6

            // Clock pill: 10+6+dot(6)+6+label+10 = ~32 + label
            let clockLabel = "Mon 22 Jun  00:00"
            w += 10 + 6 + 6 + 6 + cachedTextWidth(clockLabel, font: monoFont12) + 10
        }

        return ceil(w)
    }

    func buildContents(state: HubBarState, lastRows: Int = 1) {
        let cv = contentView!
        cv.subviews.forEach { $0.removeFromSuperview() }
        wsPills.removeAll(); appSlots.removeAll(); wsWinSlots.removeAll(); volPopup = nil
        clockLabel = nil; battLabel = nil; battIcon = nil; volLabel = nil; volIcon = nil
        serviceModeLabel = nil

        let sf = barScreen.frame
        let vf = barScreen.visibleFrame
        let topY = HubBarWindow.barTopY(sf: sf, vf: vf)
        let isFullscreen = topY >= sf.maxY

        // ── Determine fit decision ──────────────────────────────────────────
        // Measure cluster width analytically before building the view.
        // fittingSize on an unparented view returns 0, so we compute it from
        // the known widget widths: clock pill ~110, volume ~55, battery ~50,
        // app icons, mode icon, service pill, spacing.
        let clusterW = analyticalClusterWidth(state: state)

        let monitorWs = state.monitorWorkspaces[monitorIndex]
        let pills = state.visiblePillInfos(monitorWs: monitorWs)

        let notch = notchRange(isFullscreen: isFullscreen)
        let fit = decideFit(
            pills: pills, screenW: sf.width, clusterW: clusterW,
            notchMinX: notch?.minX,
            isFullscreen: isFullscreen, focused: state.focused,
            claudeAlert: state.claudeAlert, claudeActive: state.claudeActive,
            mode: state.layoutMode,
            lastRows: lastRows)

        lastFitRows = fit.rows
        lastFitCap  = fit.effectiveCap

        // ── Resize window to match row count ───────────────────────────────
        let barH = barHeightNormal * CGFloat(fit.rows)
        setFrame(NSRect(x: sf.minX, y: topY - barH, width: sf.width, height: barH), display: true)

        // Write bar height for bar-sync (primary screen only to avoid multi-monitor flapping)
        let isPrimary = barScreen == NSScreen.screens.first
        if isPrimary {
            let menuInset = topY >= sf.maxY ? 0 : Int(sf.maxY - vf.maxY)
            let home = NSHomeDirectory()
            try? "\(Int(barH))".write(toFile: home + "/.config/hub/hub_bar_height", atomically: true, encoding: .utf8)
            try? "\(Int(barH) + menuInset)".write(toFile: home + "/.config/hub/hub_bar_outer_top", atomically: true, encoding: .utf8)
            if let hub = hubScriptPath() {
                Process.launchedProcess(launchPath: "/bin/sh",
                    arguments: ["-c", "'\(hub)' bar-sync >/dev/null 2>&1 &"])
            }
        }

        // ── Background ─────────────────────────────────────────────────────
        let bg = HubBarBackgroundView(frame: cv.bounds)
        bg.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(bg)
        NSLayoutConstraint.activate([
            bg.leadingAnchor.constraint(equalTo: cv.leadingAnchor),
            bg.trailingAnchor.constraint(equalTo: cv.trailingAnchor),
            bg.topAnchor.constraint(equalTo: cv.topAnchor),
            bg.bottomAnchor.constraint(equalTo: cv.bottomAnchor),
        ])

        // ── Build cluster view (now that we know the layout) ────────────────
        let clusterView = buildCluster(state: state)
        clusterView.translatesAutoresizingMaskIntoConstraints = false

        // ── Build layout ────────────────────────────────────────────────────
        buildRowLayout(cv: cv, state: state, fit: fit,
                       clusterView: clusterView,
                       notch: notch, isFullscreen: isFullscreen, pills: pills)
    }

    // ── Multi-row layout ─────────────────────────────────────────────────────

    func buildRowLayout(cv: NSView, state: HubBarState, fit: FitDecision,
                        clusterView: NSView, notch: (minX: CGFloat, maxX: CGFloat)?,
                        isFullscreen: Bool, pills: [(ws: String, fullName: String, isFocused: Bool)]) {
        let rows = fit.rows
        let rowH = barHeightNormal

        // Add the already-built cluster to top row, right-aligned
        cv.addSubview(clusterView)
        NSLayoutConstraint.activate([
            clusterView.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -8),
            clusterView.centerYAnchor.constraint(equalTo: cv.topAnchor, constant: rowH / 2),
        ])

        // Notch is a hard wall: row 0 ends at notchMinX (left segment only).
        // Pills never straddle the notch; the right-of-notch sliver is dead space on row 0.
        let notchWallX: CGFloat? = isFullscreen ? notch?.minX : nil

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
                // Top row: pills end at the notch (if present) or the cluster left edge.
                buildTopRowPills(cv: cv, state: state, fit: fit,
                                 pills: rowPills, centerY: rowCenterY,
                                 clusterView: clusterView, notchWallX: notchWallX)
            } else {
                // Full-width rows below the notch — no cluster, full width.
                buildFullRow(cv: cv, state: state, fit: fit,
                             pills: rowPills, centerY: rowCenterY)
            }
        }
    }

    // Top row: pills in a clip view that stops at the notch wall (fullscreen) or the cluster.
    // One unified function — no split packer, no right-of-notch stack.
    private func buildTopRowPills(cv: NSView, state: HubBarState, fit: FitDecision,
                                  pills: [(ws: String, fullName: String, isFocused: Bool)],
                                  centerY: CGFloat, clusterView: NSView,
                                  notchWallX: CGFloat?) {
        let clipView = NSView()
        clipView.wantsLayer = true; clipView.layer?.masksToBounds = true
        clipView.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(clipView)  // added BEFORE cluster so cluster paints on top

        // Right edge: notch wall if present (leaves dead space right of notch on row 0),
        // otherwise the cluster left edge (safety net clip).
        NSLayoutConstraint.activate([
            clipView.leadingAnchor.constraint(equalTo: cv.leadingAnchor),
            clipView.topAnchor.constraint(equalTo: cv.topAnchor),
            clipView.heightAnchor.constraint(equalToConstant: barHeightNormal),
        ])
        if let wall = notchWallX {
            clipView.trailingAnchor.constraint(equalTo: cv.leadingAnchor, constant: wall - 2).isActive = true
        } else {
            clipView.trailingAnchor.constraint(equalTo: clusterView.leadingAnchor, constant: -4).isActive = true
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
                wsPills[p.ws] = newPill
                return newPill
            }()
            stack.addArrangedSubview(pill)
        }
        applyWorkspaceState(state: state, cap: fit.effectiveCap)
    }

    // ── Workspace strip ──────────────────────────────────────────────────────

    func applyWorkspaceState(state: HubBarState, cap: Int) {
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

            let (idxStr, nameStr) = state.spansFor(ws: ws, cap: cap)

            if isFocused {
                pill.apply(bg: ACCENT, idxColor: PILL_IDX_ACT, nameColor: PILL_NAME_ACT,
                           idx: idxStr, name: nameStr, showDot: showDot, dotColor: focusedDotColor,
                           glowColor: ACCENT, glowRadius: 8)
                pill.isHidden = false
            } else if isActive {
                pill.apply(bg: PILL_IDLE_BG, idxColor: PILL_IDX_IDLE, nameColor: PILL_NAME_IDLE,
                           idx: idxStr, name: nameStr, showDot: showDot, dotColor: dotColor,
                           glowColor: showDot ? dotColor : nil, glowRadius: 5)
                pill.isHidden = false
            } else if isLabeled {
                pill.apply(bg: PILL_IDLE_BG, idxColor: PILL_IDX_IDLE, nameColor: 0x55FFFFFF,
                           idx: idxStr, name: nameStr, showDot: showDot, dotColor: dotColor,
                           glowColor: showDot ? dotColor : nil, glowRadius: 5)
                pill.isHidden = false
            } else {
                pill.isHidden = true
            }
        }
    }

    // ── Cluster (right-side widgets) ─────────────────────────────────────────

    func buildCluster(state: HubBarState) -> NSView {
        // The cluster is an opaque view so it occludes pills sliding under it.
        let cluster = NSView()
        cluster.wantsLayer = true
        cluster.layer?.backgroundColor = NSColor(argb: CLUSTER_BG).cgColor
        cluster.setContentHuggingPriority(.required, for: .horizontal)
        cluster.setContentCompressionResistancePriority(.required, for: .horizontal)

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        cluster.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: cluster.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: cluster.trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: cluster.centerYAnchor),
            cluster.heightAnchor.constraint(equalToConstant: pillH + 4),
        ])

        // Service mode indicator — always built so applyRefresh can show/hide it
        let pill = makeServicePill()
        pill.translatesAutoresizingMaskIntoConstraints = false
        pill.isHidden = !state.serviceMode
        serviceModeLabel = pill
        stack.addArrangedSubview(pill)

        // App icon group — only when showLauncher is on and apps are configured
        if state.showLauncher && !state.apps.isEmpty {
            let group = buildAppIconGroup(state: state)
            group.translatesAutoresizingMaskIntoConstraints = false
            stack.addArrangedSubview(group)
        }

        // Layout mode icon — only in expand mode; click returns to shrink
        if state.layoutMode == .expand {
            let modeIcon = buildLayoutModeIcon(state: state)
            modeIcon.translatesAutoresizingMaskIntoConstraints = false
            stack.addArrangedSubview(modeIcon)
        }

        // Spacer + volume + battery + clock — only when showWidgets is on
        if state.showWidgets {
            stack.addArrangedSubview(makeHSpacer(4))
            buildVolume(into: stack)
            buildBattery(into: stack)
            buildClock(into: stack)
        }

        return cluster
    }

    // ── Click-wrap helper ────────────────────────────────────────────────────
    // Wraps a content view with an invisible HubBarClickView overlay of the same size.
    // Used by buildLayoutModeIcon, buildVolume, buildBattery.

    @discardableResult
    func wrapWithClick(content: NSView, click: HubBarClickView) -> NSView {
        let wrap = NSView()
        wrap.translatesAutoresizingMaskIntoConstraints = false
        content.translatesAutoresizingMaskIntoConstraints = false
        click.translatesAutoresizingMaskIntoConstraints = false
        wrap.addSubview(content); wrap.addSubview(click)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: wrap.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: wrap.trailingAnchor),
            content.topAnchor.constraint(equalTo: wrap.topAnchor),
            content.bottomAnchor.constraint(equalTo: wrap.bottomAnchor),
            click.leadingAnchor.constraint(equalTo: wrap.leadingAnchor),
            click.trailingAnchor.constraint(equalTo: wrap.trailingAnchor),
            click.topAnchor.constraint(equalTo: wrap.topAnchor),
            click.bottomAnchor.constraint(equalTo: wrap.bottomAnchor),
        ])
        return wrap
    }

    // ── Layout mode icon ─────────────────────────────────────────────────────
    // Only rendered in expand mode. Shows nf-fa-compress (⇔ compact) glyph in orange;
    // clicking it returns the bar to shrink mode.

    func buildLayoutModeIcon(state: HubBarState) -> NSView {
        // nf-fa-compress U+F066: "click to compact/shrink back"
        let icon = NSTextField(labelWithString: "\u{F066}")
        icon.font = nerdFont13
        icon.textColor = NSColor(argb: C_ORANGE)
        icon.isEditable = false; icon.isBordered = false; icon.backgroundColor = .clear

        let click = HubBarClickView(frame: .zero)
        click.onPress = {
            guard let hub = hubScriptPath() else { return }
            Process.launchedProcess(launchPath: "/bin/sh",
                arguments: ["-c", "'\(hub)' bar-layout shrink >/dev/null 2>&1 &"])
        }
        return wrapWithClick(content: icon, click: click)
    }

    // ── App icon group ───────────────────────────────────────────────────────

    func buildAppIconGroup(state: HubBarState) -> NSView {
        let group = NSView()
        group.wantsLayer = true
        group.layer?.backgroundColor = NSColor(argb: APPGRP_BG).cgColor
        group.layer?.cornerRadius = APPGRP_RADIUS
        group.layer?.masksToBounds = true
        group.layer?.borderWidth = 1
        group.layer?.borderColor = NSColor(argb: APPGRP_BORDER).cgColor
        group.setContentHuggingPriority(.required, for: .horizontal)

        let inner = NSStackView()
        inner.orientation = .horizontal
        inner.spacing = appGroupGap
        inner.alignment = .centerY
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

        // Configured app slots
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

        // Extra workspace windows not in the launcher
        var seen = Set<String>()
        var extraApps: [(app: String, ids: [Int])] = []
        for win in state.currentWindows {
            let app = win.app
            if isSystemProc(app) || launcherNames.contains(app) { continue }
            if seen.contains(app) {
                if let idx = extraApps.firstIndex(where: { $0.app == app }) {
                    extraApps[idx].ids.append(win.id)
                }
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

    // ── Bare widget helpers ──────────────────────────────────────────────────

    func makeBareIconLabel(icon: String, iconColor: UInt32) -> (stack: NSStackView, iconField: NSTextField, label: NSTextField) {
        let stack = NSStackView()
        stack.orientation = .horizontal; stack.spacing = 4; stack.alignment = .centerY
        let ic = NSTextField(labelWithString: icon)
        ic.font = nerdFont16; ic.textColor = NSColor(argb: iconColor)
        ic.isEditable = false; ic.isBordered = false; ic.backgroundColor = .clear
        let lbl = NSTextField(labelWithString: "")
        lbl.font = monoFont12; lbl.textColor = NSColor(argb: 0xFFC9CDD6)
        lbl.isEditable = false; lbl.isBordered = false; lbl.backgroundColor = .clear
        stack.addArrangedSubview(ic); stack.addArrangedSubview(lbl)
        return (stack, ic, lbl)
    }

    func buildVolume(into stack: NSStackView) {
        let (ws, ic, lbl) = makeBareIconLabel(icon: "󰕾", iconColor: C_BLUE)
        volIcon = ic; volLabel = lbl
        let click = HubBarClickView(frame: .zero)
        click.onPress = { [weak self] in self?.toggleVolumePopup() }
        stack.addArrangedSubview(wrapWithClick(content: ws, click: click))
        updateVolume()

        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, DispatchQueue.main) { [weak self] _, _ in
            self?.updateVolume()
        }
    }

    func buildBattery(into stack: NSStackView) {
        let (ws, ic, lbl) = makeBareIconLabel(icon: "󰁹", iconColor: C_GREEN)
        battIcon = ic; battLabel = lbl
        let click = HubBarClickView(frame: .zero)
        click.onPress = { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.battery")!) }
        stack.addArrangedSubview(wrapWithClick(content: ws, click: click))
        updateBattery()
    }

    func buildClock(into stack: NSStackView) {
        // Accent-soft pill: teal dot + monospace time
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
        lbl.font = monoFont12
        lbl.textColor = NSColor(argb: 0xFFE8EAF0)
        lbl.isEditable = false; lbl.isBordered = false; lbl.backgroundColor = .clear
        clockLabel = lbl

        inner.addArrangedSubview(dot)
        inner.addArrangedSubview(lbl)

        pill.addSubview(inner)
        NSLayoutConstraint.activate([
            inner.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 10),
            inner.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -10),
            inner.centerYAnchor.constraint(equalTo: pill.centerYAnchor),
            pill.heightAnchor.constraint(equalToConstant: pillH),
        ])

        pill.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(pill)
        updateClock()
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

    func makeHSpacer(_ width: CGFloat) -> NSView {
        let v = NSView(); v.translatesAutoresizingMaskIntoConstraints = false
        v.widthAnchor.constraint(equalToConstant: width).isActive = true
        return v
    }

    // ── Periodic update methods ──────────────────────────────────────────────

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
            case 90...100: return ("󰁹", C_GREEN)
            case 70...89:  return ("󰂀", C_GREEN)
            case 50...69:  return ("󰁾", C_GREEN)
            case 30...49:  return ("󰁼", C_ORANGE)
            case 10...29:  return ("󰁺", C_RED)
            default:       return ("󰂃", C_RED)
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
        var muted: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        var muteAddr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyData(deviceID, &muteAddr, 0, nil, &size, &muted)
        var vol: Float32 = 0
        size = UInt32(MemoryLayout<Float32>.size)
        var volAddr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyData(deviceID, &volAddr, 0, nil, &size, &vol)
        let pct = Int(vol * 100)
        if muted != 0 {
            volIcon?.stringValue = "󰖁"
        } else {
            switch pct {
            case 60...100: volIcon?.stringValue = "󰕾"
            case 30...59:  volIcon?.stringValue = "󰖀"
            case 1...29:   volIcon?.stringValue = "󰕿"
            default:       volIcon?.stringValue = "󰖁"
            }
        }
        volLabel?.stringValue = "\(pct)%"
    }

    func applyRefresh(state: HubBarState, newRows: Int, newCap: Int) {
        applyWorkspaceState(state: state, cap: newCap)
        updateClock(); updateBattery(); updateVolume()   // safe no-ops if widgets hidden
        serviceModeLabel?.isHidden = !state.serviceMode
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

        let target = VolumeSliderTarget(deviceID: deviceID) { [weak self] in self?.updateVolume() }
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
            self?.updateVolume()
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
    var pulseBright = true; var lastState = HubBarState()

    func start() { writePIDFile(); buildWindows(); installSignalSource(); startTimers() }

    func writePIDFile() {
        let path = NSHomeDirectory() + "/.config/hub/hub_bar.pid"
        try? "\(ProcessInfo.processInfo.processIdentifier)\n".write(toFile: path, atomically: true, encoding: .utf8)
    }

    // Returns display IDs of screens where a native macOS full-screen app covers the entire frame.
    // Layer-0 windows that span screen.frame exactly are full-screen app windows; normal app windows
    // can't extend into the menu-bar area, so only true full-screen apps satisfy this check.
    private func fullScreenDisplayIDs() -> Set<CGDirectDisplayID> {
        var result = Set<CGDirectDisplayID>()
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]] else { return result }
        let mainH = NSScreen.screens.first?.frame.height ?? 0
        for screen in NSScreen.screens {
            let sf = screen.frame
            for info in list {
                guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                      let b = info[kCGWindowBounds as String] as? [String: CGFloat] else { continue }
                // CGWindowList uses flipped coords (Y=0 at top of main screen); convert to NSScreen space.
                let cgY = b["Y"] ?? 0, cgH = b["Height"] ?? 0
                let win = CGRect(x: b["X"] ?? 0, y: mainH - cgY - cgH,
                                 width: b["Width"] ?? 0, height: cgH)
                if win.contains(sf) {
                    if let did = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID {
                        result.insert(did)
                    }
                    break
                }
            }
        }
        return result
    }

    func updateVisibility() {
        let fullScreenIDs = fullScreenDisplayIDs()
        for w in windows {
            let did = w.barScreen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
            if let did = did, fullScreenIDs.contains(did) {
                w.orderOut(nil)
            } else {
                w.orderFrontRegardless()
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
                    let vf = w.barScreen.visibleFrame
                    let topY = HubBarWindow.barTopY(sf: sf, vf: vf)
                    let isFullscreen = topY >= sf.maxY
                    let notch = w.notchRange(isFullscreen: isFullscreen)
                    let monitorWs = state.monitorWorkspaces[w.monitorIndex]
                    let pills = state.visiblePillInfos(monitorWs: monitorWs)

                    let newFit = decideFit(
                        pills: pills, screenW: sf.width, clusterW: w.analyticalClusterWidth(state: state),
                        notchMinX: notch?.minX,
                        isFullscreen: isFullscreen, focused: state.focused,
                        claudeAlert: state.claudeAlert, claudeActive: state.claudeActive,
                        mode: state.layoutMode,
                        lastRows: w.lastFitRows)

                    let rowsChanged = newFit.rows != w.lastFitRows
                    let capChanged  = newFit.effectiveCap != w.lastFitCap
                    let modeChanged = state.layoutMode != prevState.layoutMode
                    let visChanged  = state.showLauncher != prevState.showLauncher
                                   || state.showWidgets  != prevState.showWidgets
                    let appsChanged = state.showLauncher && state.apps.count != prevState.apps.count
                    // Detect new workspaces whose pill view hasn't been created yet
                    let newPillMissing = pills.contains { w.wsPills[$0.ws] == nil }

                    if rowsChanged || capChanged || modeChanged || visChanged || appsChanged || newPillMissing {
                        w.buildContents(state: state, lastRows: w.lastFitRows)
                        w.orderFrontRegardless()
                    } else {
                        w.applyRefresh(state: state, newRows: newFit.rows, newCap: newFit.effectiveCap)
                    }
                }
            }
        }
    }

    func startTimers() {
        clockTimer   = Timer.scheduledTimer(withTimeInterval: 10,  repeats: true) { [weak self] _ in self?.windows.forEach { $0.updateClock() } }
        batteryTimer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in self?.windows.forEach { $0.updateBattery() } }
        pulseTimer   = Timer.scheduledTimer(withTimeInterval: 0.75, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.pulseBright = !self.pulseBright
            let bright = self.pulseBright; let state = self.lastState
            for w in self.windows {
                for ws in state.claudeActive { if let pill = w.wsPills[ws] { pill.updatePulse(bright: bright) } }
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification,
            object: nil, queue: .main) { [weak self] _ in self?.windows.forEach { $0.updateBattery() } }
        // Show/hide bars when a full-screen transition creates/destroys a space.
        // Delay slightly to let the new Space fully settle before querying window list.
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

let pidFile = NSHomeDirectory() + "/.config/hub/hub_bar.pid"
if let existing = try? String(contentsOfFile: pidFile, encoding: .utf8),
   let existingPID = Int(existing.trimmingCharacters(in: .whitespacesAndNewlines)),
   existingPID != Int(ProcessInfo.processInfo.processIdentifier) {
    let alive = kill(pid_t(existingPID), 0) == 0
    if alive { fputs("hub_bar: another instance already running (pid \(existingPID))\n", stderr); exit(1) }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = HubBarController()
    func applicationDidFinishLaunching(_ n: Notification) { controller.start() }
}

let delegate = AppDelegate()
app.delegate = delegate
app.run()
