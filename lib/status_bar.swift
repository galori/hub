import Cocoa
import IOKit.ps
import CoreWLAN
import CoreAudio

// Single-file native Swift status bar for hub.
// Replaces sketchybar: reads state files + aerospace queries on SIGUSR1, re-renders all views.
// PID written to ~/.config/hub/status_bar.pid; hub bar-refresh sends SIGUSR1.

// ──────────────────────────────────────────────────────────────────────────────
// MARK: – Theme / Geometry
// ──────────────────────────────────────────────────────────────────────────────

extension NSColor {
    // 0xAARRGGBB
    convenience init(argb: UInt32) {
        let a = CGFloat((argb >> 24) & 0xff) / 255
        let r = CGFloat((argb >> 16) & 0xff) / 255
        let g = CGFloat((argb >>  8) & 0xff) / 255
        let b = CGFloat( argb        & 0xff) / 255
        self.init(srgbRed: r, green: g, blue: b, alpha: a)
    }
}

func luminance(argb: UInt32) -> Int {
    let r = Int((argb >> 16) & 0xff)
    let g = Int((argb >>  8) & 0xff)
    let b = Int( argb        & 0xff)
    return (r * 299 + g * 587 + b * 114) / 1000
}

let BAR_COLOR:    UInt32 = 0xf02c2e34
let ITEM_BG:      UInt32 = 0xff363944
let ITEM_BG2:     UInt32 = 0xff414550
let C_WHITE:      UInt32 = 0xffe2e2e3
let C_RED:        UInt32 = 0xfffc5d7c
let C_GREEN:      UInt32 = 0xff9ed072
let C_BLUE:       UInt32 = 0xff76cce0
let C_YELLOW:     UInt32 = 0xffe7c664
let C_ORANGE:     UInt32 = 0xfff39660
let C_GREY:       UInt32 = 0xff7f8490
let INACTIVE_BG:  UInt32 = 0x40363944
let EMPTY_LABELED_BG: UInt32 = 0x20363944
let HOVER_BG:     UInt32 = 0x33ffffff
let CLICK_BG:     UInt32 = 0xff76cce0

let SLOT_COLORS: [UInt32] = [
    0xff1A73E8, 0xffFF7043, 0xff8E76D1, 0xff00C853, 0xffEC407A,
    0xff00D1FF, 0xffF9A825, 0xff5C6BC0, 0xffEF5350, 0xff26C6DA,
    0xffAEEA00, 0xff7E57C2, 0xfff39660, 0xff00A396, 0xffFFCA28,
    0xffAB47BC, 0xff66BB6A, 0xffE05297, 0xff42A5F5, 0xff8D6E63,
    0xff9CCC65, 0xffC62828, 0xff78909C, 0xffD4E157, 0xff4527A0,
    0xffFFA726, 0xff00897B, 0xff6A1B9A, 0xff29B6F6, 0xff2E7D32,
    0xff5C8AE6, 0xff1565C0, 0xff7889B3, 0xffFF6EC7, 0xff00838F,
]

let ALL_WS = ["1","2","3","4","5","6","7","8","9",
              "A","B","C","D","E","F","G","H","I","J","K","L","M",
              "N","O","P","Q","R","S","T","U","V","W","X","Y","Z"]

// Maps WS code → slot color (same mapping as aerospace.sh)
var slotColorMap: [String: UInt32] = {
    var m: [String: UInt32] = [:]
    for (i, ws) in ALL_WS.enumerated() {
        m[ws] = SLOT_COLORS[i % SLOT_COLORS.count]
    }
    return m
}()

let barHeightNormal: CGFloat = 40
let barHeightTall:   CGFloat = 80
let pillHeight:      CGFloat = 28
let cornerRadius:    CGFloat = 9
let borderWidth:     CGFloat = 2

let nerdFont   = NSFont(name: "Hack Nerd Font", size: 14) ?? NSFont.systemFont(ofSize: 14)
let nerdFont16 = NSFont(name: "Hack Nerd Font", size: 16) ?? NSFont.systemFont(ofSize: 16)
let nerdFont13 = NSFont(name: "Hack Nerd Font", size: 13) ?? NSFont.systemFont(ofSize: 13)

// ──────────────────────────────────────────────────────────────────────────────
// MARK: – Aerospace runner
// ──────────────────────────────────────────────────────────────────────────────

enum Aerospace {
    static func run(_ args: [String]) -> String {
        let aero = FileManager.default.fileExists(atPath: "/opt/homebrew/bin/aerospace")
            ? "/opt/homebrew/bin/aerospace" : "/usr/local/bin/aerospace"
        let p = Process()
        p.launchPath = aero
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        try? p.run()
        p.waitUntilExit()
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
// MARK: – BarState
// ──────────────────────────────────────────────────────────────────────────────

struct WsInfo {
    var id: String
    var name: String
    var color: String     // hex like "1A73E8" or ""
    var repo: String      // repo basename or ""
}

struct BarState {
    var focused: String = ""
    var active: Set<String> = []          // non-empty, non-focused workspaces
    var wsInfo: [String: WsInfo] = [:]    // labeled workspaces
    var monitorWorkspaces: [Int: Set<String>] = [:]  // 1-based AeroSpace monitor → workspace IDs
    var currentWindows: [(id: Int, app: String)] = []   // windows in focused ws
    var apps: [[String: String]] = []     // apps.json array
    var labelMaxLen: Int = -1
    var repoPrefix: Bool = false
    var barTall: Bool = false
    var serviceMode: Bool = false
    var claudeAlert: Set<String> = []
    var claudeActive: Set<String> = []

    // Snapshot — runs on utility queue, no UI mutations here
    static func snapshot() -> BarState {
        var s = BarState()
        let hub = NSHomeDirectory() + "/.config/hub"

        s.focused = Aerospace.run(["list-workspaces", "--focused"])

        let activeRaw = Aerospace.run(["list-workspaces", "--monitor", "all", "--empty", "no"])
        s.active = Set(activeRaw.split(separator: "\n").map { String($0) })
        s.active.remove(s.focused)

        // Per-monitor workspace lists (for secondary-monitor label filtering)
        let monCountRaw = Aerospace.run(["list-monitors", "--format", "%{monitor-id}"])
        let monitorIDs = monCountRaw.split(separator: "\n").compactMap { Int($0) }
        for mid in monitorIDs {
            let wsRaw = Aerospace.run(["list-workspaces", "--monitor", "\(mid)"])
            s.monitorWorkspaces[mid] = Set(wsRaw.split(separator: "\n").map { String($0) })
        }

        // Labels file
        let labelsFile = hub + "/sketchybar_labels"
        if let lines = try? String(contentsOfFile: labelsFile, encoding: .utf8) {
            for line in lines.split(separator: "\n") {
                let parts = line.split(separator: ":", maxSplits: 3, omittingEmptySubsequences: false).map(String.init)
                guard parts.count >= 1 else { continue }
                let id = parts[0]
                guard !id.isEmpty else { continue }
                s.wsInfo[id] = WsInfo(
                    id:    id,
                    name:  parts.count > 1 ? parts[1] : "",
                    color: parts.count > 2 ? parts[2] : "",
                    repo:  parts.count > 3 ? parts[3] : ""
                )
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

        // label_maxlen
        let maxlenFile = hub + "/label_maxlen"
        if let v = try? String(contentsOfFile: maxlenFile, encoding: .utf8),
           let n = Int(v.trimmingCharacters(in: .whitespacesAndNewlines)) {
            s.labelMaxLen = n
        }

        // repo_prefix
        let prefixFile = hub + "/repo_prefix"
        if let v = try? String(contentsOfFile: prefixFile, encoding: .utf8) {
            s.repoPrefix = v.trimmingCharacters(in: .whitespacesAndNewlines) == "on"
        }

        // bar_tall
        s.barTall = FileManager.default.fileExists(atPath: hub + "/bar_tall")

        // service mode
        s.serviceMode = FileManager.default.fileExists(atPath: "/tmp/hub_service_mode")

        // claude states
        for ws in ALL_WS {
            if FileManager.default.fileExists(atPath: "/tmp/hub_claude_alert_\(ws)") {
                s.claudeAlert.insert(ws)
            }
            if FileManager.default.fileExists(atPath: "/tmp/hub_claude_active_\(ws)") {
                s.claudeActive.insert(ws)
            }
        }
        // Auto-clear for focused workspace
        if !s.focused.isEmpty {
            try? FileManager.default.removeItem(atPath: "/tmp/hub_claude_alert_\(s.focused)")
            try? FileManager.default.removeItem(atPath: "/tmp/hub_claude_active_\(s.focused)")
            s.claudeAlert.remove(s.focused)
            s.claudeActive.remove(s.focused)
        }

        return s
    }

    func labelFor(ws: String) -> String {
        guard let info = wsInfo[ws], !info.name.isEmpty else { return ws }
        var name = info.name
        if repoPrefix, !info.repo.isEmpty, name != info.repo {
            name = "\(info.repo):\(name)"
        }
        if labelMaxLen == 0 { return ws }
        if labelMaxLen > 0, name.count > labelMaxLen, ws != focused {
            let truncated = String(name.prefix(labelMaxLen))
            return "\(ws) \(truncated)…"
        }
        return "\(ws) \(name)"
    }
}

// ──────────────────────────────────────────────────────────────────────────────
// MARK: – ClickView
// ──────────────────────────────────────────────────────────────────────────────

class ClickView: NSView {
    var onPress: (() -> Void)?
    var hoverBG: NSColor = NSColor(argb: HOVER_BG)
    var normalBG: NSColor = .clear

    override func mouseDown(with event: NSEvent) {
        onPress?()
    }
    override func mouseEntered(with event: NSEvent) {
        layer?.backgroundColor = hoverBG.cgColor
    }
    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = normalBG.cgColor
    }
    override var acceptsFirstResponder: Bool { false }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self, userInfo: nil))
    }
}

// ──────────────────────────────────────────────────────────────────────────────
// MARK: – PillView: rounded-rect with border + label
// ──────────────────────────────────────────────────────────────────────────────

class PillView: ClickView {
    let textField: NSTextField

    init() {
        textField = NSTextField(labelWithString: "")
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.isEditable = false
        textField.isBordered = false
        textField.backgroundColor = .clear
        textField.font = nerdFont13
        textField.textColor = NSColor(argb: C_WHITE)
        textField.lineBreakMode = .byClipping
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        layer?.masksToBounds = true
        addSubview(textField)
        NSLayoutConstraint.activate([
            textField.centerYAnchor.constraint(equalTo: centerYAnchor),
            textField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            textField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func apply(bg: UInt32, fg: UInt32, borderColor: UInt32, bw: CGFloat, text: String, font: NSFont? = nil) {
        let bgColor = NSColor(argb: bg)
        layer?.backgroundColor = bgColor.cgColor
        layer?.borderColor = NSColor(argb: borderColor).cgColor
        layer?.borderWidth = bw
        textField.stringValue = text
        textField.textColor = NSColor(argb: fg)
        if let f = font { textField.font = f }
        // Keep normalBG in sync so mouseExited restores the correct background
        normalBG = bgColor
    }
}

// ──────────────────────────────────────────────────────────────────────────────
// MARK: – WorkspacePill
// ──────────────────────────────────────────────────────────────────────────────

class WorkspacePill: PillView {
    let wsID: String
    var pulseBright = true
    var isFocused = false

    init(wsID: String) {
        self.wsID = wsID
        super.init()
        normalBG = .clear
        let hub = hubScriptPath() ?? ""
        onPress = { [weak self] in
            guard let self = self, !self.isFocused else { return }
            let aero = FileManager.default.fileExists(atPath: "/opt/homebrew/bin/aerospace")
                ? "/opt/homebrew/bin/aerospace" : "/usr/local/bin/aerospace"
            Process.launchedProcess(launchPath: aero, arguments: ["workspace", wsID])
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    override func mouseEntered(with event: NSEvent) {
        guard !isFocused else { return }
        super.mouseEntered(with: event)
    }

    func updatePulse(bright: Bool) {
        pulseBright = bright
        let c = bright ? C_BLUE : 0x3076cce0 as UInt32
        layer?.borderColor = NSColor(argb: c).cgColor
    }
}

// ──────────────────────────────────────────────────────────────────────────────
// MARK: – AppSlotView (launcher icon)
// ──────────────────────────────────────────────────────────────────────────────

class AppSlotView: ClickView {
    let imageView: NSImageView
    let dotView:   NSView
    let tipLabel:  NSTextField

    init(slot: Int) {
        imageView = NSImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.imageScaling = .scaleProportionallyUpOrDown

        dotView = NSView()
        dotView.translatesAutoresizingMaskIntoConstraints = false
        dotView.wantsLayer = true
        dotView.layer?.cornerRadius = 3
        dotView.layer?.backgroundColor = NSColor(argb: C_GREEN).cgColor

        tipLabel = NSTextField(labelWithString: "\(slot)")
        tipLabel.translatesAutoresizingMaskIntoConstraints = false
        tipLabel.font = NSFont(name: "Hack Nerd Font", size: 9) ?? NSFont.systemFont(ofSize: 9)
        tipLabel.textColor = NSColor(white: 1, alpha: 0.67)
        tipLabel.isEditable = false
        tipLabel.isBordered = false
        tipLabel.backgroundColor = .clear

        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        normalBG = .clear

        addSubview(imageView)
        addSubview(dotView)
        addSubview(tipLabel)

        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -4),
            imageView.widthAnchor.constraint(equalToConstant: 28),
            imageView.heightAnchor.constraint(equalToConstant: 28),
            dotView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3),
            dotView.centerXAnchor.constraint(equalTo: centerXAnchor),
            dotView.widthAnchor.constraint(equalToConstant: 6),
            dotView.heightAnchor.constraint(equalToConstant: 6),
            tipLabel.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            tipLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
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
// MARK: – WsWinSlotView (extra workspace apps)
// ──────────────────────────────────────────────────────────────────────────────

class WsWinSlotView: ClickView {
    let imageView: NSImageView
    var windowIDs: [Int] = []
    var rotateIdx: Int = 0

    init() {
        imageView = NSImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.imageScaling = .scaleProportionallyUpOrDown

        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        normalBG = .clear

        addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -2),
            imageView.widthAnchor.constraint(equalToConstant: 28),
            imageView.heightAnchor.constraint(equalToConstant: 28),
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
// MARK: – System processes filter (mirrors app_launcher.sh)
// ──────────────────────────────────────────────────────────────────────────────

private let SYSTEM_PROCS: Set<String> = [
    "SecurityAgent", "UserNotificationCenter", "ScreenSaverEngine",
    "System Preferences", "System Settings", "Finder",
    "universalaccessd", "loginwindow"
]

func isSystemProc(_ name: String) -> Bool {
    if name.contains(".") { return true }
    return SYSTEM_PROCS.contains(name)
}

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
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.dismiss()
        }
    }

    func dismiss() {
        if let m = globalMonitor { NSEvent.removeMonitor(m); globalMonitor = nil }
        orderOut(nil)
    }
}

// ──────────────────────────────────────────────────────────────────────────────
// MARK: – BarWindow (one per NSScreen)
// ──────────────────────────────────────────────────────────────────────────────

class BarWindow: NSWindow {
    let barScreen: NSScreen
    var monitorIndex: Int = 1  // 1-based AeroSpace monitor index
    let leadingStack: NSStackView
    let trailingStack: NSStackView

    // Workspace pills
    var wsPills: [String: WorkspacePill] = [:]

    // Right-side widgets
    var clockLabel: NSTextField?
    var battLabel: NSTextField?
    var battIcon: NSTextField?
    var wifiIcon: NSTextField?
    var volLabel: NSTextField?
    var volIcon: NSTextField?
    var serviceModeLabel: NSView?

    // App launcher slots
    var appSlots: [AppSlotView] = []
    // WsWin slots
    var wsWinSlots: [WsWinSlotView] = []

    // Volume popup
    var volPopup: VolumePopupWindow?

    init(screen: NSScreen) {
        self.barScreen = screen
        leadingStack = NSStackView()
        trailingStack = NSStackView()

        let sf = screen.frame
        let r = NSRect(x: sf.minX, y: sf.maxY - barHeightNormal, width: sf.width, height: barHeightNormal)

        super.init(contentRect: r, styleMask: .borderless, backing: .buffered, defer: false)

        level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)
        backgroundColor = NSColor(argb: BAR_COLOR)
        isOpaque = false
        hasShadow = true
        ignoresMouseEvents = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
    }

    func buildContents(state: BarState) {
        let cv = contentView!
        // Fully remove and recreate stacks to avoid duplicate arranged subviews on rebuild
        leadingStack.removeFromSuperview()
        trailingStack.removeFromSuperview()
        leadingStack.arrangedSubviews.forEach { leadingStack.removeArrangedSubview($0); $0.removeFromSuperview() }
        trailingStack.arrangedSubviews.forEach { trailingStack.removeArrangedSubview($0); $0.removeFromSuperview() }
        cv.subviews.forEach { $0.removeFromSuperview() }
        wsPills.removeAll()
        appSlots.removeAll()
        wsWinSlots.removeAll()
        volPopup = nil

        // Adjust bar height
        let barH = state.barTall ? barHeightTall : barHeightNormal
        let sf = barScreen.frame
        setFrame(NSRect(x: sf.minX, y: sf.maxY - barH, width: sf.width, height: barH), display: true)

        leadingStack.translatesAutoresizingMaskIntoConstraints = false
        leadingStack.orientation = .horizontal
        leadingStack.spacing = 4
        leadingStack.edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 0)

        trailingStack.translatesAutoresizingMaskIntoConstraints = false
        trailingStack.orientation = .horizontal
        trailingStack.spacing = 4
        trailingStack.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 8)

        cv.addSubview(leadingStack)
        cv.addSubview(trailingStack)

        // In tall mode: widgets (trailing) on top row, labels (leading) on bottom row.
        // NSWindow content view is flipped (y=0 at top), so positive Y offset = lower on screen.
        let leadingYOffset: CGFloat = state.barTall ? 20 : 0
        let trailingYOffset: CGFloat = state.barTall ? -20 : 0

        NSLayoutConstraint.activate([
            leadingStack.leadingAnchor.constraint(equalTo: cv.leadingAnchor),
            leadingStack.centerYAnchor.constraint(equalTo: cv.centerYAnchor, constant: leadingYOffset),
            leadingStack.heightAnchor.constraint(equalToConstant: pillHeight),
            trailingStack.trailingAnchor.constraint(equalTo: cv.trailingAnchor),
            trailingStack.centerYAnchor.constraint(equalTo: cv.centerYAnchor, constant: trailingYOffset),
            trailingStack.heightAnchor.constraint(equalToConstant: pillHeight),
        ])

        buildWorkspaceStrip(state: state)
        buildRightWidgets(state: state)
    }

    // ── Workspace pills ──────────────────────────────────────────────────────

    func buildWorkspaceStrip(state: BarState) {
        // Only show workspaces assigned to this monitor (secondary screens show only their own)
        let monitorWs = state.monitorWorkspaces[monitorIndex]
        for ws in ALL_WS {
            // If we have per-monitor data, filter; otherwise show all (primary monitor fallback)
            if let monWs = monitorWs, !monWs.contains(ws) { continue }
            let pill = WorkspacePill(wsID: ws)
            pill.translatesAutoresizingMaskIntoConstraints = false
            pill.heightAnchor.constraint(equalToConstant: pillHeight).isActive = true
            wsPills[ws] = pill
            leadingStack.addArrangedSubview(pill)
        }
        applyWorkspaceState(state: state)
    }

    func applyWorkspaceState(state: BarState) {
        for ws in ALL_WS {
            guard let pill = wsPills[ws] else { continue }
            let isActive = state.active.contains(ws) || ws == state.focused
            let isFocused = ws == state.focused
            pill.isFocused = isFocused
            let isLabeled = state.wsInfo[ws] != nil

            if isActive {
                if isFocused {
                    let bgColor = wsColor(ws: ws, state: state)
                    let lum = luminance(argb: bgColor)
                    let fg: UInt32 = lum > 160 ? 0xff000000 : 0xffffffff
                    pill.apply(bg: bgColor, fg: fg, borderColor: ITEM_BG2, bw: borderWidth,
                               text: state.labelFor(ws: ws), font: nerdFont13)
                    pill.isHidden = false
                } else {
                    let hasAlert  = state.claudeAlert.contains(ws)
                    let hasActive = state.claudeActive.contains(ws)
                    let bcolor: UInt32 = hasActive ? C_BLUE : (hasAlert ? 0xffF9A825 : ITEM_BG2)
                    let bw: CGFloat    = (hasActive || hasAlert) ? 3 : 1
                    pill.apply(bg: INACTIVE_BG, fg: 0xaaffffff, borderColor: bcolor, bw: bw,
                               text: state.labelFor(ws: ws), font: nerdFont13)
                    pill.isHidden = false
                }
            } else if isLabeled {
                let hasAlert  = state.claudeAlert.contains(ws)
                let hasActive = state.claudeActive.contains(ws)
                let bcolor: UInt32 = hasActive ? C_BLUE : (hasAlert ? 0xffF9A825 : 0x00000000)
                let bw: CGFloat    = (hasActive || hasAlert) ? 3 : 0
                pill.apply(bg: EMPTY_LABELED_BG, fg: 0x55ffffff, borderColor: bcolor, bw: bw,
                           text: state.labelFor(ws: ws), font: nerdFont13)
                pill.isHidden = false
            } else {
                pill.isHidden = true
            }
        }
    }

    func wsColor(ws: String, state: BarState) -> UInt32 {
        if let info = state.wsInfo[ws], !info.color.isEmpty {
            let hex = info.color.hasPrefix("#") ? String(info.color.dropFirst()) : info.color
            if let v = UInt32(hex, radix: 16) {
                return 0xff000000 | v
            }
        }
        return slotColorMap[ws] ?? ITEM_BG
    }

    // ── Right widgets ────────────────────────────────────────────────────────

    func buildRightWidgets(state: BarState) {
        // Service mode indicator (leftmost in trailing, i.e. added first reversed)
        buildServiceMode(state: state)

        // WsWin strip
        buildWsWinStrip(state: state)

        addSpacer(8)

        // App launcher
        buildAppLauncher(state: state)

        addSpacer(8)

        // Wifi
        buildWifi()

        addSpacer(8)

        // Volume
        buildVolume()

        addSpacer(8)

        // Battery
        buildBattery()

        addSpacer(8)

        // Clock (rightmost = last added in trailing)
        buildClock()
    }

    func addSpacer(_ width: CGFloat) {
        let sp = NSView()
        sp.translatesAutoresizingMaskIntoConstraints = false
        sp.widthAnchor.constraint(equalToConstant: width).isActive = true
        trailingStack.addArrangedSubview(sp)
    }

    func makePillContainer(content: NSView) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor(argb: ITEM_BG).cgColor
        container.layer?.cornerRadius = cornerRadius
        container.layer?.masksToBounds = true
        container.layer?.borderWidth = borderWidth
        container.layer?.borderColor = NSColor(argb: ITEM_BG2).cgColor
        container.heightAnchor.constraint(equalToConstant: pillHeight).isActive = true
        content.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            content.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            content.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
        return container
    }

    func makeIconLabel(icon: String, iconColor: UInt32, text: String) -> (container: NSView, icon: NSTextField, label: NSTextField) {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false

        let ic = NSTextField(labelWithString: icon)
        ic.font = nerdFont16
        ic.textColor = NSColor(argb: iconColor)
        ic.isEditable = false; ic.isBordered = false; ic.backgroundColor = .clear

        let lbl = NSTextField(labelWithString: text)
        lbl.font = nerdFont13
        lbl.textColor = NSColor(argb: C_WHITE)
        lbl.isEditable = false; lbl.isBordered = false; lbl.backgroundColor = .clear

        stack.addArrangedSubview(ic)
        stack.addArrangedSubview(lbl)

        return (makePillContainer(content: stack), ic, lbl)
    }

    func buildClock() {
        let (container, ic, lbl) = makeIconLabel(icon: "󰃰", iconColor: C_YELLOW, text: "")
        clockLabel = lbl
        ic.font = nerdFont16
        trailingStack.addArrangedSubview(container)
        updateClock()
    }

    func updateClock() {
        let fmt = DateFormatter()
        fmt.dateFormat = "EEE dd MMM HH:mm"
        clockLabel?.stringValue = fmt.string(from: Date())
    }

    func buildBattery() {
        let (container, ic, lbl) = makeIconLabel(icon: "󰁹", iconColor: C_GREEN, text: "--")
        battIcon = ic
        battLabel = lbl
        // Click → battery system prefs
        let battClick = ClickView(frame: .zero)
        battClick.translatesAutoresizingMaskIntoConstraints = false
        battClick.onPress = {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.battery")!)
        }
        container.addSubview(battClick)
        NSLayoutConstraint.activate([
            battClick.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            battClick.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            battClick.topAnchor.constraint(equalTo: container.topAnchor),
            battClick.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        trailingStack.addArrangedSubview(container)
        updateBattery()
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

        battIcon?.stringValue = icon
        battIcon?.textColor = NSColor(argb: color)
        battLabel?.stringValue = "\(pct)%"
    }

    func buildWifi() {
        let (container, ic, _) = makeIconLabel(icon: "󰤨", iconColor: C_GREEN, text: "")
        wifiIcon = ic
        // Click → network settings
        let wifiClick = ClickView(frame: .zero)
        wifiClick.translatesAutoresizingMaskIntoConstraints = false
        wifiClick.onPress = {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.network")!)
        }
        container.addSubview(wifiClick)
        NSLayoutConstraint.activate([
            wifiClick.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            wifiClick.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            wifiClick.topAnchor.constraint(equalTo: container.topAnchor),
            wifiClick.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        trailingStack.addArrangedSubview(container)
        updateWifi()
    }

    func updateWifi() {
        let ssid = CWWiFiClient.shared().interface()?.ssid()
        if ssid != nil {
            wifiIcon?.stringValue = "󰤨"
            wifiIcon?.textColor = NSColor(argb: C_GREEN)
        } else {
            wifiIcon?.stringValue = "󰤭"
            wifiIcon?.textColor = NSColor(argb: C_RED)
        }
    }

    func buildVolume() {
        let (container, ic, lbl) = makeIconLabel(icon: "󰕾", iconColor: C_BLUE, text: "")
        volIcon = ic
        volLabel = lbl

        let volClick = ClickView(frame: .zero)
        volClick.translatesAutoresizingMaskIntoConstraints = false
        volClick.onPress = { [weak self] in self?.toggleVolumePopup() }
        container.addSubview(volClick)
        NSLayoutConstraint.activate([
            volClick.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            volClick.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            volClick.topAnchor.constraint(equalTo: container.topAnchor),
            volClick.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        trailingStack.addArrangedSubview(container)
        updateVolume()

        // Listen for external volume changes
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, DispatchQueue.main) { [weak self] _, _ in
            self?.updateVolume()
        }
    }

    func updateVolume() {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &deviceID)

        var muted: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        var muteAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyData(deviceID, &muteAddr, 0, nil, &size, &muted)

        var vol: Float32 = 0
        size = UInt32(MemoryLayout<Float32>.size)
        var volAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
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

    func toggleVolumePopup() {
        if let p = volPopup, p.isVisible { p.dismiss(); volPopup = nil; return }

        // Build popup window
        let popW: CGFloat = 220
        let popH: CGFloat = 44
        // Anchor below volume pill in bar
        let barFrame = frame
        let popX = barFrame.maxX - 300  // approximate; will adjust
        let popY = barFrame.minY - popH - 4

        let popup = VolumePopupWindow(
            contentRect: NSRect(x: popX, y: popY, width: popW, height: popH),
            styleMask: .borderless, backing: .buffered, defer: false)
        popup.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)
        popup.backgroundColor = NSColor(argb: ITEM_BG)
        popup.isOpaque = false
        popup.hasShadow = true
        popup.collectionBehavior = [.canJoinAllSpaces, .stationary]

        let cv = popup.contentView!
        cv.wantsLayer = true
        cv.layer?.cornerRadius = cornerRadius
        cv.layer?.masksToBounds = true
        cv.layer?.borderWidth = borderWidth
        cv.layer?.borderColor = NSColor(argb: ITEM_BG2).cgColor

        // Mute icon
        let muteIcon = NSTextField(labelWithString: "󰖁")
        muteIcon.translatesAutoresizingMaskIntoConstraints = false
        muteIcon.font = nerdFont13
        muteIcon.textColor = NSColor(argb: C_WHITE)
        muteIcon.isEditable = false; muteIcon.isBordered = false; muteIcon.backgroundColor = .clear

        // Slider
        let slider = NSSlider(value: 0.5, minValue: 0, maxValue: 1, target: nil, action: nil)
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.isContinuous = true
        if let cell = slider.cell as? NSSliderCell {
            cell.isVertical = false
        }

        // Max icon
        let maxIcon = NSTextField(labelWithString: "󰕾")
        maxIcon.translatesAutoresizingMaskIntoConstraints = false
        maxIcon.font = nerdFont13
        maxIcon.textColor = NSColor(argb: C_WHITE)
        maxIcon.isEditable = false; maxIcon.isBordered = false; maxIcon.backgroundColor = .clear

        cv.addSubview(muteIcon)
        cv.addSubview(slider)
        cv.addSubview(maxIcon)

        NSLayoutConstraint.activate([
            muteIcon.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 10),
            muteIcon.centerYAnchor.constraint(equalTo: cv.centerYAnchor),
            slider.leadingAnchor.constraint(equalTo: muteIcon.trailingAnchor, constant: 6),
            slider.trailingAnchor.constraint(equalTo: maxIcon.leadingAnchor, constant: -6),
            slider.centerYAnchor.constraint(equalTo: cv.centerYAnchor),
            maxIcon.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -10),
            maxIcon.centerYAnchor.constraint(equalTo: cv.centerYAnchor),
        ])

        // Load current volume
        var deviceID = AudioDeviceID(0)
        var sz = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &sz, &deviceID)
        var vol: Float32 = 0
        sz = UInt32(MemoryLayout<Float32>.size)
        var volAddr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyData(deviceID, &volAddr, 0, nil, &sz, &vol)
        slider.doubleValue = Double(vol)

        // Slider action: set volume
        let target = VolumeSliderTarget(deviceID: deviceID) { [weak self] in self?.updateVolume() }
        slider.target = target
        slider.action = #selector(VolumeSliderTarget.sliderChanged(_:))
        // Keep target alive
        objc_setAssociatedObject(popup, "sliderTarget", target, .OBJC_ASSOCIATION_RETAIN)

        // Mute click
        let muteBtn = ClickView(frame: .zero)
        muteBtn.translatesAutoresizingMaskIntoConstraints = false
        muteBtn.onPress = { [weak self] in
            var mut: UInt32 = 0
            var mutSz = UInt32(MemoryLayout<UInt32>.size)
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

        popup.orderFrontRegardless()
        popup.installDismissMonitor()
        volPopup = popup
    }

    func buildAppLauncher(state: BarState) {
        guard !state.apps.isEmpty else { return }
        let hub = hubScriptPath() ?? ""

        for (i, app) in state.apps.enumerated() {
            let slot = i + 1
            let slotView = AppSlotView(slot: slot)
            slotView.translatesAutoresizingMaskIntoConstraints = false
            slotView.widthAnchor.constraint(equalToConstant: 36).isActive = true
            slotView.heightAnchor.constraint(equalToConstant: pillHeight).isActive = true

            // Set icon — prefer bundle ID lookup, fall back to /Applications path
            if let bid = app["bundle_id"] ?? app["bundleID"], !bid.isEmpty {
                slotView.setIcon(bundleID: bid)
            } else if let name = app["name"], !name.isEmpty {
                // Try running app first, then /Applications fallback
                if let running = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == name }),
                   let url = running.bundleURL {
                    slotView.imageView.image = NSWorkspace.shared.icon(forFile: url.path)
                } else {
                    slotView.setIconByName(name)
                }
            }

            // Running indicator
            let appName = app["name"] ?? ""
            let isRunning = state.currentWindows.contains { $0.app == appName }
            slotView.dotView.isHidden = !isRunning

            slotView.onPress = { [weak slotView] in
                guard !hub.isEmpty else { return }
                let mods = NSEvent.modifierFlags
                let force = mods.contains(.shift) ? " --force" : ""
                Process.launchedProcess(launchPath: "/bin/sh",
                    arguments: ["-c", "'\(hub)' open \(slot)\(force)"])
                slotView?.layer?.backgroundColor = NSColor(argb: CLICK_BG).withAlphaComponent(0.3).cgColor
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    slotView?.layer?.backgroundColor = nil
                }
            }

            appSlots.append(slotView)
            trailingStack.addArrangedSubview(slotView)
        }

        // App launcher pill container wraps all slots
        // (Stack view handles layout; no explicit bracket container needed)
    }

    func buildWsWinStrip(state: BarState) {
        // Determine extra apps (not in launcher, not system procs)
        let launcherNames = Set(state.apps.compactMap { $0["name"] })
        var extraApps: [(app: String, ids: [Int])] = []
        var seen = Set<String>()
        for win in state.currentWindows {
            let app = win.app
            if isSystemProc(app) { continue }
            if launcherNames.contains(app) { continue }
            if seen.contains(app) {
                if let idx = extraApps.firstIndex(where: { $0.app == app }) {
                    extraApps[idx].ids.append(win.id)
                }
                continue
            }
            seen.insert(app)
            if extraApps.count < 8 {
                extraApps.append((app: app, ids: [win.id]))
            }
        }

        for (i, entry) in extraApps.prefix(8).enumerated() {
            _ = i
            let slot = WsWinSlotView()
            slot.translatesAutoresizingMaskIntoConstraints = false
            slot.widthAnchor.constraint(equalToConstant: 36).isActive = true
            slot.heightAnchor.constraint(equalToConstant: pillHeight).isActive = true
            slot.windowIDs = entry.ids

            let appPath = "/Applications/\(entry.app).app"
            if FileManager.default.fileExists(atPath: appPath) {
                slot.imageView.image = NSWorkspace.shared.icon(forFile: appPath)
            } else if let running = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == entry.app }),
                      let url = running.bundleURL {
                slot.imageView.image = NSWorkspace.shared.icon(forFile: url.path)
            }

            wsWinSlots.append(slot)
            trailingStack.addArrangedSubview(slot)
        }
    }

    func buildServiceMode(state: BarState) {
        let pill = NSView()
        pill.translatesAutoresizingMaskIntoConstraints = false
        pill.wantsLayer = true
        pill.layer?.backgroundColor = NSColor(argb: 0xffC91B00).cgColor
        pill.layer?.cornerRadius = cornerRadius
        pill.layer?.masksToBounds = true
        pill.heightAnchor.constraint(equalToConstant: pillHeight).isActive = true
        pill.widthAnchor.constraint(equalToConstant: 30).isActive = true

        let lbl = NSTextField(labelWithString: "S")
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.font = nerdFont13
        lbl.textColor = .white
        lbl.isEditable = false; lbl.isBordered = false; lbl.backgroundColor = .clear
        lbl.alignment = .center
        pill.addSubview(lbl)
        NSLayoutConstraint.activate([
            lbl.centerXAnchor.constraint(equalTo: pill.centerXAnchor),
            lbl.centerYAnchor.constraint(equalTo: pill.centerYAnchor),
        ])
        pill.isHidden = !state.serviceMode
        serviceModeLabel = pill
        trailingStack.addArrangedSubview(pill)
    }

    func applyRefresh(state: BarState) {
        applyWorkspaceState(state: state)
        updateClock()
        updateBattery()
        updateWifi()
        updateVolume()
        serviceModeLabel?.isHidden = !state.serviceMode
    }
}

// ──────────────────────────────────────────────────────────────────────────────
// MARK: – Volume slider target (ObjC bridge)
// ──────────────────────────────────────────────────────────────────────────────

class VolumeSliderTarget: NSObject {
    let deviceID: AudioDeviceID
    let onChange: () -> Void

    init(deviceID: AudioDeviceID, onChange: @escaping () -> Void) {
        self.deviceID = deviceID
        self.onChange = onChange
    }

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
// MARK: – BarController
// ──────────────────────────────────────────────────────────────────────────────

class BarController: NSObject {
    var windows: [BarWindow] = []
    var clockTimer: Timer?
    var batteryTimer: Timer?
    var wifiTimer: Timer?
    var pulseTimer: Timer?
    var pulseBright = true
    var lastState = BarState()

    func start() {
        writePIDFile()
        buildWindows()
        installSignalSource()
        startTimers()
    }

    func writePIDFile() {
        let path = NSHomeDirectory() + "/.config/hub/status_bar.pid"
        try? "\(ProcessInfo.processInfo.processIdentifier)\n".write(toFile: path, atomically: true, encoding: .utf8)
    }

    func buildWindows() {
        windows.forEach { $0.close() }
        windows.removeAll()
        DispatchQueue.global(qos: .userInitiated).async {
            let state = BarState.snapshot()
            // Map AeroSpace monitor IDs to NSScreen by geometry: AeroSpace lists monitors
            // sorted left-to-right by origin.x; match NSScreen by same ordering.
            let sortedScreens = NSScreen.screens.sorted { $0.frame.minX < $1.frame.minX }
            let monitorIDs = state.monitorWorkspaces.keys.sorted()
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.lastState = state
                for (i, screen) in sortedScreens.enumerated() {
                    let w = BarWindow(screen: screen)
                    // Assign 1-based AeroSpace monitor index by left-to-right screen order
                    w.monitorIndex = monitorIDs.indices.contains(i) ? monitorIDs[i] : (i + 1)
                    w.buildContents(state: state)
                    w.orderFrontRegardless()
                    self.windows.append(w)
                }
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
        // Keep src alive
        objc_setAssociatedObject(self, "sigusr1src", src, .OBJC_ASSOCIATION_RETAIN)
    }

    func refresh() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let state = BarState.snapshot()
            DispatchQueue.main.async {
                let prevTall = self?.lastState.barTall ?? false
                self?.lastState = state
                for w in self?.windows ?? [] {
                    if state.barTall != prevTall {
                        w.buildContents(state: state)
                        w.orderFrontRegardless()
                    } else {
                        w.applyRefresh(state: state)
                    }
                }
            }
        }
    }

    func startTimers() {
        clockTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.windows.forEach { $0.updateClock() }
        }
        batteryTimer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in
            self?.windows.forEach { $0.updateBattery() }
        }
        wifiTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.windows.forEach { $0.updateWifi() }
        }
        pulseTimer = Timer.scheduledTimer(withTimeInterval: 0.75, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.pulseBright = !self.pulseBright
            let bright = self.pulseBright
            let state = self.lastState
            for w in self.windows {
                for ws in state.claudeActive {
                    if let pill = w.wsPills[ws] {
                        pill.updatePulse(bright: bright)
                    }
                }
            }
        }

        // Wake notification: refresh battery + wifi
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification,
            object: nil, queue: .main) { [weak self] _ in
            self?.windows.forEach { $0.updateBattery(); $0.updateWifi() }
        }

        // Screen change: rebuild all windows
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in
            self?.buildWindows()
        }
    }
}

// ──────────────────────────────────────────────────────────────────────────────
// MARK: – Single-instance guard & entry point
// ──────────────────────────────────────────────────────────────────────────────

let pidFile = NSHomeDirectory() + "/.config/hub/status_bar.pid"
if let existing = try? String(contentsOfFile: pidFile, encoding: .utf8),
   let existingPID = Int(existing.trimmingCharacters(in: .whitespacesAndNewlines)),
   existingPID != Int(ProcessInfo.processInfo.processIdentifier) {
    // Check if that PID is still alive
    let alive = kill(pid_t(existingPID), 0) == 0
    if alive {
        fputs("status_bar: another instance already running (pid \(existingPID))\n", stderr)
        exit(1)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = BarController()
    func applicationDidFinishLaunching(_ n: Notification) {
        controller.start()
    }
}

let delegate = AppDelegate()
app.delegate = delegate
app.run()
