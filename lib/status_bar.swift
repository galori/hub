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

// ── Gradient stops ──
let GRAD_TOP:     UInt32 = 0xFF1A1C22
let GRAD_BOT:     UInt32 = 0xFF15171C
let CLUSTER_BG:   UInt32 = 0xFF181A20   // opaque occluder matching bar average

// ── Accent ──
let ACCENT:       UInt32 = 0xFF41D1C4   // fixed teal
let ACCENT_SOFT:  UInt32 = 0x2241D1C4   // teal @13%
let ACCENT_DOT:   UInt32 = 0xFF41D1C4

// ── Pill colours ──
let PILL_IDLE_BG:  UInt32 = 0x09FFFFFF   // rgba(255,255,255,0.035)
let PILL_IDX_IDLE: UInt32 = 0xFF5A5D68
let PILL_NAME_IDLE:UInt32 = 0xFFAEB3BF
let PILL_IDX_ACT:  UInt32 = 0x73000000  // rgba(0,0,0,0.45)
let PILL_NAME_ACT: UInt32 = 0xFF06201E

// ── Status dot (claude alert/active) ──
let DOT_ORANGE:   UInt32 = 0xFFF0883E
let DOT_BLUE:     UInt32 = 0xFF76CCE0

// ── App-icon group ──
let APPGRP_BG:    UInt32 = 0x0BFFFFFF   // rgba(255,255,255,0.045)
let APPGRP_BORDER:UInt32 = 0x0DFFFFFF   // rgba(255,255,255,0.05)
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
let barHeightTall:   CGFloat = 80
let pillH:           CGFloat = 28
let pillRadius:      CGFloat = 8
let pillPadH:        CGFloat = 10   // horizontal inner padding
let pillGap:         CGFloat = 5
let appIconSize:     CGFloat = 26
let appGroupGap:     CGFloat = 14

// ── Fonts ──
let monoFont11   = NSFont(name: "Hack Nerd Font", size: 11) ?? NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
let monoFont13   = NSFont(name: "Hack Nerd Font", size: 13) ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
let monoFont12   = NSFont(name: "Hack Nerd Font", size: 12) ?? NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
let monoFont16   = NSFont(name: "Hack Nerd Font", size: 16) ?? NSFont.monospacedSystemFont(ofSize: 16, weight: .regular)
let nerdFont     = monoFont13   // backward-compat alias
let nerdFont16   = monoFont16
let nerdFont13   = monoFont13

// ── Legacy (kept for volume popup) ──
let ITEM_BG:   UInt32 = 0xFF363944
let ITEM_BG2:  UInt32 = 0xFF414550
let HOVER_BG:  UInt32 = 0x33FFFFFF
let CLICK_BG:  UInt32 = 0xFF76CCE0
let cornerRadius: CGFloat = 9
let borderWidth:  CGFloat = 2

// ── Workspace slot colours (for per-ws identity, still used by wsColor()) ──
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
// MARK: – BarState
// ──────────────────────────────────────────────────────────────────────────────

struct WsInfo {
    var id: String; var name: String; var color: String; var repo: String
}

struct BarState {
    var focused: String = ""
    var active: Set<String> = []
    var wsInfo: [String: WsInfo] = [:]
    var monitorWorkspaces: [Int: Set<String>] = [:]
    var currentWindows: [(id: Int, app: String)] = []
    var apps: [[String: String]] = []
    var labelMaxLen: Int = -1
    var repoPrefix: Bool = false
    var barTall: Bool = false
    var serviceMode: Bool = false
    var claudeAlert: Set<String> = []
    var claudeActive: Set<String> = []

    static func snapshot() -> BarState {
        var s = BarState()
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
        let labelsFile = hub + "/sketchybar_labels"
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

        // label_maxlen
        if let v = try? String(contentsOfFile: hub + "/label_maxlen", encoding: .utf8),
           let n = Int(v.trimmingCharacters(in: .whitespacesAndNewlines)) { s.labelMaxLen = n }

        // repo_prefix
        if let v = try? String(contentsOfFile: hub + "/repo_prefix", encoding: .utf8) {
            s.repoPrefix = v.trimmingCharacters(in: .whitespacesAndNewlines) == "on"
        }

        // bar_tall
        s.barTall = FileManager.default.fileExists(atPath: hub + "/bar_tall")

        // service mode
        s.serviceMode = FileManager.default.fileExists(atPath: "/tmp/hub_service_mode")

        // claude states
        for ws in ALL_WS {
            if FileManager.default.fileExists(atPath: "/tmp/hub_claude_alert_\(ws)") { s.claudeAlert.insert(ws) }
            if FileManager.default.fileExists(atPath: "/tmp/hub_claude_active_\(ws)") { s.claudeActive.insert(ws) }
        }
        if !s.focused.isEmpty {
            try? FileManager.default.removeItem(atPath: "/tmp/hub_claude_alert_\(s.focused)")
            try? FileManager.default.removeItem(atPath: "/tmp/hub_claude_active_\(s.focused)")
            s.claudeAlert.remove(s.focused); s.claudeActive.remove(s.focused)
        }
        return s
    }

    // Returns (idx, name) spans for display. tall=true ⇒ never truncate.
    func spansFor(ws: String, tall: Bool) -> (idx: String, name: String) {
        guard let info = wsInfo[ws], !info.name.isEmpty else { return (ws, "") }
        var name = info.name
        if repoPrefix, !info.repo.isEmpty, name != info.repo { name = "\(info.repo):\(name)" }
        if labelMaxLen == 0 { return (ws, "") }
        if !tall, labelMaxLen > 0, name.count > labelMaxLen, ws != focused {
            return (ws, String(name.prefix(labelMaxLen)) + "…")
        }
        return (ws, name)
    }

    // Kept for backward compat
    func labelFor(ws: String) -> String {
        let (idx, name) = spansFor(ws: ws, tall: false)
        return name.isEmpty ? idx : "\(idx) \(name)"
    }

    func wsColor(ws: String) -> UInt32 {
        if let info = wsInfo[ws], !info.color.isEmpty {
            let hex = info.color.hasPrefix("#") ? String(info.color.dropFirst()) : info.color
            if let v = UInt32(hex, radix: 16) { return 0xff000000 | v }
        }
        return slotColorMap[ws] ?? ITEM_BG
    }
}

// ──────────────────────────────────────────────────────────────────────────────
// MARK: – BarBackgroundView (gradient + highlight + border)
// ──────────────────────────────────────────────────────────────────────────────

class BarBackgroundView: NSView {
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
// MARK: – ClickView
// ──────────────────────────────────────────────────────────────────────────────

class ClickView: NSView {
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

        // name field
        nameField.isEditable = false; nameField.isBordered = false; nameField.backgroundColor = .clear
        nameField.font = monoFont13
        nameField.lineBreakMode = .byClipping; nameField.setContentCompressionResistancePriority(.required, for: .horizontal)
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
        layer?.backgroundColor = NSColor(argb: HOVER_BG).cgColor
    }
    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = .none
    }

    func apply(bg: UInt32, idxColor: UInt32, nameColor: UInt32,
               idx: String, name: String,
               showDot: Bool, dotColor: UInt32,
               glowColor: UInt32?, glowRadius: CGFloat) {
        innerView.layer?.backgroundColor = NSColor(argb: bg).cgColor
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

class AppSlotView: ClickView {
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

class WsWinSlotView: ClickView {
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
// MARK: – BarWindow (one per NSScreen)
// ──────────────────────────────────────────────────────────────────────────────

class BarWindow: NSWindow {
    let barScreen: NSScreen
    var monitorIndex: Int = 1
    let leadingStack  = NSStackView()
    let trailingStack = NSStackView()   // kept for compat but unused in new layout

    var wsPills: [String: WorkspacePill] = [:]
    var appSlots:   [AppSlotView]   = []
    var wsWinSlots: [WsWinSlotView] = []
    var volPopup: VolumePopupWindow?

    // Widget label refs for updates
    var clockLabel: NSTextField?
    var battLabel:  NSTextField?
    var battIcon:   NSTextField?
    var wifiIcon:   NSTextField?
    var volLabel:   NSTextField?
    var volIcon:    NSTextField?
    var serviceModeLabel: NSView?

    init(screen: NSScreen) {
        self.barScreen = screen
        let sf = screen.frame
        let r = NSRect(x: sf.minX, y: sf.maxY - barHeightNormal, width: sf.width, height: barHeightNormal)
        super.init(contentRect: r, styleMask: .borderless, backing: .buffered, defer: false)
        level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        ignoresMouseEvents = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
    }

    func buildContents(state: BarState) {
        let cv = contentView!
        leadingStack.arrangedSubviews.forEach { leadingStack.removeArrangedSubview($0); $0.removeFromSuperview() }
        trailingStack.arrangedSubviews.forEach { trailingStack.removeArrangedSubview($0); $0.removeFromSuperview() }
        cv.subviews.forEach { $0.removeFromSuperview() }
        wsPills.removeAll(); appSlots.removeAll(); wsWinSlots.removeAll(); volPopup = nil
        clockLabel = nil; battLabel = nil; battIcon = nil; wifiIcon = nil; volLabel = nil; volIcon = nil
        serviceModeLabel = nil

        let barH = state.barTall ? barHeightTall : barHeightNormal
        let sf = barScreen.frame
        setFrame(NSRect(x: sf.minX, y: sf.maxY - barH, width: sf.width, height: barH), display: true)

        // Background
        let bg = BarBackgroundView(frame: cv.bounds)
        bg.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(bg)
        NSLayoutConstraint.activate([
            bg.leadingAnchor.constraint(equalTo: cv.leadingAnchor),
            bg.trailingAnchor.constraint(equalTo: cv.trailingAnchor),
            bg.topAnchor.constraint(equalTo: cv.topAnchor),
            bg.bottomAnchor.constraint(equalTo: cv.bottomAnchor),
        ])

        if state.barTall {
            buildTallLayout(cv: cv, state: state)
        } else {
            buildCompactLayout(cv: cv, state: state)
        }
    }

    // ── Compact layout ───────────────────────────────────────────────────────

    func buildCompactLayout(cv: NSView, state: BarState) {
        // Cluster (right side) — opaque so it occludes overflowing pills
        let cluster = buildCluster(state: state)
        cluster.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(cluster)  // added AFTER background

        // Clip view (holds leadingStack, clips at cluster left edge)
        let clipView = NSView()
        clipView.wantsLayer = true
        clipView.layer?.masksToBounds = true
        clipView.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(clipView)  // added BEFORE cluster so cluster paints on top

        // leadingStack inside clipView (no trailing constraint → overflows)
        leadingStack.translatesAutoresizingMaskIntoConstraints = false
        leadingStack.orientation = .horizontal
        leadingStack.spacing = pillGap
        leadingStack.alignment = .centerY
        leadingStack.setContentHuggingPriority(.required, for: .horizontal)
        clipView.addSubview(leadingStack)

        NSLayoutConstraint.activate([
            // cluster: right-aligned, vertically centered
            cluster.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -8),
            cluster.centerYAnchor.constraint(equalTo: cv.centerYAnchor),

            // clipView: leading to cv, trailing to cluster left edge
            clipView.leadingAnchor.constraint(equalTo: cv.leadingAnchor),
            clipView.trailingAnchor.constraint(equalTo: cluster.leadingAnchor, constant: -4),
            clipView.topAnchor.constraint(equalTo: cv.topAnchor),
            clipView.bottomAnchor.constraint(equalTo: cv.bottomAnchor),

            // leadingStack: left-pinned, centered, NO trailing constraint
            leadingStack.leadingAnchor.constraint(equalTo: clipView.leadingAnchor, constant: 8),
            leadingStack.centerYAnchor.constraint(equalTo: clipView.centerYAnchor),
            leadingStack.heightAnchor.constraint(equalToConstant: pillH),
        ])

        buildWorkspaceStrip(state: state, tall: false)
        applyWorkspaceState(state: state, tall: false)
    }

    // ── Tall layout ──────────────────────────────────────────────────────────

    func buildTallLayout(cv: NSView, state: BarState) {
        let rowH: CGFloat = barHeightTall / 2

        // Top row: cluster right-aligned
        let cluster = buildCluster(state: state)
        cluster.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(cluster)

        // Divider
        let divider = NSView()
        divider.wantsLayer = true
        divider.layer?.backgroundColor = NSColor(argb: 0x0FFFFFFF).cgColor
        divider.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(divider)

        // Bottom row: full-width pill strip (no clip, no truncation)
        leadingStack.translatesAutoresizingMaskIntoConstraints = false
        leadingStack.orientation = .horizontal
        leadingStack.spacing = pillGap + 1
        leadingStack.alignment = .centerY
        leadingStack.setContentHuggingPriority(.defaultLow, for: .horizontal)
        cv.addSubview(leadingStack)

        NSLayoutConstraint.activate([
            // Top row cluster
            cluster.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -8),
            cluster.centerYAnchor.constraint(equalTo: cv.topAnchor, constant: rowH / 2),

            // Divider at midpoint
            divider.leadingAnchor.constraint(equalTo: cv.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: cv.trailingAnchor),
            divider.heightAnchor.constraint(equalToConstant: 1),
            divider.topAnchor.constraint(equalTo: cv.topAnchor, constant: rowH),

            // Bottom row pill strip: full width
            leadingStack.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 8),
            leadingStack.trailingAnchor.constraint(lessThanOrEqualTo: cv.trailingAnchor, constant: -8),
            leadingStack.centerYAnchor.constraint(equalTo: cv.topAnchor, constant: rowH + rowH / 2),
            leadingStack.heightAnchor.constraint(equalToConstant: pillH),
        ])

        buildWorkspaceStrip(state: state, tall: true)
        applyWorkspaceState(state: state, tall: true)
    }

    // ── Workspace strip ──────────────────────────────────────────────────────

    func buildWorkspaceStrip(state: BarState, tall: Bool) {
        let monitorWs = state.monitorWorkspaces[monitorIndex]
        for ws in ALL_WS {
            if let monWs = monitorWs, !monWs.contains(ws) { continue }
            let pill = WorkspacePill(wsID: ws)
            pill.translatesAutoresizingMaskIntoConstraints = false
            pill.heightAnchor.constraint(equalToConstant: pillH).isActive = true
            wsPills[ws] = pill
            leadingStack.addArrangedSubview(pill)
        }
        applyWorkspaceState(state: state, tall: tall)
    }

    func applyWorkspaceState(state: BarState, tall: Bool) {
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

            let (idxStr, nameStr) = state.spansFor(ws: ws, tall: tall)

            if isFocused {
                pill.apply(bg: ACCENT, idxColor: PILL_IDX_ACT, nameColor: PILL_NAME_ACT,
                           idx: idxStr, name: nameStr, showDot: showDot, dotColor: dotColor,
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

    func buildCluster(state: BarState) -> NSView {
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

        // Service mode indicator
        if state.serviceMode {
            let pill = makeServicePill()
            pill.translatesAutoresizingMaskIntoConstraints = false
            serviceModeLabel = pill
            stack.addArrangedSubview(pill)
        }

        // App icon group
        if !state.apps.isEmpty {
            let group = buildAppIconGroup(state: state)
            group.translatesAutoresizingMaskIntoConstraints = false
            stack.addArrangedSubview(group)
        }

        // Spacer
        stack.addArrangedSubview(makeHSpacer(4))

        // Wifi (bare icon)
        buildWifi(into: stack)

        // Volume (bare icon+pct)
        buildVolume(into: stack)

        // Battery (bare icon+pct)
        buildBattery(into: stack)

        // Clock (accent-soft pill)
        buildClock(into: stack)

        return cluster
    }

    // ── App icon group ───────────────────────────────────────────────────────

    func buildAppIconGroup(state: BarState) -> NSView {
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

    func buildWifi(into stack: NSStackView) {
        let (ws, ic, _) = makeBareIconLabel(icon: "󰤨", iconColor: C_GREEN)
        wifiIcon = ic
        let click = ClickView(frame: .zero)
        click.translatesAutoresizingMaskIntoConstraints = false
        click.onPress = { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.network")!) }
        let wrap = NSView()
        wrap.translatesAutoresizingMaskIntoConstraints = false
        ws.translatesAutoresizingMaskIntoConstraints = false
        wrap.addSubview(ws); wrap.addSubview(click)
        NSLayoutConstraint.activate([
            ws.leadingAnchor.constraint(equalTo: wrap.leadingAnchor),
            ws.trailingAnchor.constraint(equalTo: wrap.trailingAnchor),
            ws.topAnchor.constraint(equalTo: wrap.topAnchor),
            ws.bottomAnchor.constraint(equalTo: wrap.bottomAnchor),
            click.leadingAnchor.constraint(equalTo: wrap.leadingAnchor),
            click.trailingAnchor.constraint(equalTo: wrap.trailingAnchor),
            click.topAnchor.constraint(equalTo: wrap.topAnchor),
            click.bottomAnchor.constraint(equalTo: wrap.bottomAnchor),
        ])
        stack.addArrangedSubview(wrap)
        updateWifi()
    }

    func buildVolume(into stack: NSStackView) {
        let (ws, ic, lbl) = makeBareIconLabel(icon: "󰕾", iconColor: C_BLUE)
        volIcon = ic; volLabel = lbl
        let click = ClickView(frame: .zero)
        click.translatesAutoresizingMaskIntoConstraints = false
        click.onPress = { [weak self] in self?.toggleVolumePopup() }
        let wrap = NSView()
        wrap.translatesAutoresizingMaskIntoConstraints = false
        ws.translatesAutoresizingMaskIntoConstraints = false
        wrap.addSubview(ws); wrap.addSubview(click)
        NSLayoutConstraint.activate([
            ws.leadingAnchor.constraint(equalTo: wrap.leadingAnchor),
            ws.trailingAnchor.constraint(equalTo: wrap.trailingAnchor),
            ws.topAnchor.constraint(equalTo: wrap.topAnchor),
            ws.bottomAnchor.constraint(equalTo: wrap.bottomAnchor),
            click.leadingAnchor.constraint(equalTo: wrap.leadingAnchor),
            click.trailingAnchor.constraint(equalTo: wrap.trailingAnchor),
            click.topAnchor.constraint(equalTo: wrap.topAnchor),
            click.bottomAnchor.constraint(equalTo: wrap.bottomAnchor),
        ])
        stack.addArrangedSubview(wrap)
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
        let click = ClickView(frame: .zero)
        click.translatesAutoresizingMaskIntoConstraints = false
        click.onPress = { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.battery")!) }
        let wrap = NSView()
        wrap.translatesAutoresizingMaskIntoConstraints = false
        ws.translatesAutoresizingMaskIntoConstraints = false
        wrap.addSubview(ws); wrap.addSubview(click)
        NSLayoutConstraint.activate([
            ws.leadingAnchor.constraint(equalTo: wrap.leadingAnchor),
            ws.trailingAnchor.constraint(equalTo: wrap.trailingAnchor),
            ws.topAnchor.constraint(equalTo: wrap.topAnchor),
            ws.bottomAnchor.constraint(equalTo: wrap.bottomAnchor),
            click.leadingAnchor.constraint(equalTo: wrap.leadingAnchor),
            click.trailingAnchor.constraint(equalTo: wrap.trailingAnchor),
            click.topAnchor.constraint(equalTo: wrap.topAnchor),
            click.bottomAnchor.constraint(equalTo: wrap.bottomAnchor),
        ])
        stack.addArrangedSubview(wrap)
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

    func updateWifi() {
        let ssid = CWWiFiClient.shared().interface()?.ssid()
        if ssid != nil {
            wifiIcon?.stringValue = "󰤨"; wifiIcon?.textColor = NSColor(argb: C_GREEN)
        } else {
            wifiIcon?.stringValue = "󰤭"; wifiIcon?.textColor = NSColor(argb: C_RED)
        }
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

    func applyRefresh(state: BarState) {
        applyWorkspaceState(state: state, tall: state.barTall)
        updateClock(); updateBattery(); updateWifi(); updateVolume()
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

        let muteBtn = ClickView(frame: .zero)
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
// MARK: – BarController
// ──────────────────────────────────────────────────────────────────────────────

class BarController: NSObject {
    var windows: [BarWindow] = []
    var clockTimer: Timer?; var batteryTimer: Timer?; var wifiTimer: Timer?; var pulseTimer: Timer?
    var pulseBright = true; var lastState = BarState()

    func start() { writePIDFile(); buildWindows(); installSignalSource(); startTimers() }

    func writePIDFile() {
        let path = NSHomeDirectory() + "/.config/hub/status_bar.pid"
        try? "\(ProcessInfo.processInfo.processIdentifier)\n".write(toFile: path, atomically: true, encoding: .utf8)
    }

    func buildWindows() {
        windows.forEach { $0.close() }; windows.removeAll()
        DispatchQueue.global(qos: .userInitiated).async {
            let state = BarState.snapshot()
            let sortedScreens = NSScreen.screens.sorted { $0.frame.minX < $1.frame.minX }
            let monitorIDs = state.monitorWorkspaces.keys.sorted()
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.lastState = state
                for (i, screen) in sortedScreens.enumerated() {
                    let w = BarWindow(screen: screen)
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
                        w.buildContents(state: state); w.orderFrontRegardless()
                    } else {
                        w.applyRefresh(state: state)
                    }
                }
            }
        }
    }

    func startTimers() {
        clockTimer   = Timer.scheduledTimer(withTimeInterval: 10,  repeats: true) { [weak self] _ in self?.windows.forEach { $0.updateClock() } }
        batteryTimer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in self?.windows.forEach { $0.updateBattery() } }
        wifiTimer    = Timer.scheduledTimer(withTimeInterval: 30,  repeats: true) { [weak self] _ in self?.windows.forEach { $0.updateWifi() } }
        pulseTimer   = Timer.scheduledTimer(withTimeInterval: 0.75, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.pulseBright = !self.pulseBright
            let bright = self.pulseBright; let state = self.lastState
            for w in self.windows {
                for ws in state.claudeActive { if let pill = w.wsPills[ws] { pill.updatePulse(bright: bright) } }
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification,
            object: nil, queue: .main) { [weak self] _ in self?.windows.forEach { $0.updateBattery(); $0.updateWifi() } }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in self?.buildWindows() }
    }
}

// ──────────────────────────────────────────────────────────────────────────────
// MARK: – Entry point
// ──────────────────────────────────────────────────────────────────────────────

let pidFile = NSHomeDirectory() + "/.config/hub/status_bar.pid"
if let existing = try? String(contentsOfFile: pidFile, encoding: .utf8),
   let existingPID = Int(existing.trimmingCharacters(in: .whitespacesAndNewlines)),
   existingPID != Int(ProcessInfo.processInfo.processIdentifier) {
    let alive = kill(pid_t(existingPID), 0) == 0
    if alive { fputs("status_bar: another instance already running (pid \(existingPID))\n", stderr); exit(1) }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = BarController()
    func applicationDidFinishLaunching(_ n: Notification) { controller.start() }
}

let delegate = AppDelegate()
app.delegate = delegate
app.run()
