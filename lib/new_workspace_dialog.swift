import Cocoa

// New Workspace dialog for helm.
// Keyboard-first: every action reachable via keyboard, also clickable with mouse.
// Writes result to /tmp/helm-new-workspace as tab-separated:
//   name\tpath\troot_repo\tworkspace_id
// or "cancel" if cancelled.

let resultPath = "/tmp/helm-new-workspace"
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let screen = NSScreen.main ?? NSScreen.screens[0]
let sf = screen.frame

// --- Colors (matching helm palette) ---
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
        }
        return r
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command) else { return super.performKeyEquivalent(with: event) }
        let target = window?.firstResponder
        switch event.charactersIgnoringModifiers ?? "" {
        case "a": return NSApp.sendAction(#selector(NSText.selectAll(_:)), to: target, from: self)
        case "c": return NSApp.sendAction(#selector(NSText.copy(_:)),      to: target, from: self)
        case "v": return NSApp.sendAction(#selector(NSText.paste(_:)),     to: target, from: self)
        case "x": return NSApp.sendAction(#selector(NSText.cut(_:)),       to: target, from: self)
        default:  return super.performKeyEquivalent(with: event)
        }
    }
}

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
    let wsFile = NSString(string: "~/.config/helm/workspaces.json").expandingTildeInPath
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
    let recentFile = NSString(string: "~/.config/helm/recent_repos.json").expandingTildeInPath
    guard let data = FileManager.default.contents(atPath: recentFile),
          var arr = try? JSONSerialization.jsonObject(with: data) as? [String] else { return }
    arr.removeAll { $0 == path }
    if let newData = try? JSONSerialization.data(withJSONObject: arr) {
        try? newData.write(to: URL(fileURLWithPath: recentFile))
    }
}

func recentPaths() -> [String] {
    let recentFile = NSString(string: "~/.config/helm/recent_repos.json").expandingTildeInPath
    if let data = FileManager.default.contents(atPath: recentFile),
       let arr = try? JSONSerialization.jsonObject(with: data) as? [String] {
        return arr.filter { !$0.isEmpty }
    }
    // Fall back to deriving from workspaces.json for backwards compatibility
    let wsFile = NSString(string: "~/.config/helm/workspaces.json").expandingTildeInPath
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

    let errorLabel = NSTextField(labelWithString: "")
    errorLabel.translatesAutoresizingMaskIntoConstraints = false
    errorLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
    errorLabel.textColor = NSColor(red: 0.99, green: 0.36, blue: 0.49, alpha: 1)
    addView(errorLabel)

    // Recent paths
    let recent = recentPaths()
    var recentBtns: [NSButton] = []
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
                btn.topAnchor.constraint(equalTo: prevRecentAnchor, constant: 2),
                btn.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 20),
                btn.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -20),
                btn.heightAnchor.constraint(equalToConstant: 26),
            ])
            prevRecentAnchor = btn.bottomAnchor
            recentBtns.append(btn)
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
        errorLabel.topAnchor.constraint(equalTo: pathField.bottomAnchor, constant: 6),
        errorLabel.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 28),
        errorLabel.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -28),
        nextBtn.topAnchor.constraint(equalTo: prevRecentAnchor, constant: 14),
        nextBtn.trailingAnchor.constraint(equalTo: cancelBtn.leadingAnchor, constant: -10),
        nextBtn.heightAnchor.constraint(equalToConstant: 34),
        nextBtn.widthAnchor.constraint(equalToConstant: 100),
        cancelBtn.topAnchor.constraint(equalTo: nextBtn.topAnchor),
        cancelBtn.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -28),
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
    class CancelAction: NSObject {
        @objc func cancel(_ sender: Any) { cancelAndDismiss() }
    }

    let browseAction = BrowseAction(pathField)
    let nextAction = NextAction(pathField, errorLabel)
    let cancelAction = CancelAction()
    browseBtn.target = browseAction; browseBtn.action = #selector(BrowseAction.browse(_:))
    nextBtn.target = nextAction; nextBtn.action = #selector(NextAction.next(_:))
    cancelBtn.target = cancelAction; cancelBtn.action = #selector(CancelAction.cancel(_:))
    objc_setAssociatedObject(browseBtn, "a", browseAction, .OBJC_ASSOCIATION_RETAIN)
    objc_setAssociatedObject(nextBtn, "a", nextAction, .OBJC_ASSOCIATION_RETAIN)
    objc_setAssociatedObject(cancelBtn, "a", cancelAction, .OBJC_ASSOCIATION_RETAIN)

    currentKeyHandler = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
        if event.keyCode == 53 { cancelAndDismiss(); return nil }
        if event.keyCode == 36 { nextAction.doNext(); return nil }
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
        showNamingWorkspace(path: path, repoRoot: "")
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
        init(_ p: String, _ r: String) { path = p; root = r }
        @objc func pick(_ sender: Any) {
            let color = readWorktreeColor(path)
            showNamingWorkspace(path: path, repoRoot: root, color: color)
        }
    }

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

        let action = WtAction(wt.path, repoRoot)
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
        init(_ r: String, _ m: [String: String]?) { root = r; mgr = m }
        @objc func create(_ sender: Any) { showCreateWorktree(repoRoot: root, manager: mgr) }
    }
    let newWtAction = NewWtAction(repoRoot, manager)
    newWtRow.target = newWtAction; newWtRow.action = #selector(NewWtAction.create(_:))
    objc_setAssociatedObject(newWtRow, "a", newWtAction, .OBJC_ASSOCIATION_RETAIN)

    let cancelBtn = makeBtn(label: "CANCEL", shortcut: "esc", bg: itemBg, fg: NSColor(white: 1, alpha: 0.75))
    addView(cancelBtn)
    class CancelAction: NSObject {
        @objc func cancel(_ sender: Any) { cancelAndDismiss() }
    }
    let cancelAction = CancelAction()
    cancelBtn.target = cancelAction; cancelBtn.action = #selector(CancelAction.cancel(_:))
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
        cancelBtn.topAnchor.constraint(equalTo: newWtRow.bottomAnchor, constant: 14),
        cancelBtn.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -28),
        cancelBtn.heightAnchor.constraint(equalToConstant: 34),
        cancelBtn.widthAnchor.constraint(equalToConstant: 100),
        cancelBtn.bottomAnchor.constraint(equalTo: cv.bottomAnchor, constant: -20),
    ])

    relayout()

    currentKeyHandler = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
        if event.keyCode == 53 { cancelAndDismiss(); return nil }
        if let chars = event.charactersIgnoringModifiers, let digit = Int(chars),
           digit >= 1, digit <= worktrees.count {
            let wt = worktrees[digit - 1]
            let color = readWorktreeColor(wt.path)
            showNamingWorkspace(path: wt.path, repoRoot: repoRoot, color: color)
            return nil
        }
        if event.charactersIgnoringModifiers == "n" {
            showCreateWorktree(repoRoot: repoRoot, manager: manager)
            return nil
        }
        return event
    }
}

// ============================================================================
// STEP 2b: Create New Worktree
// ============================================================================
func showCreateWorktree(repoRoot: String, manager: [String: String]? = nil) {
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

    let createBtn = makeBtn(label: "CREATE", shortcut: "enter", bg: accentBlue, fg: .white, bold: true)
    addView(createBtn)
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
        createBtn.trailingAnchor.constraint(equalTo: cancelBtn.leadingAnchor, constant: -10),
        createBtn.heightAnchor.constraint(equalToConstant: 34),
        createBtn.widthAnchor.constraint(equalToConstant: 100),
        cancelBtn.topAnchor.constraint(equalTo: createBtn.topAnchor),
        cancelBtn.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -28),
        cancelBtn.heightAnchor.constraint(equalToConstant: 34),
        cancelBtn.widthAnchor.constraint(equalToConstant: 100),
        cancelBtn.bottomAnchor.constraint(equalTo: cv.bottomAnchor, constant: -20),
    ])

    relayout()
    win.makeFirstResponder(nameField)

    class CreateAction: NSObject {
        let root: String
        let field: NSTextField
        let errLabel: NSTextField
        let mgr: [String: String]?
        init(_ r: String, _ f: NSTextField, _ e: NSTextField, _ m: [String: String]?) {
            root = r; field = f; errLabel = e; mgr = m
        }
        @objc func create(_ sender: Any) { doCreate() }
        func doCreate() {
            let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { errLabel.stringValue = "Name cannot be empty"; return }
            let existing = listWorktrees(root)
            if let match = existing.first(where: { lastPathComponent($0.path) == name }) {
                let color = readWorktreeColor(match.path)
                showNamingWorkspace(path: match.path, repoRoot: root, color: color)
                return
            }
            showCreatingSpinner(repoRoot: root, name: name, manager: mgr)
        }
    }
    class CancelAction: NSObject {
        @objc func cancel(_ sender: Any) { cancelAndDismiss() }
    }
    let createAction = CreateAction(repoRoot, nameField, errorLabel, manager)
    let cancelAction = CancelAction()
    createBtn.target = createAction; createBtn.action = #selector(CreateAction.create(_:))
    cancelBtn.target = cancelAction; cancelBtn.action = #selector(CancelAction.cancel(_:))
    objc_setAssociatedObject(createBtn, "a", createAction, .OBJC_ASSOCIATION_RETAIN)
    objc_setAssociatedObject(cancelBtn, "a", cancelAction, .OBJC_ASSOCIATION_RETAIN)

    currentKeyHandler = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
        if event.keyCode == 53 { cancelAndDismiss(); return nil }
        if event.keyCode == 36 { createAction.doCreate(); return nil }
        return event
    }
}

// ============================================================================
// STEP 2b.5: Creating Worktree Spinner
// ============================================================================
func showCreatingSpinner(repoRoot: String, name: String, manager: [String: String]? = nil) {
    clearContent()

    let titleLabel = NSTextField(labelWithString: "Creating Worktree")
    titleLabel.translatesAutoresizingMaskIntoConstraints = false
    titleLabel.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
    titleLabel.textColor = dimWhite
    addView(titleLabel)

    let spinner = NSProgressIndicator()
    spinner.translatesAutoresizingMaskIntoConstraints = false
    spinner.style = .spinning
    spinner.controlSize = .regular
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
        let result = createWorktree(repoRoot: repoRoot, name: name)
        DispatchQueue.main.async {
            guard let path = result.path else {
                let errMsg = result.error.isEmpty ? "Failed to create worktree" : "Failed to create worktree:\n\(result.error)"
                statusLabel.stringValue = errMsg
                statusLabel.textColor = NSColor(red: 0.99, green: 0.36, blue: 0.49, alpha: 1)
                spinner.stopAnimation(nil)
                currentKeyHandler = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    if event.keyCode == 53 { cancelAndDismiss(); return nil }
                    return event
                }
                return
            }
            showNamingWorkspace(path: path, repoRoot: repoRoot, setupCmd: manager?["setup"])
        }
    }
}

// ============================================================================
// STEP 3: Finalize — auto-submit with directory name as workspace name
// ============================================================================
func showNamingWorkspace(path: String, repoRoot: String, color: String? = nil, setupCmd: String? = nil) {
    let wsID = nextWorkspaceID()
    let name = lastPathComponent(path)
    var result = "\(name)\t\(path)\t\(repoRoot)\t\(wsID)"
    result += "\t\(color ?? "")"
    result += "\t\(setupCmd ?? "")"
    writeResult(result)
    dismiss()
}

// ============================================================================
// LAUNCH
// ============================================================================
FileManager.default.createFile(atPath: resultPath, contents: nil)

win.alphaValue = 0
win.makeKeyAndOrderFront(nil)
app.activate(ignoringOtherApps: true)
NSAnimationContext.runAnimationGroup { ctx in
    ctx.duration = 0.15
    win.animator().alphaValue = 1
    backdrop.animator().alphaValue = 1
}

showPickPath()
app.run()
