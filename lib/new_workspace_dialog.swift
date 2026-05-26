import Cocoa

// New Workspace dialog for hub.
// Keyboard-first: every action reachable via keyboard, also clickable with mouse.
// Writes result to /tmp/hub-new-workspace as tab-separated:
//   name\tpath\troot_repo\tworkspace_id
// or "cancel" if cancelled.

let resultPath = "/tmp/hub-new-workspace"
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let screen = NSScreen.main ?? NSScreen.screens[0]
let sf = screen.frame

// --- Colors (matching hub palette) ---
let bgColor = NSColor(white: 0.08, alpha: 0.93)
let itemBg = NSColor(red: 0.21, green: 0.22, blue: 0.27, alpha: 1)
let itemBg2 = NSColor(red: 0.25, green: 0.27, blue: 0.31, alpha: 1)
let textWhite = NSColor(red: 0.89, green: 0.89, blue: 0.89, alpha: 1)
let dimWhite = NSColor(white: 1, alpha: 0.45)
let accentBlue = NSColor(red: 0.20, green: 0.45, blue: 0.85, alpha: 1)
let greenColor = NSColor(red: 0.62, green: 0.82, blue: 0.45, alpha: 1)

// --- Window ---
class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

let dialogW: CGFloat = min(sf.width * 0.45, 600)
let win = KeyableWindow(contentRect: NSRect(x: 0, y: 0, width: dialogW, height: 100),
                        styleMask: .borderless, backing: .buffered, defer: false)
win.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)
win.backgroundColor = bgColor
win.isOpaque = false
win.hasShadow = true
win.collectionBehavior = [.canJoinAllSpaces, .stationary]

let cv = win.contentView!
cv.wantsLayer = true
cv.layer?.cornerRadius = 18
cv.layer?.masksToBounds = true

// --- Backdrop ---
let backdrop: NSWindow = {
    let w = NSWindow(contentRect: sf, styleMask: .borderless, backing: .buffered, defer: false)
    w.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
    w.backgroundColor = NSColor(white: 0, alpha: 0.85)
    w.isOpaque = false
    w.hasShadow = false
    w.collectionBehavior = [.canJoinAllSpaces, .stationary]
    w.alphaValue = 0
    w.orderFrontRegardless()
    return w
}()

// --- Result writing ---
func writeResult(_ value: String) {
    try? value.write(toFile: resultPath, atomically: true, encoding: .utf8)
}

func dismiss() {
    NSAnimationContext.runAnimationGroup({ ctx in
        ctx.duration = 0.25
        win.animator().alphaValue = 0
        backdrop.animator().alphaValue = 0
    }, completionHandler: {
        NSApp.terminate(nil)
    })
}

func cancelAndDismiss() {
    writeResult("cancel")
    dismiss()
}

// --- Helpers ---
func makeLabel(_ s: String) -> NSTextField {
    let f = NSTextField(labelWithString: s)
    f.translatesAutoresizingMaskIntoConstraints = false
    f.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
    f.textColor = dimWhite
    return f
}

class PaddedCell: NSTextFieldCell {
    private func paddedRect(_ rect: NSRect) -> NSRect {
        var r = super.drawingRect(forBounds: rect)
        r.origin.x += 8; r.size.width -= 16
        let h = r.size.height
        let textH = cellSize(forBounds: rect).height
        r.origin.y += max(0, (h - textH) / 2)
        r.size.height = min(h, textH)
        return r
    }
    override func drawingRect(forBounds rect: NSRect) -> NSRect { paddedRect(rect) }
    override func edit(withFrame rect: NSRect, in view: NSView, editor: NSText, delegate: Any?, event: NSEvent?) {
        super.edit(withFrame: paddedRect(rect), in: view, editor: editor, delegate: delegate, event: event)
    }
    override func select(withFrame rect: NSRect, in view: NSView, editor: NSText, delegate: Any?, start: Int, length: Int) {
        super.select(withFrame: paddedRect(rect), in: view, editor: editor, delegate: delegate, start: start, length: length)
    }
}

class StyledField: NSTextField {
    override func becomeFirstResponder() -> Bool {
        let r = super.becomeFirstResponder()
        if r, let tv = currentEditor() as? NSTextView {
            tv.selectedTextAttributes = [
                .backgroundColor: NSColor(white: 0.38, alpha: 1),
                .foregroundColor: NSColor.white,
            ]
            tv.insertionPointColor = .white
        }
        return r
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command) else { return super.performKeyEquivalent(with: event) }
        let target = window?.firstResponder
        switch event.charactersIgnoringModifiers ?? "" {
        case "a": return NSApp.sendAction(#selector(NSText.selectAll(_:)), to: target, from: self)
        case "c": return NSApp.sendAction(#selector(NSText.copy(_:)),      to: target, from: self)
        case "v": return NSApp.sendAction(#selector(NSStyledField.pasteStrippingNewlines(_:)), to: self, from: self)
        case "x": return NSApp.sendAction(#selector(NSText.cut(_:)),       to: target, from: self)
        default:  return super.performKeyEquivalent(with: event)
        }
    }
    @objc func pasteStrippingNewlines(_ sender: Any?) {
        guard let text = NSPasteboard.general.string(forType: .string) else { return }
        let cleaned = text.components(separatedBy: .newlines).joined()
        if let editor = currentEditor() as? NSTextView {
            editor.insertText(cleaned, replacementRange: editor.selectedRange())
        }
    }
}
private typealias NSStyledField = StyledField

func makeField(placeholder: String, value: String = "") -> NSTextField {
    let f = StyledField()
    f.cell = PaddedCell()
    f.translatesAutoresizingMaskIntoConstraints = false
    f.isEditable = true
    f.isBordered = false
    f.wantsLayer = true
    f.layer?.backgroundColor = itemBg.cgColor
    f.layer?.cornerRadius = 6
    f.textColor = .white
    f.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
    f.focusRingType = .none
    (f.cell as? NSTextFieldCell)?.placeholderAttributedString = NSAttributedString(
        string: placeholder,
        attributes: [.foregroundColor: NSColor(white: 1, alpha: 0.25),
                     .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)])
    f.stringValue = value
    return f
}

class CustomCheckbox: NSView {
    var isChecked: Bool { didSet { needsDisplay = true } }
    var label: String
    var fontSize: CGFloat

    init(label: String, checked: Bool, fontSize: CGFloat = 13) {
        self.label = label
        self.isChecked = checked
        self.fontSize = fontSize
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(toggle)))
    }
    required init?(coder: NSCoder) { fatalError() }

    @objc func toggle() { isChecked.toggle() }

    override func draw(_ dirtyRect: NSRect) {
        let boxSize: CGFloat = 16
        let boxY = (bounds.height - boxSize) / 2
        let boxRect = NSRect(x: 0, y: boxY, width: boxSize, height: boxSize)
        let path = NSBezierPath(roundedRect: boxRect, xRadius: 3, yRadius: 3)
        if isChecked {
            NSColor(red: 0.20, green: 0.45, blue: 0.85, alpha: 1).setFill()
            path.fill()
            let check = NSBezierPath()
            check.move(to: NSPoint(x: boxRect.minX + 3.5, y: boxRect.midY))
            check.line(to: NSPoint(x: boxRect.minX + 6.5, y: boxRect.minY + 3.5))
            check.line(to: NSPoint(x: boxRect.maxX - 3, y: boxRect.maxY - 3.5))
            check.lineWidth = 1.8
            check.lineCapStyle = .round
            check.lineJoinStyle = .round
            NSColor.white.setStroke()
            check.stroke()
        } else {
            NSColor(white: 0.08, alpha: 1).setFill()
            path.fill()
            NSColor(white: 1, alpha: 0.5).setStroke()
            path.lineWidth = 1.5
            path.stroke()
        }
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor(white: 1, alpha: 0.75),
            .font: NSFont.systemFont(ofSize: fontSize, weight: .regular),
        ]
        let str = NSAttributedString(string: label, attributes: attrs)
        str.draw(at: NSPoint(x: boxSize + 8, y: (bounds.height - str.size().height) / 2))
    }

    override var intrinsicContentSize: NSSize {
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: fontSize, weight: .regular)]
        let w = (label as NSString).size(withAttributes: attrs).width
        return NSSize(width: 16 + 8 + w, height: 22)
    }
}

func makeBtn(label: String, shortcut: String? = nil, bg: NSColor, fg: NSColor, bold: Bool = false) -> NSButton {
    let b = NSButton()
    b.translatesAutoresizingMaskIntoConstraints = false
    b.bezelStyle = .rounded
    b.isBordered = false
    b.wantsLayer = true
    b.layer?.backgroundColor = bg.cgColor
    b.layer?.cornerRadius = 8
    b.alignment = .center
    let weight: NSFont.Weight = bold ? .semibold : .medium
    let style = NSMutableParagraphStyle()
    style.alignment = .center
    let attr = NSMutableAttributedString()
    attr.append(NSAttributedString(string: label, attributes: [
        .foregroundColor: fg,
        .font: NSFont.systemFont(ofSize: 12, weight: weight),
        .paragraphStyle: style,
    ]))
    if let key = shortcut {
        attr.append(NSAttributedString(string: "  \(key)", attributes: [
            .foregroundColor: fg.withAlphaComponent(0.4),
            .font: NSFont.systemFont(ofSize: 9, weight: .medium),
            .paragraphStyle: style,
        ]))
    }
    b.attributedTitle = attr
    return b
}

func showFilePicker() -> String? {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.prompt = "Select"
    let savedWinLevel = win.level
    let savedBackdropLevel = backdrop.level
    win.level = .normal
    backdrop.level = .normal
    backdrop.alphaValue = 0
    let result = panel.runModal()
    win.level = savedWinLevel
    backdrop.level = savedBackdropLevel
    backdrop.alphaValue = 1
    win.makeKeyAndOrderFront(nil)
    app.activate(ignoringOtherApps: true)
    guard result == .OK, let url = panel.url else { return nil }
    return url.path
}

// --- Git helpers ---
func isGitRepo(_ path: String) -> Bool {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    p.arguments = ["-C", path, "rev-parse", "--git-dir"]
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    try? p.run()
    p.waitUntilExit()
    return p.terminationStatus == 0
}

func gitRepoRoot(_ path: String) -> String? {
    let p = Process()
    let pipe = Pipe()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    p.arguments = ["-C", path, "rev-parse", "--show-toplevel"]
    p.standardOutput = pipe
    p.standardError = FileHandle.nullDevice
    try? p.run()
    p.waitUntilExit()
    guard p.terminationStatus == 0 else { return nil }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
}

struct Worktree {
    let path: String
    let branch: String
    let isBare: Bool
    var color: String?
}

func loadSupersetConfig(_ repoRoot: String) -> [String: String]? {
    let filePath = (repoRoot as NSString).appendingPathComponent(".superset/config.json")
    guard let data = FileManager.default.contents(atPath: filePath),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
    var result: [String: String] = [:]
    for (key, val) in json {
        if let arr = val as? [String], let first = arr.first {
            result[key] = first
        } else if let str = val as? String {
            result[key] = str
        }
    }
    return result.isEmpty ? nil : result
}

func readWorktreeColor(_ worktreePath: String) -> String? {
    let envrcPath = (worktreePath as NSString).appendingPathComponent(".envrc.local")
    guard let content = try? String(contentsOfFile: envrcPath, encoding: .utf8) else { return nil }
    for line in content.components(separatedBy: "\n") {
        if line.contains("WORKTREE_COLOR=") {
            let parts = line.components(separatedBy: "WORKTREE_COLOR=")
            if parts.count > 1 {
                return parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
    }
    return nil
}

func listWorktrees(_ path: String) -> [Worktree] {
    let prune = Process()
    prune.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    prune.arguments = ["-C", path, "worktree", "prune"]
    prune.standardOutput = FileHandle.nullDevice
    prune.standardError = FileHandle.nullDevice
    try? prune.run()
    prune.waitUntilExit()

    let p = Process()
    let pipe = Pipe()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    p.arguments = ["-C", path, "worktree", "list", "--porcelain"]
    p.standardOutput = pipe
    p.standardError = FileHandle.nullDevice
    try? p.run()
    p.waitUntilExit()
    guard p.terminationStatus == 0 else { return [] }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    guard let output = String(data: data, encoding: .utf8) else { return [] }

    var worktrees: [Worktree] = []
    var curPath = ""
    var curBranch = ""
    var curBare = false
    for line in output.components(separatedBy: "\n") {
        if line.hasPrefix("worktree ") {
            if !curPath.isEmpty {
                worktrees.append(Worktree(path: curPath, branch: curBranch, isBare: curBare))
            }
            curPath = String(line.dropFirst(9))
            curBranch = ""
            curBare = false
        } else if line.hasPrefix("branch ") {
            let ref = String(line.dropFirst(7))
            curBranch = ref.components(separatedBy: "/").last ?? ref
        } else if line == "bare" {
            curBare = true
        }
    }
    if !curPath.isEmpty {
        worktrees.append(Worktree(path: curPath, branch: curBranch, isBare: curBare))
    }
    return worktrees
}

func listGitBranches(_ repoRoot: String) -> [String] {
    let p = Process()
    let pipe = Pipe()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    p.arguments = ["-C", repoRoot, "branch", "--format=%(refname:short)", "--sort=-committerdate"]
    p.standardOutput = pipe
    p.standardError = FileHandle.nullDevice
    try? p.run()
    p.waitUntilExit()
    guard p.terminationStatus == 0 else { return [] }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    guard let output = String(data: data, encoding: .utf8) else { return [] }
    return output.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
}

func createWorktree(repoRoot: String, name: String) -> (path: String?, error: String) {
    let checkBranch = Process()
    checkBranch.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    checkBranch.arguments = ["-C", repoRoot, "rev-parse", "--verify", "refs/heads/\(name)"]
    checkBranch.standardOutput = FileHandle.nullDevice
    checkBranch.standardError = FileHandle.nullDevice
    try? checkBranch.run()
    checkBranch.waitUntilExit()
    let branchExists = checkBranch.terminationStatus == 0

    let worktreesDir = (repoRoot as NSString).appendingPathComponent("worktrees")
    try? FileManager.default.createDirectory(atPath: worktreesDir, withIntermediateDirectories: true)
    let worktreePath = (worktreesDir as NSString).appendingPathComponent(name)

    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    if branchExists {
        p.arguments = ["-C", repoRoot, "worktree", "add", worktreePath, name]
    } else {
        p.arguments = ["-C", repoRoot, "worktree", "add", "-b", name, worktreePath]
    }
    p.standardOutput = FileHandle.nullDevice
    let stderrPipe = Pipe()
    p.standardError = stderrPipe
    try? p.run()
    p.waitUntilExit()
    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
    let stderrStr = String(data: stderrData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return p.terminationStatus == 0 ? (worktreePath, "") : (nil, stderrStr)
}

func lastPathComponent(_ path: String) -> String {
    (path as NSString).lastPathComponent
}

func nextWorkspaceID() -> String {
    let wsFile = NSString(string: "~/.config/hub/workspaces.json").expandingTildeInPath
    var usedIDs: Set<String> = []
    if let data = FileManager.default.contents(atPath: wsFile),
       let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
        for ws in arr {
            if let id = ws["workspace_id"] as? String { usedIDs.insert(id) }
        }
    }
    let allIDs = ["1","2","3","4","5","6","7","8","9",
                  "A","B","C","D","E","F","G","I","M","N","O","P","Q","R","S","T","U","V","W","X","Y","Z"]
    for id in allIDs {
        if !usedIDs.contains(id) { return id }
    }
    return "1"
}

// --- ANSI color parsing ---
func parseANSI(_ raw: String, baseFont: NSFont, baseColor: NSColor) -> NSAttributedString {
    let result = NSMutableAttributedString()
    var curColor = baseColor
    var curFont = baseFont
    let esc = Character("\u{1B}")
    var i = raw.startIndex
    var plain = ""
    while i < raw.endIndex {
        if raw[i] == esc {
            if !plain.isEmpty {
                result.append(NSAttributedString(string: plain, attributes: [
                    .foregroundColor: curColor, .font: curFont]))
                plain = ""
            }
            let next = raw.index(after: i)
            if next < raw.endIndex && raw[next] == "[" {
                var j = raw.index(after: next)
                var seq = ""
                while j < raw.endIndex && raw[j] != "m" {
                    seq.append(raw[j])
                    j = raw.index(after: j)
                }
                if j < raw.endIndex && raw[j] == "m" {
                    let codes = seq.split(separator: ";").compactMap { Int($0) }
                    for c in (codes.isEmpty ? [0] : codes) {
                        switch c {
                        case 0: curColor = baseColor; curFont = baseFont
                        case 1: curFont = NSFont.monospacedSystemFont(ofSize: baseFont.pointSize, weight: .bold)
                        case 31: curColor = NSColor(red: 0.99, green: 0.36, blue: 0.49, alpha: 1)
                        case 32: curColor = NSColor(red: 0.62, green: 0.82, blue: 0.45, alpha: 1)
                        case 33: curColor = NSColor(red: 0.91, green: 0.78, blue: 0.39, alpha: 1)
                        case 34: curColor = NSColor(red: 0.46, green: 0.80, blue: 0.88, alpha: 1)
                        case 35: curColor = NSColor(red: 0.70, green: 0.62, blue: 0.95, alpha: 1)
                        case 36: curColor = NSColor(red: 0.00, green: 0.82, blue: 1.00, alpha: 1)
                        default: break
                        }
                    }
                    i = raw.index(after: j)
                    continue
                }
            }
            plain.append(raw[i])
            i = raw.index(after: i)
        } else {
            plain.append(raw[i])
            i = raw.index(after: i)
        }
    }
    if !plain.isEmpty {
        result.append(NSAttributedString(string: plain, attributes: [
            .foregroundColor: curColor, .font: curFont]))
    }
    return result
}

// ============================================================================
// STATE MACHINE
// ============================================================================

var allSubviews: [NSView] = []
var currentKeyHandler: Any?

func clearContent() {
    for v in allSubviews { v.removeFromSuperview() }
    allSubviews.removeAll()
    cv.removeConstraints(cv.constraints)
    if let h = currentKeyHandler { NSEvent.removeMonitor(h); currentKeyHandler = nil }
}

func addView(_ v: NSView) {
    cv.addSubview(v)
    allSubviews.append(v)
}

func relayout() {
    cv.layoutSubtreeIfNeeded()
    let fittingSize = cv.fittingSize
    let finalH = max(fittingSize.height + 8, 120)
    let finalRect = NSRect(
        x: sf.midX - dialogW / 2,
        y: sf.midY - finalH / 2 + 80,
        width: dialogW,
        height: finalH
    )
    win.setFrame(finalRect, display: true, animate: win.isVisible)
}

// ============================================================================
// STEP 1: Pick Path
// ============================================================================

func removeFromRecentPaths(_ path: String) {
    let recentFile = NSString(string: "~/.config/hub/recent_repos.json").expandingTildeInPath
    guard let data = FileManager.default.contents(atPath: recentFile),
          var arr = try? JSONSerialization.jsonObject(with: data) as? [String] else { return }
    arr.removeAll { $0 == path }
    if let newData = try? JSONSerialization.data(withJSONObject: arr) {
        try? newData.write(to: URL(fileURLWithPath: recentFile))
    }
}

func recentPaths() -> [String] {
    let recentFile = NSString(string: "~/.config/hub/recent_repos.json").expandingTildeInPath
    if let data = FileManager.default.contents(atPath: recentFile),
       let arr = try? JSONSerialization.jsonObject(with: data) as? [String] {
        return arr.filter { !$0.isEmpty }
    }
    // Fall back to deriving from workspaces.json for backwards compatibility
    let wsFile = NSString(string: "~/.config/hub/workspaces.json").expandingTildeInPath
    guard let data = FileManager.default.contents(atPath: wsFile),
          let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
    var seen = Set<String>()
    var paths: [String] = []
    for ws in arr {
        let root = ws["root_repo"] as? String ?? ""
        let path = ws["path"] as? String ?? ""
        let repoPath = root.isEmpty ? path : root
        guard !repoPath.isEmpty, !seen.contains(repoPath) else { continue }
        seen.insert(repoPath)
        paths.append(repoPath)
    }
    return paths
}

func showNoRepoName() {
    clearContent()

    let titleLabel = NSTextField(labelWithString: "New Workspace")
    titleLabel.translatesAutoresizingMaskIntoConstraints = false
    titleLabel.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
    titleLabel.textColor = dimWhite
    addView(titleLabel)

    let nameLabel = makeLabel("NAME")
    addView(nameLabel)
    let nameField = makeField(placeholder: "workspace name")
    addView(nameField)

    let errorLabel = NSTextField(labelWithString: "")
    errorLabel.translatesAutoresizingMaskIntoConstraints = false
    errorLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
    errorLabel.textColor = NSColor(red: 0.99, green: 0.36, blue: 0.49, alpha: 1)
    addView(errorLabel)

    let createBtn = makeBtn(label: "CREATE", shortcut: "enter", bg: accentBlue, fg: .white, bold: true)
    addView(createBtn)
    let backBtn = makeBtn(label: "BACK", shortcut: "⌘[", bg: itemBg, fg: NSColor(white: 1, alpha: 0.75))
    addView(backBtn)
    let cancelBtn = makeBtn(label: "CANCEL", shortcut: "esc", bg: itemBg, fg: NSColor(white: 1, alpha: 0.75))
    addView(cancelBtn)

    NSLayoutConstraint.activate([
        titleLabel.topAnchor.constraint(equalTo: cv.topAnchor, constant: 24),
        titleLabel.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 28),
        nameLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 18),
        nameLabel.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 28),
        nameField.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 6),
        nameField.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 28),
        nameField.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -28),
        nameField.heightAnchor.constraint(equalToConstant: 36),
        errorLabel.topAnchor.constraint(equalTo: nameField.bottomAnchor, constant: 6),
        errorLabel.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 28),
        errorLabel.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -28),
        createBtn.topAnchor.constraint(equalTo: errorLabel.bottomAnchor, constant: 14),
        createBtn.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -28),
        createBtn.heightAnchor.constraint(equalToConstant: 34),
        createBtn.widthAnchor.constraint(equalToConstant: 100),
        backBtn.topAnchor.constraint(equalTo: createBtn.topAnchor),
        backBtn.trailingAnchor.constraint(equalTo: createBtn.leadingAnchor, constant: -10),
        backBtn.heightAnchor.constraint(equalToConstant: 34),
        backBtn.widthAnchor.constraint(equalToConstant: 100),
        cancelBtn.topAnchor.constraint(equalTo: createBtn.topAnchor),
        cancelBtn.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 28),
        cancelBtn.heightAnchor.constraint(equalToConstant: 34),
        cancelBtn.widthAnchor.constraint(equalToConstant: 100),
        cancelBtn.bottomAnchor.constraint(equalTo: cv.bottomAnchor, constant: -20),
    ])

    relayout()
    win.makeFirstResponder(nameField)

    class CreateAction: NSObject {
        let field: NSTextField
        let errLabel: NSTextField
        init(_ f: NSTextField, _ e: NSTextField) { field = f; errLabel = e }
        @objc func create(_ sender: Any) { doCreate() }
        func doCreate() {
            let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { errLabel.stringValue = "Enter a name"; return }
            showConfirmWorkspace(explicitName: name, path: "-", repoRoot: "", back: { showNoRepoName() })
        }
    }
    class BackAction: NSObject {
        @objc func back(_ sender: Any) { showPickPath() }
    }
    class CancelAction: NSObject {
        @objc func cancel(_ sender: Any) { cancelAndDismiss() }
    }

    let createAction = CreateAction(nameField, errorLabel)
    let backAction = BackAction()
    let cancelAction = CancelAction()
    createBtn.target = createAction; createBtn.action = #selector(CreateAction.create(_:))
    backBtn.target = backAction; backBtn.action = #selector(BackAction.back(_:))
    cancelBtn.target = cancelAction; cancelBtn.action = #selector(CancelAction.cancel(_:))
    objc_setAssociatedObject(createBtn, "a", createAction, .OBJC_ASSOCIATION_RETAIN)
    objc_setAssociatedObject(backBtn, "a", backAction, .OBJC_ASSOCIATION_RETAIN)
    objc_setAssociatedObject(cancelBtn, "a", cancelAction, .OBJC_ASSOCIATION_RETAIN)

    currentKeyHandler = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
        if event.keyCode == 53 { cancelAndDismiss(); return nil }
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers == "[" { showPickPath(); return nil }
        if event.keyCode == 36 { createAction.doCreate(); return nil }
        return event
    }
}

func showPickPath() {
    clearContent()

    let titleLabel = NSTextField(labelWithString: "New Workspace")
    titleLabel.translatesAutoresizingMaskIntoConstraints = false
    titleLabel.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
    titleLabel.textColor = dimWhite
    addView(titleLabel)

    let pathLabel = makeLabel("PATH (enter path or browse)")
    addView(pathLabel)
    let pathField = makeField(placeholder: "/path/to/repo")
    addView(pathField)

    let browseBtn = makeBtn(label: "BROWSE", shortcut: "tab", bg: NSColor(white: 0.22, alpha: 1), fg: NSColor(white: 1, alpha: 0.75))
    addView(browseBtn)
    let noRepoBtn = makeBtn(label: "NO REPO", shortcut: "⌘↵", bg: NSColor(white: 0.18, alpha: 1), fg: NSColor(white: 1, alpha: 0.45))
    addView(noRepoBtn)

    let errorLabel = NSTextField(labelWithString: "")
    errorLabel.translatesAutoresizingMaskIntoConstraints = false
    errorLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
    errorLabel.textColor = NSColor(red: 0.99, green: 0.36, blue: 0.49, alpha: 1)
    addView(errorLabel)

    // Recent paths
    let recent = recentPaths()
    var recentActions: [AnyObject] = []

    class RecentPathAction: NSObject {
        let path: String
        let errLabel: NSTextField
        weak var btn: NSButton?
        init(_ p: String, _ e: NSTextField) { path = p; errLabel = e }
        @objc func pick(_ sender: Any) {
            guard FileManager.default.fileExists(atPath: path) else {
                removeFromRecentPaths(path)
                btn?.isEnabled = false
                btn?.alphaValue = 0.3
                errLabel.stringValue = "Directory no longer exists: \(path)"
                return
            }
            handlePathSelected(path)
        }
    }

    class RemoveRecentAction: NSObject {
        let path: String
        init(_ p: String) { path = p }
        @objc func remove(_ sender: Any) {
            removeFromRecentPaths(path)
            showPickPath()
        }
    }

    var prevRecentAnchor: NSLayoutYAxisAnchor = errorLabel.bottomAnchor
    if !recent.isEmpty {
        let recentLabel = makeLabel("RECENT")
        addView(recentLabel)
        NSLayoutConstraint.activate([
            recentLabel.topAnchor.constraint(equalTo: errorLabel.bottomAnchor, constant: 14),
            recentLabel.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 28),
        ])
        prevRecentAnchor = recentLabel.bottomAnchor

        for (i, rp) in recent.prefix(15).enumerated() {
            let displayPath = (rp as NSString).abbreviatingWithTildeInPath

            let removeBtn = NSButton()
            removeBtn.translatesAutoresizingMaskIntoConstraints = false
            removeBtn.isBordered = false
            removeBtn.wantsLayer = true
            removeBtn.layer?.cornerRadius = 3
            removeBtn.attributedTitle = NSAttributedString(string: "✕", attributes: [
                .font: NSFont.systemFont(ofSize: 10, weight: .medium),
                .foregroundColor: NSColor(white: 1, alpha: 0.3),
            ])
            removeBtn.toolTip = "Remove from recent"
            let removeAction = RemoveRecentAction(rp)
            recentActions.append(removeAction)
            removeBtn.target = removeAction; removeBtn.action = #selector(RemoveRecentAction.remove(_:))
            objc_setAssociatedObject(removeBtn, "rm\(i)", removeAction, .OBJC_ASSOCIATION_RETAIN)
            addView(removeBtn)

            let btn = NSButton()
            btn.translatesAutoresizingMaskIntoConstraints = false
            btn.isBordered = false
            btn.wantsLayer = true
            btn.layer?.cornerRadius = 4
            btn.alignment = .left
            btn.attributedTitle = NSAttributedString(string: "  \(displayPath)", attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                .foregroundColor: NSColor(white: 1, alpha: 0.55),
            ])
            let action = RecentPathAction(rp, errorLabel)
            action.btn = btn
            recentActions.append(action)
            btn.target = action; btn.action = #selector(RecentPathAction.pick(_:))
            objc_setAssociatedObject(btn, "rp\(i)", action, .OBJC_ASSOCIATION_RETAIN)
            addView(btn)
            NSLayoutConstraint.activate([
                removeBtn.centerYAnchor.constraint(equalTo: btn.centerYAnchor),
                removeBtn.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -20),
                removeBtn.widthAnchor.constraint(equalToConstant: 20),
                removeBtn.heightAnchor.constraint(equalToConstant: 20),
                btn.topAnchor.constraint(equalTo: prevRecentAnchor, constant: 2),
                btn.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 20),
                btn.trailingAnchor.constraint(equalTo: removeBtn.leadingAnchor, constant: -4),
                btn.heightAnchor.constraint(equalToConstant: 26),
            ])
            prevRecentAnchor = btn.bottomAnchor
        }
    }

    let nextBtn = makeBtn(label: "NEXT", shortcut: "enter", bg: accentBlue, fg: .white, bold: true)
    addView(nextBtn)
    let cancelBtn = makeBtn(label: "CANCEL", shortcut: "esc", bg: itemBg, fg: NSColor(white: 1, alpha: 0.75))
    addView(cancelBtn)

    NSLayoutConstraint.activate([
        titleLabel.topAnchor.constraint(equalTo: cv.topAnchor, constant: 24),
        titleLabel.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 28),
        pathLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 18),
        pathLabel.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 28),
        pathField.topAnchor.constraint(equalTo: pathLabel.bottomAnchor, constant: 6),
        pathField.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 28),
        pathField.trailingAnchor.constraint(equalTo: browseBtn.leadingAnchor, constant: -10),
        pathField.heightAnchor.constraint(equalToConstant: 36),
        browseBtn.centerYAnchor.constraint(equalTo: pathField.centerYAnchor),
        browseBtn.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -28),
        browseBtn.heightAnchor.constraint(equalToConstant: 36),
        browseBtn.widthAnchor.constraint(equalToConstant: 100),
        noRepoBtn.topAnchor.constraint(equalTo: pathField.bottomAnchor, constant: 6),
        noRepoBtn.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -28),
        noRepoBtn.heightAnchor.constraint(equalToConstant: 24),
        noRepoBtn.widthAnchor.constraint(equalToConstant: 100),
        errorLabel.topAnchor.constraint(equalTo: pathField.bottomAnchor, constant: 6),
        errorLabel.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 28),
        errorLabel.trailingAnchor.constraint(equalTo: noRepoBtn.leadingAnchor, constant: -8),
        nextBtn.topAnchor.constraint(equalTo: prevRecentAnchor, constant: 14),
        nextBtn.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -28),
        nextBtn.heightAnchor.constraint(equalToConstant: 34),
        nextBtn.widthAnchor.constraint(equalToConstant: 100),
        cancelBtn.topAnchor.constraint(equalTo: nextBtn.topAnchor),
        cancelBtn.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 28),
        cancelBtn.heightAnchor.constraint(equalToConstant: 34),
        cancelBtn.widthAnchor.constraint(equalToConstant: 100),
        cancelBtn.bottomAnchor.constraint(equalTo: cv.bottomAnchor, constant: -20),
    ])

    relayout()
    win.makeFirstResponder(pathField)

    class BrowseAction: NSObject {
        let field: NSTextField
        init(_ f: NSTextField) { field = f }
        @objc func browse(_ sender: Any) {
            if let path = showFilePicker() { field.stringValue = path }
        }
    }
    class NextAction: NSObject {
        let field: NSTextField
        let errLabel: NSTextField
        init(_ f: NSTextField, _ e: NSTextField) { field = f; errLabel = e }
        @objc func next(_ sender: Any) { doNext() }
        func doNext() {
            let path = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let expanded = NSString(string: path).expandingTildeInPath
            guard !expanded.isEmpty else { errLabel.stringValue = "Enter a path"; return }
            guard FileManager.default.fileExists(atPath: expanded) else {
                errLabel.stringValue = "Directory does not exist"
                return
            }
            handlePathSelected(expanded)
        }
    }
    class NoRepoAction: NSObject {
        @objc func noRepo(_ sender: Any) { showNoRepoName() }
    }
    class CancelAction: NSObject {
        @objc func cancel(_ sender: Any) { cancelAndDismiss() }
    }

    let browseAction = BrowseAction(pathField)
    let nextAction = NextAction(pathField, errorLabel)
    let noRepoAction = NoRepoAction()
    let cancelAction = CancelAction()
    browseBtn.target = browseAction; browseBtn.action = #selector(BrowseAction.browse(_:))
    nextBtn.target = nextAction; nextBtn.action = #selector(NextAction.next(_:))
    noRepoBtn.target = noRepoAction; noRepoBtn.action = #selector(NoRepoAction.noRepo(_:))
    cancelBtn.target = cancelAction; cancelBtn.action = #selector(CancelAction.cancel(_:))
    objc_setAssociatedObject(browseBtn, "a", browseAction, .OBJC_ASSOCIATION_RETAIN)
    objc_setAssociatedObject(nextBtn, "a", nextAction, .OBJC_ASSOCIATION_RETAIN)
    objc_setAssociatedObject(noRepoBtn, "a", noRepoAction, .OBJC_ASSOCIATION_RETAIN)
    objc_setAssociatedObject(cancelBtn, "a", cancelAction, .OBJC_ASSOCIATION_RETAIN)

    currentKeyHandler = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
        if event.keyCode == 53 { cancelAndDismiss(); return nil }
        if event.keyCode == 36 {
            if event.modifierFlags.contains(.command) { showNoRepoName(); return nil }
            nextAction.doNext(); return nil
        }
        if event.keyCode == 48 { // Tab
            let cur = win.firstResponder
            let isField = (cur is NSTextView && pathField.currentEditor() === cur)
            if isField {
                win.makeFirstResponder(browseBtn)
            } else {
                win.makeFirstResponder(pathField)
            }
            return nil
        }
        return event
    }
}

func handlePathSelected(_ path: String) {
    guard isGitRepo(path) else {
        showNamingWorkspace(path: path, repoRoot: "", back: { showPickPath() })
        return
    }
    let root = gitRepoRoot(path) ?? path
    let manager = loadSupersetConfig(root)
    let worktrees = listWorktrees(root)
    showPickWorktree(repoRoot: root, worktrees: worktrees, manager: manager)
}

// ============================================================================
// STEP 2: Pick Worktree
// ============================================================================
func showPickWorktree(repoRoot: String, worktrees: [Worktree], manager: [String: String]? = nil) {
    clearContent()

    let titleLabel = NSTextField(labelWithString: "Select Worktree")
    titleLabel.translatesAutoresizingMaskIntoConstraints = false
    titleLabel.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
    titleLabel.textColor = dimWhite
    addView(titleLabel)

    let subtitle: String
    if worktrees.count <= 1 {
        subtitle = "Git repo — use as-is or create a worktree"
    } else {
        subtitle = "This repo has \(worktrees.count) worktrees"
    }
    let subtitleLabel = NSTextField(labelWithString: subtitle)
    subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
    subtitleLabel.font = NSFont.systemFont(ofSize: 12, weight: .regular)
    subtitleLabel.textColor = NSColor(white: 1, alpha: 0.3)
    addView(subtitleLabel)

    class WtAction: NSObject {
        let path: String
        let root: String
        let back: () -> Void
        init(_ p: String, _ r: String, _ back: @escaping () -> Void) {
            path = p; root = r; self.back = back
        }
        @objc func pick(_ sender: Any) {
            let color = readWorktreeColor(path)
            showNamingWorkspace(path: path, repoRoot: root, color: color, back: back)
        }
    }

    let backToHere = { showPickWorktree(repoRoot: repoRoot, worktrees: worktrees, manager: manager) }

    var prevAnchor: NSLayoutYAxisAnchor = subtitleLabel.bottomAnchor
    var actions: [WtAction] = []

    for (i, wt) in worktrees.enumerated() {
        let isRoot = (wt.path == repoRoot)
        let displayName = isRoot ? "\(lastPathComponent(wt.path)) (root)" : lastPathComponent(wt.path)
        let branchInfo = wt.branch.isEmpty ? "" : "  [\(wt.branch)]"

        let btn = NSButton()
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.isBordered = false
        btn.bezelStyle = .inline
        btn.wantsLayer = true
        btn.layer?.cornerRadius = 6
        btn.alignment = .left

        let attr = NSMutableAttributedString()
        attr.append(NSAttributedString(string: "  \(i + 1)  \(displayName)", attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 15, weight: .regular),
            .foregroundColor: textWhite,
        ]))
        attr.append(NSAttributedString(string: branchInfo, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: NSColor(white: 1, alpha: 0.35),
        ]))
        btn.attributedTitle = attr

        let action = WtAction(wt.path, repoRoot, backToHere)
        actions.append(action)
        btn.target = action; btn.action = #selector(WtAction.pick(_:))
        objc_setAssociatedObject(btn, "a\(i)", action, .OBJC_ASSOCIATION_RETAIN)

        addView(btn)
        NSLayoutConstraint.activate([
            btn.topAnchor.constraint(equalTo: prevAnchor, constant: prevAnchor === subtitleLabel.bottomAnchor ? 12 : 2),
            btn.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 8),
            btn.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -8),
            btn.heightAnchor.constraint(equalToConstant: 34),
        ])
        prevAnchor = btn.bottomAnchor
    }

    let sep = NSView()
    sep.translatesAutoresizingMaskIntoConstraints = false
    sep.wantsLayer = true
    sep.layer?.backgroundColor = NSColor(white: 1, alpha: 0.08).cgColor
    addView(sep)

    let newWtRow = NSButton()
    newWtRow.translatesAutoresizingMaskIntoConstraints = false
    newWtRow.isBordered = false
    newWtRow.bezelStyle = .inline
    newWtRow.wantsLayer = true
    newWtRow.layer?.cornerRadius = 6
    newWtRow.alignment = .left
    let newWtAttr = NSMutableAttributedString()
    newWtAttr.append(NSAttributedString(string: "  n  + new worktree", attributes: [
        .font: NSFont.monospacedSystemFont(ofSize: 15, weight: .regular),
        .foregroundColor: greenColor,
    ]))
    newWtRow.attributedTitle = newWtAttr
    addView(newWtRow)

    class NewWtAction: NSObject {
        let root: String
        let mgr: [String: String]?
        let wts: [Worktree]
        init(_ r: String, _ m: [String: String]?, _ w: [Worktree]) { root = r; mgr = m; wts = w }
        @objc func create(_ sender: Any) {
            showCreateWorktree(repoRoot: root, worktrees: wts, manager: mgr)
        }
    }
    let newWtAction = NewWtAction(repoRoot, manager, worktrees)
    newWtRow.target = newWtAction; newWtRow.action = #selector(NewWtAction.create(_:))
    objc_setAssociatedObject(newWtRow, "a", newWtAction, .OBJC_ASSOCIATION_RETAIN)

    let backBtn = makeBtn(label: "BACK", shortcut: "⌘[", bg: itemBg, fg: NSColor(white: 1, alpha: 0.75))
    addView(backBtn)
    let cancelBtn = makeBtn(label: "CANCEL", shortcut: "esc", bg: itemBg, fg: NSColor(white: 1, alpha: 0.75))
    addView(cancelBtn)
    class BackAction: NSObject {
        @objc func back(_ sender: Any) { showPickPath() }
    }
    class CancelAction: NSObject {
        @objc func cancel(_ sender: Any) { cancelAndDismiss() }
    }
    let backAction = BackAction()
    let cancelAction = CancelAction()
    backBtn.target = backAction; backBtn.action = #selector(BackAction.back(_:))
    cancelBtn.target = cancelAction; cancelBtn.action = #selector(CancelAction.cancel(_:))
    objc_setAssociatedObject(backBtn, "a", backAction, .OBJC_ASSOCIATION_RETAIN)
    objc_setAssociatedObject(cancelBtn, "a", cancelAction, .OBJC_ASSOCIATION_RETAIN)

    NSLayoutConstraint.activate([
        titleLabel.topAnchor.constraint(equalTo: cv.topAnchor, constant: 24),
        titleLabel.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 28),
        subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
        subtitleLabel.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 28),
        sep.topAnchor.constraint(equalTo: prevAnchor, constant: 6),
        sep.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 8),
        sep.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -8),
        sep.heightAnchor.constraint(equalToConstant: 1),
        newWtRow.topAnchor.constraint(equalTo: sep.bottomAnchor, constant: 2),
        newWtRow.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 8),
        newWtRow.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -8),
        newWtRow.heightAnchor.constraint(equalToConstant: 34),
        backBtn.topAnchor.constraint(equalTo: newWtRow.bottomAnchor, constant: 14),
        backBtn.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -28),
        backBtn.heightAnchor.constraint(equalToConstant: 34),
        backBtn.widthAnchor.constraint(equalToConstant: 100),
        cancelBtn.topAnchor.constraint(equalTo: backBtn.topAnchor),
        cancelBtn.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 28),
        cancelBtn.heightAnchor.constraint(equalToConstant: 34),
        cancelBtn.widthAnchor.constraint(equalToConstant: 100),
        cancelBtn.bottomAnchor.constraint(equalTo: cv.bottomAnchor, constant: -20),
    ])

    relayout()

    currentKeyHandler = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
        if event.keyCode == 53 { cancelAndDismiss(); return nil }
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers == "[" { showPickPath(); return nil }
        if let chars = event.charactersIgnoringModifiers, let digit = Int(chars),
           digit >= 1, digit <= worktrees.count {
            let wt = worktrees[digit - 1]
            let color = readWorktreeColor(wt.path)
            showNamingWorkspace(path: wt.path, repoRoot: repoRoot, color: color,
                                back: { showPickWorktree(repoRoot: repoRoot, worktrees: worktrees, manager: manager) })
            return nil
        }
        if event.charactersIgnoringModifiers == "n" {
            showCreateWorktree(repoRoot: repoRoot, worktrees: worktrees, manager: manager)
            return nil
        }
        return event
    }
}

// ============================================================================
// STEP 2b: Create New Worktree
// ============================================================================
func showCreateWorktree(repoRoot: String, worktrees: [Worktree], manager: [String: String]? = nil) {
    clearContent()

    let titleLabel = NSTextField(labelWithString: "Create New Worktree")
    titleLabel.translatesAutoresizingMaskIntoConstraints = false
    titleLabel.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
    titleLabel.textColor = dimWhite
    addView(titleLabel)

    let nameLabel = makeLabel("NAME (used for branch and worktree directory)")
    addView(nameLabel)
    let nameField = makeField(placeholder: "my-feature")
    addView(nameField)

    let errorLabel = NSTextField(labelWithString: "")
    errorLabel.translatesAutoresizingMaskIntoConstraints = false
    errorLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
    errorLabel.textColor = NSColor(red: 0.99, green: 0.36, blue: 0.49, alpha: 1)
    addView(errorLabel)

    // --- Branch list (scrollable, filterable) ---
    let branchesLabel = makeLabel("EXISTING BRANCHES")
    addView(branchesLabel)

    let scrollView = NSScrollView()
    scrollView.translatesAutoresizingMaskIntoConstraints = false
    scrollView.hasVerticalScroller = true
    scrollView.autohidesScrollers = false
    scrollView.drawsBackground = false
    scrollView.wantsLayer = true
    scrollView.layer?.backgroundColor = itemBg.cgColor
    scrollView.layer?.cornerRadius = 6
    scrollView.scrollerStyle = .legacy
    if let scroller = scrollView.verticalScroller {
        scroller.knobStyle = .light
    }
    addView(scrollView)

    let clipView = scrollView.contentView
    let stackContainer = FlippedView()
    stackContainer.translatesAutoresizingMaskIntoConstraints = false
    stackContainer.wantsLayer = false
    scrollView.documentView = stackContainer

    NSLayoutConstraint.activate([
        stackContainer.topAnchor.constraint(equalTo: clipView.topAnchor),
        stackContainer.leadingAnchor.constraint(equalTo: clipView.leadingAnchor),
        stackContainer.trailingAnchor.constraint(equalTo: clipView.trailingAnchor),
    ])

    let allBranches = listGitBranches(repoRoot)

    class BranchListManager: NSObject, NSTextFieldDelegate {
        let allBranches: [String]
        let container: NSView
        let field: NSTextField
        let repoRoot: String
        let errLabel: NSTextField
        let mgr: [String: String]?
        var debounceTimer: Timer?
        var branchButtons: [(branch: String, button: NSButton)] = []
        var highlightedIndex: Int = -1

        init(branches: [String], container: NSView, field: NSTextField,
             repoRoot: String, errLabel: NSTextField, mgr: [String: String]?) {
            self.allBranches = branches
            self.container = container
            self.field = field
            self.repoRoot = repoRoot
            self.errLabel = errLabel
            self.mgr = mgr
            super.init()
        }

        func controlTextDidChange(_ obj: Notification) {
            debounceTimer?.invalidate()
            let query = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            debounceTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: false) { [weak self] _ in
                guard let self = self else { return }
                DispatchQueue.global(qos: .userInteractive).async {
                    let filtered = query.isEmpty ? self.allBranches : self.allBranches.filter { $0.lowercased().contains(query) }
                    DispatchQueue.main.async { self.rebuildList(filtered: filtered) }
                }
            }
        }

        func rebuildList(filtered: [String]? = nil) {
            let branches = filtered ?? allBranches
            for sub in container.subviews { sub.removeFromSuperview() }
            branchButtons.removeAll()
            highlightedIndex = -1
            var prevAnchor: NSLayoutYAxisAnchor = container.topAnchor
            for (i, branch) in branches.enumerated() {
                let btn = NSButton()
                btn.translatesAutoresizingMaskIntoConstraints = false
                btn.isBordered = false
                btn.wantsLayer = true
                btn.layer?.cornerRadius = 4
                btn.alignment = .left
                btn.attributedTitle = NSAttributedString(string: "  \(branch)", attributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                    .foregroundColor: NSColor(white: 1, alpha: 0.65),
                ])
                let branchCopy = branch
                let action = BranchPickAction(branch: branchCopy, field: field, errLabel: errLabel,
                                              repoRoot: repoRoot, mgr: mgr, listMgr: self)
                btn.target = action; btn.action = #selector(BranchPickAction.pick(_:))
                objc_setAssociatedObject(btn, "ba\(i)", action, .OBJC_ASSOCIATION_RETAIN)
                container.addSubview(btn)
                branchButtons.append((branch: branch, button: btn))
                NSLayoutConstraint.activate([
                    btn.topAnchor.constraint(equalTo: prevAnchor, constant: i == 0 ? 4 : 1),
                    btn.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                    btn.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                    btn.heightAnchor.constraint(equalToConstant: 26),
                ])
                prevAnchor = btn.bottomAnchor
            }
            if !branches.isEmpty {
                prevAnchor.constraint(equalTo: container.bottomAnchor, constant: -4).isActive = true
            } else {
                container.topAnchor.constraint(equalTo: container.bottomAnchor).isActive = true
            }
            container.layoutSubtreeIfNeeded()
        }

        func moveHighlight(by delta: Int) {
            guard !branchButtons.isEmpty else { return }
            let newIndex = max(0, min(branchButtons.count - 1, highlightedIndex + delta))
            setHighlight(newIndex)
        }

        func setHighlight(_ index: Int) {
            if highlightedIndex >= 0 && highlightedIndex < branchButtons.count {
                let old = branchButtons[highlightedIndex].button
                old.layer?.backgroundColor = nil
                old.attributedTitle = NSAttributedString(string: "  \(branchButtons[highlightedIndex].branch)", attributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                    .foregroundColor: NSColor(white: 1, alpha: 0.65),
                ])
            }
            highlightedIndex = index
            if index >= 0 && index < branchButtons.count {
                let btn = branchButtons[index].button
                btn.layer?.backgroundColor = NSColor(white: 1, alpha: 0.08).cgColor
                btn.attributedTitle = NSAttributedString(string: "  \(branchButtons[index].branch)", attributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                    .foregroundColor: NSColor.white,
                ])
                (btn.superview?.enclosingScrollView)?.scrollToVisible(btn.frame)
            }
        }

        func selectHighlighted() {
            guard highlightedIndex >= 0 && highlightedIndex < branchButtons.count else { return }
            let branch = branchButtons[highlightedIndex].branch
            field.stringValue = branch
            errLabel.stringValue = ""
        }
    }

    class BranchPickAction: NSObject {
        let branch: String
        let field: NSTextField
        let errLabel: NSTextField
        let repoRoot: String
        let mgr: [String: String]?
        weak var listMgr: BranchListManager?
        init(branch: String, field: NSTextField, errLabel: NSTextField,
             repoRoot: String, mgr: [String: String]?, listMgr: BranchListManager) {
            self.branch = branch; self.field = field; self.errLabel = errLabel
            self.repoRoot = repoRoot; self.mgr = mgr; self.listMgr = listMgr
        }
        @objc func pick(_ sender: Any) {
            field.stringValue = branch
            errLabel.stringValue = ""
            win.makeFirstResponder(field)
            listMgr?.rebuildList()
        }
    }

    let listMgr = BranchListManager(branches: allBranches, container: stackContainer,
                                     field: nameField, repoRoot: repoRoot,
                                     errLabel: errorLabel, mgr: manager)
    nameField.delegate = listMgr
    objc_setAssociatedObject(nameField, "listMgr", listMgr, .OBJC_ASSOCIATION_RETAIN)

    // --- Buttons ---
    let createBtn = makeBtn(label: "CREATE", shortcut: "enter", bg: accentBlue, fg: .white, bold: true)
    addView(createBtn)
    let backBtn = makeBtn(label: "BACK", shortcut: "⌘[", bg: itemBg, fg: NSColor(white: 1, alpha: 0.75))
    addView(backBtn)
    let cancelBtn = makeBtn(label: "CANCEL", shortcut: "esc", bg: itemBg, fg: NSColor(white: 1, alpha: 0.75))
    addView(cancelBtn)

    NSLayoutConstraint.activate([
        titleLabel.topAnchor.constraint(equalTo: cv.topAnchor, constant: 24),
        titleLabel.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 28),
        nameLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 18),
        nameLabel.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 28),
        nameField.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 6),
        nameField.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 28),
        nameField.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -28),
        nameField.heightAnchor.constraint(equalToConstant: 36),
        errorLabel.topAnchor.constraint(equalTo: nameField.bottomAnchor, constant: 6),
        errorLabel.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 28),
        errorLabel.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -28),
        branchesLabel.topAnchor.constraint(equalTo: errorLabel.bottomAnchor, constant: 14),
        branchesLabel.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 28),
        scrollView.topAnchor.constraint(equalTo: branchesLabel.bottomAnchor, constant: 6),
        scrollView.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 28),
        scrollView.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -28),
        scrollView.heightAnchor.constraint(equalToConstant: 160),
        createBtn.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 14),
        createBtn.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -28),
        createBtn.heightAnchor.constraint(equalToConstant: 34),
        createBtn.widthAnchor.constraint(equalToConstant: 100),
        backBtn.topAnchor.constraint(equalTo: createBtn.topAnchor),
        backBtn.trailingAnchor.constraint(equalTo: createBtn.leadingAnchor, constant: -10),
        backBtn.heightAnchor.constraint(equalToConstant: 34),
        backBtn.widthAnchor.constraint(equalToConstant: 100),
        cancelBtn.topAnchor.constraint(equalTo: createBtn.topAnchor),
        cancelBtn.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 28),
        cancelBtn.heightAnchor.constraint(equalToConstant: 34),
        cancelBtn.widthAnchor.constraint(equalToConstant: 100),
        cancelBtn.bottomAnchor.constraint(equalTo: cv.bottomAnchor, constant: -20),
    ])

    relayout()
    listMgr.rebuildList()
    win.makeFirstResponder(nameField)

    let backToHere = { showCreateWorktree(repoRoot: repoRoot, worktrees: worktrees, manager: manager) }
    let backToParent = { showPickWorktree(repoRoot: repoRoot, worktrees: worktrees, manager: manager) }

    class CreateAction: NSObject {
        let root: String
        let field: NSTextField
        let errLabel: NSTextField
        let mgr: [String: String]?
        let back: () -> Void
        init(_ r: String, _ f: NSTextField, _ e: NSTextField, _ m: [String: String]?, _ back: @escaping () -> Void) {
            root = r; field = f; errLabel = e; mgr = m; self.back = back
        }
        @objc func create(_ sender: Any) { doCreate() }
        func doCreate() {
            let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { errLabel.stringValue = "Name cannot be empty"; return }
            let existing = listWorktrees(root)
            if let match = existing.first(where: { lastPathComponent($0.path) == name }) {
                let color = readWorktreeColor(match.path)
                showNamingWorkspace(path: match.path, repoRoot: root, color: color, back: back)
                return
            }
            let worktreesDir = (root as NSString).appendingPathComponent("worktrees")
            let expectedPath = (worktreesDir as NSString).appendingPathComponent(name)
            showNamingWorkspace(path: expectedPath, repoRoot: root, setupCmd: mgr?["setup"], pendingWorktreeName: name, back: back)
        }
    }
    class BackAction: NSObject {
        let back: () -> Void
        init(_ back: @escaping () -> Void) { self.back = back }
        @objc func goBack(_ sender: Any) { back() }
    }
    class CancelAction: NSObject {
        @objc func cancel(_ sender: Any) { cancelAndDismiss() }
    }
    let createAction = CreateAction(repoRoot, nameField, errorLabel, manager, backToHere)
    let backAction = BackAction(backToParent)
    let cancelAction = CancelAction()
    createBtn.target = createAction; createBtn.action = #selector(CreateAction.create(_:))
    backBtn.target = backAction; backBtn.action = #selector(BackAction.goBack(_:))
    cancelBtn.target = cancelAction; cancelBtn.action = #selector(CancelAction.cancel(_:))
    objc_setAssociatedObject(createBtn, "a", createAction, .OBJC_ASSOCIATION_RETAIN)
    objc_setAssociatedObject(backBtn, "a", backAction, .OBJC_ASSOCIATION_RETAIN)
    objc_setAssociatedObject(cancelBtn, "a", cancelAction, .OBJC_ASSOCIATION_RETAIN)

    currentKeyHandler = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
        if event.keyCode == 53 { cancelAndDismiss(); return nil }
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers == "[" { backToParent(); return nil }
        if event.keyCode == 36 { createAction.doCreate(); return nil }
        // Arrow keys navigate the branch list
        if event.keyCode == 125 { listMgr.moveHighlight(by: 1); return nil }  // down
        if event.keyCode == 126 { listMgr.moveHighlight(by: -1); return nil } // up
        // Tab selects highlighted branch
        if event.keyCode == 48 {
            if listMgr.highlightedIndex >= 0 {
                listMgr.selectHighlighted()
                listMgr.highlightedIndex = -1
                listMgr.rebuildList()
            }
            return nil
        }
        return event
    }
}

// ============================================================================
// STEP 3b: Creating Worktree Spinner (after confirmation)
// ============================================================================
func showCreatingWorktreeAndFinish(repoRoot: String, name: String, result confirmedResult: String) {
    clearContent()

    let titleLabel = NSTextField(labelWithString: "Creating Worktree")
    titleLabel.translatesAutoresizingMaskIntoConstraints = false
    titleLabel.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
    titleLabel.textColor = dimWhite
    addView(titleLabel)

    let spinner = NSProgressIndicator()
    spinner.translatesAutoresizingMaskIntoConstraints = false
    spinner.style = .spinning
    spinner.controlSize = .large
    spinner.appearance = NSAppearance(named: .darkAqua)
    spinner.startAnimation(nil)
    addView(spinner)

    let statusLabel = NSTextField(wrappingLabelWithString: "Running git worktree add...")
    statusLabel.translatesAutoresizingMaskIntoConstraints = false
    statusLabel.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    statusLabel.textColor = NSColor(white: 1, alpha: 0.5)
    statusLabel.alignment = .center
    addView(statusLabel)

    NSLayoutConstraint.activate([
        titleLabel.topAnchor.constraint(equalTo: cv.topAnchor, constant: 24),
        titleLabel.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 28),
        spinner.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 24),
        spinner.centerXAnchor.constraint(equalTo: cv.centerXAnchor),
        statusLabel.topAnchor.constraint(equalTo: spinner.bottomAnchor, constant: 16),
        statusLabel.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 28),
        statusLabel.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -28),
        statusLabel.bottomAnchor.constraint(equalTo: cv.bottomAnchor, constant: -24),
    ])

    relayout()

    DispatchQueue.global(qos: .userInitiated).async {
        let wtResult = createWorktree(repoRoot: repoRoot, name: name)
        DispatchQueue.main.async {
            guard wtResult.path != nil else {
                let errMsg = wtResult.error.isEmpty ? "Failed to create worktree" : "Failed to create worktree:\n\(wtResult.error)"
                statusLabel.stringValue = errMsg
                statusLabel.textColor = NSColor(red: 0.99, green: 0.36, blue: 0.49, alpha: 1)
                spinner.stopAnimation(nil)
                currentKeyHandler = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    if event.keyCode == 53 { cancelAndDismiss(); return nil }
                    return event
                }
                return
            }
            writeResult(confirmedResult)
            dismiss()
        }
    }
}

// ============================================================================
// STEP 3: Confirm — show app checkboxes then write result
// ============================================================================
func loadAppNames() -> [String] {
    let p = NSString(string: "~/.config/hub/apps.json").expandingTildeInPath
    guard let data = FileManager.default.contents(atPath: p),
          let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
    else { return [] }
    return arr.compactMap { $0["name"] as? String }
}

func showNamingWorkspace(path: String, repoRoot: String, color: String? = nil, setupCmd: String? = nil, pendingWorktreeName: String? = nil, back: (() -> Void)? = nil) {
    showConfirmWorkspace(path: path, repoRoot: repoRoot, color: color, setupCmd: setupCmd, pendingWorktreeName: pendingWorktreeName, back: back)
}

func showConfirmWorkspace(
    explicitName: String? = nil,
    path: String,
    repoRoot: String,
    color: String? = nil,
    setupCmd: String? = nil,
    pendingWorktreeName: String? = nil,
    back: (() -> Void)? = nil
) {
    clearContent()

    let wsName = explicitName ?? lastPathComponent(path)
    let wsID = nextWorkspaceID()
    let appNames = loadAppNames()

    let titleLabel = NSTextField(labelWithString: "Create Workspace")
    titleLabel.translatesAutoresizingMaskIntoConstraints = false
    titleLabel.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
    titleLabel.textColor = dimWhite
    addView(titleLabel)

    let nameField = makeField(placeholder: "workspace name", value: wsName)
    addView(nameField)

    let nameErrorLabel = NSTextField(labelWithString: "")
    nameErrorLabel.translatesAutoresizingMaskIntoConstraints = false
    nameErrorLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
    nameErrorLabel.textColor = NSColor(red: 0.99, green: 0.36, blue: 0.49, alpha: 1)
    addView(nameErrorLabel)

    var prevAnchor: NSLayoutYAxisAnchor = nameErrorLabel.bottomAnchor

    if path != "-" {
        let abbreviated = (path as NSString).abbreviatingWithTildeInPath
        let pathLabel = NSTextField(labelWithString: abbreviated)
        pathLabel.translatesAutoresizingMaskIntoConstraints = false
        pathLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        pathLabel.textColor = dimWhite
        pathLabel.lineBreakMode = .byTruncatingMiddle
        addView(pathLabel)
        NSLayoutConstraint.activate([
            pathLabel.topAnchor.constraint(equalTo: nameField.bottomAnchor, constant: 4),
            pathLabel.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 28),
            pathLabel.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -28),
            nameErrorLabel.topAnchor.constraint(equalTo: pathLabel.bottomAnchor, constant: 2),
        ])
    } else {
        nameErrorLabel.topAnchor.constraint(equalTo: nameField.bottomAnchor, constant: 4).isActive = true
    }

    var checkboxes: [CustomCheckbox] = []

    if !appNames.isEmpty {
        let appsLabel = makeLabel("OPEN ON CREATION")
        addView(appsLabel)
        NSLayoutConstraint.activate([
            appsLabel.topAnchor.constraint(equalTo: prevAnchor, constant: 20),
            appsLabel.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 28),
        ])
        prevAnchor = appsLabel.bottomAnchor

        for name in appNames {
            let cb = CustomCheckbox(label: name, checked: true)
            addView(cb)
            NSLayoutConstraint.activate([
                cb.topAnchor.constraint(equalTo: prevAnchor, constant: 10),
                cb.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 28),
            ])
            prevAnchor = cb.bottomAnchor
            checkboxes.append(cb)
        }
    }

    // --- Optional Claude prompt ---
    let promptLabel = makeLabel("CLAUDE PROMPT (optional — leave empty to skip)")
    addView(promptLabel)
    NSLayoutConstraint.activate([
        promptLabel.topAnchor.constraint(equalTo: prevAnchor, constant: 20),
        promptLabel.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 28),
    ])

    let (promptScroll, promptView) = makePromptTextView()
    addView(promptScroll)
    NSLayoutConstraint.activate([
        promptScroll.topAnchor.constraint(equalTo: promptLabel.bottomAnchor, constant: 6),
        promptScroll.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 28),
        promptScroll.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -28),
        promptScroll.heightAnchor.constraint(equalToConstant: 64),
    ])
    prevAnchor = promptScroll.bottomAnchor

    // Wire Tab key view chain: name field → prompt text view → name field.
    // NSTextView isn't auto-registered; explicit nextKeyView is required.
    nameField.nextKeyView = promptView
    promptView.nextKeyView = nameField

    let createBtn = makeBtn(label: "CREATE", shortcut: "enter", bg: accentBlue, fg: .white, bold: true)
    addView(createBtn)
    let cancelBtn = makeBtn(label: "CANCEL", shortcut: "esc", bg: itemBg, fg: NSColor(white: 1, alpha: 0.75))
    addView(cancelBtn)
    var backBtn: NSButton? = nil
    if back != nil {
        let b = makeBtn(label: "BACK", shortcut: "⌘[", bg: itemBg, fg: NSColor(white: 1, alpha: 0.75))
        addView(b)
        backBtn = b
    }

    var buttonConstraints: [NSLayoutConstraint] = [
        titleLabel.topAnchor.constraint(equalTo: cv.topAnchor, constant: 24),
        titleLabel.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 28),
        nameField.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
        nameField.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 28),
        nameField.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -28),
        nameField.heightAnchor.constraint(equalToConstant: 36),
        nameErrorLabel.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 28),
        nameErrorLabel.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -28),
        createBtn.topAnchor.constraint(equalTo: prevAnchor, constant: 20),
        createBtn.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -28),
        createBtn.heightAnchor.constraint(equalToConstant: 34),
        createBtn.widthAnchor.constraint(equalToConstant: 100),
        cancelBtn.topAnchor.constraint(equalTo: createBtn.topAnchor),
        cancelBtn.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 28),
        cancelBtn.heightAnchor.constraint(equalToConstant: 34),
        cancelBtn.widthAnchor.constraint(equalToConstant: 100),
        cancelBtn.bottomAnchor.constraint(equalTo: cv.bottomAnchor, constant: -20),
    ]
    if let b = backBtn {
        buttonConstraints.append(contentsOf: [
            b.topAnchor.constraint(equalTo: createBtn.topAnchor),
            b.trailingAnchor.constraint(equalTo: createBtn.leadingAnchor, constant: -10),
            b.heightAnchor.constraint(equalToConstant: 34),
            b.widthAnchor.constraint(equalToConstant: 100),
        ])
    }
    NSLayoutConstraint.activate(buttonConstraints)

    relayout()

    class ConfirmAction: NSObject {
        let wsID: String
        let nameField: NSTextField
        let nameErrLabel: NSTextField
        let path: String
        let repoRoot: String
        let color: String?
        let setupCmd: String?
        let pendingWorktreeName: String?
        let checkboxes: [CustomCheckbox]
        let promptView: NSTextView
        init(_ id: String, _ nf: NSTextField, _ ne: NSTextField, _ p: String, _ r: String, _ c: String?, _ s: String?, _ wt: String?, _ cbs: [CustomCheckbox], _ pv: NSTextView) {
            wsID = id; nameField = nf; nameErrLabel = ne; path = p; repoRoot = r; color = c; setupCmd = s; pendingWorktreeName = wt; checkboxes = cbs; promptView = pv
        }
        @objc func confirm(_ sender: Any) { doConfirm() }
        func doConfirm() {
            let wsName = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !wsName.isEmpty else { nameErrLabel.stringValue = "Enter a name"; return }
            nameErrLabel.stringValue = ""
            var checkedSlots: [String] = []
            for (i, cb) in checkboxes.enumerated() {
                if cb.isChecked { checkedSlots.append("\(i + 1)") }
            }
            let appsField = checkedSlots.isEmpty ? "-" : checkedSlots.joined(separator: ",")
            // Base64-encode the prompt so newlines/tabs survive the
            // tab-delimited result format on the shell side.
            let promptText = promptView.string.trimmingCharacters(in: .whitespacesAndNewlines)
            let promptB64 = promptText.isEmpty
                ? ""
                : (promptText.data(using: .utf8)?.base64EncodedString() ?? "")
            var result = "\(wsName)\t\(path)\t\(repoRoot.isEmpty ? "-" : repoRoot)\t\(wsID)"
            result += "\t\(color ?? "-")"
            result += "\t\(setupCmd ?? "-")"
            result += "\t\(appsField)"
            result += "\t\(promptB64)"
            if let wtName = pendingWorktreeName {
                showCreatingWorktreeAndFinish(repoRoot: repoRoot, name: wtName, result: result)
            } else {
                writeResult(result)
                dismiss()
            }
        }
    }
    class CancelAction: NSObject {
        @objc func cancel(_ sender: Any) { cancelAndDismiss() }
    }
    class BackAction: NSObject {
        let back: () -> Void
        init(_ back: @escaping () -> Void) { self.back = back }
        @objc func goBack(_ sender: Any) { back() }
    }

    let confirmAction = ConfirmAction(wsID, nameField, nameErrorLabel, path, repoRoot, color, setupCmd, pendingWorktreeName, checkboxes, promptView)
    let cancelAction = CancelAction()
    createBtn.target = confirmAction; createBtn.action = #selector(ConfirmAction.confirm(_:))
    cancelBtn.target = cancelAction; cancelBtn.action = #selector(CancelAction.cancel(_:))
    objc_setAssociatedObject(createBtn, "a", confirmAction, .OBJC_ASSOCIATION_RETAIN)
    objc_setAssociatedObject(cancelBtn, "a", cancelAction, .OBJC_ASSOCIATION_RETAIN)
    if let b = backBtn, let backFn = back {
        let backAction = BackAction(backFn)
        b.target = backAction; b.action = #selector(BackAction.goBack(_:))
        objc_setAssociatedObject(b, "a", backAction, .OBJC_ASSOCIATION_RETAIN)
    }

    win.makeFirstResponder(nameField)

    currentKeyHandler = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
        if event.keyCode == 53 { cancelAndDismiss(); return nil }
        if let backFn = back,
           event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers == "[" { backFn(); return nil }
        if event.keyCode == 36 {
            // Enter inside the prompt text view inserts a newline; Cmd+Enter
            // (or Enter from any other field) submits the form.
            let promptHasFocus = (win.firstResponder as? NSTextView) === promptView
            if promptHasFocus && !event.modifierFlags.contains(.command) {
                return event
            }
            confirmAction.doConfirm(); return nil
        }
        return event
    }
}

// NSTextView delegate that draws placeholder text when the view is empty.
class PromptTextViewDelegate: NSObject, NSTextViewDelegate {
    let placeholder: String
    init(_ placeholder: String) { self.placeholder = placeholder }
    func textDidChange(_ notification: Notification) {
        guard let tv = notification.object as? NSTextView else { return }
        tv.needsDisplay = true
    }
}

// NSTextView subclass that draws its own placeholder when empty.
class PromptTextView: NSTextView {
    var placeholderString: String = ""
    override func draw(_ rect: NSRect) {
        super.draw(rect)
        if string.isEmpty {
            let attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor(white: 1, alpha: 0.25),
                .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
            ]
            let inset = textContainerInset
            let origin = NSPoint(x: inset.width + 5, y: inset.height + 1)
            NSAttributedString(string: placeholderString, attributes: attrs).draw(at: origin)
        }
    }
}

// Multi-line prompt input — small editable text view inside a scroll view.
// Newlines are valid in prompts, so Enter inserts a newline; Cmd+Enter submits.
func makePromptTextView() -> (NSScrollView, PromptTextView) {
    let scroll = NSScrollView()
    scroll.translatesAutoresizingMaskIntoConstraints = false
    scroll.hasVerticalScroller = true
    scroll.autohidesScrollers = true
    scroll.drawsBackground = false
    scroll.wantsLayer = true
    scroll.layer?.backgroundColor = itemBg.cgColor
    scroll.layer?.cornerRadius = 6
    scroll.layer?.borderWidth = 1
    scroll.layer?.borderColor = NSColor(white: 1, alpha: 0.12).cgColor
    scroll.borderType = .noBorder

    let tv = PromptTextView()
    tv.placeholderString = "e.g. fix the login redirect bug"
    tv.isEditable = true
    tv.isSelectable = true
    tv.allowsUndo = true
    tv.isRichText = false
    tv.importsGraphics = false
    tv.drawsBackground = false
    tv.textColor = .white
    tv.insertionPointColor = .white
    tv.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    tv.textContainerInset = NSSize(width: 8, height: 6)
    tv.autoresizingMask = [.width]
    tv.minSize = NSSize(width: 0, height: 0)
    tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    tv.isVerticallyResizable = true
    tv.isHorizontallyResizable = false
    tv.textContainer?.widthTracksTextView = true
    tv.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
    let delegate = PromptTextViewDelegate("e.g. fix the login redirect bug")
    tv.delegate = delegate
    objc_setAssociatedObject(tv, "ptd", delegate, .OBJC_ASSOCIATION_RETAIN)

    scroll.documentView = tv
    return (scroll, tv)
}

// ============================================================================
// LAUNCH
// ============================================================================
FileManager.default.createFile(atPath: resultPath, contents: nil)

win.alphaValue = 0
win.makeKeyAndOrderFront(nil)
DispatchQueue.main.async {
    app.activate(ignoringOtherApps: true)
    NSAnimationContext.runAnimationGroup { ctx in
        ctx.duration = 0.15
        win.animator().alphaValue = 1
        backdrop.animator().alphaValue = 1
    }
}

showPickPath()
app.run()
