import Cocoa

// New Workspace dialog for ws2.
// Keyboard-first: every action reachable via keyboard, also clickable with mouse.
// Writes result to /tmp/ws2-new-workspace as tab-separated:
//   name\tpath\troot_repo\tworkspace_id
// or "cancel" if cancelled.

let resultPath = "/tmp/ws2-new-workspace"
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let screen = NSScreen.main ?? NSScreen.screens[0]
let sf = screen.frame

// --- Colors (matching ws2 palette) ---
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
}

func listWorktrees(_ path: String) -> [Worktree] {
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

func createWorktree(repoRoot: String, name: String) -> String? {
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
    p.standardError = FileHandle.nullDevice
    try? p.run()
    p.waitUntilExit()
    return p.terminationStatus == 0 ? worktreePath : nil
}

func lastPathComponent(_ path: String) -> String {
    (path as NSString).lastPathComponent
}

func nextWorkspaceID() -> String {
    let wsFile = NSString(string: "~/.config/ws2/workspaces.json").expandingTildeInPath
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
        nextBtn.topAnchor.constraint(equalTo: errorLabel.bottomAnchor, constant: 14),
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
    let worktrees = listWorktrees(root)
    showPickWorktree(repoRoot: root, worktrees: worktrees)
}

// ============================================================================
// STEP 2: Pick Worktree
// ============================================================================
func showPickWorktree(repoRoot: String, worktrees: [Worktree]) {
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
        subtitle = "This repo has \(worktrees.count) worktrees — press a number to select"
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
        @objc func pick(_ sender: Any) { showNamingWorkspace(path: path, repoRoot: root) }
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

    let newWtBtn = makeBtn(label: "+ NEW WORKTREE", shortcut: "n", bg: NSColor(white: 0.22, alpha: 1), fg: greenColor)
    addView(newWtBtn)

    class NewWtAction: NSObject {
        let root: String
        init(_ r: String) { root = r }
        @objc func create(_ sender: Any) { showCreateWorktree(repoRoot: root) }
    }
    let newWtAction = NewWtAction(repoRoot)
    newWtBtn.target = newWtAction; newWtBtn.action = #selector(NewWtAction.create(_:))
    objc_setAssociatedObject(newWtBtn, "a", newWtAction, .OBJC_ASSOCIATION_RETAIN)

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
        newWtBtn.topAnchor.constraint(equalTo: prevAnchor, constant: 14),
        newWtBtn.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 28),
        newWtBtn.heightAnchor.constraint(equalToConstant: 34),
        newWtBtn.widthAnchor.constraint(equalToConstant: 170),
        cancelBtn.topAnchor.constraint(equalTo: newWtBtn.topAnchor),
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
            showNamingWorkspace(path: wt.path, repoRoot: repoRoot)
            return nil
        }
        if event.charactersIgnoringModifiers == "n" {
            showCreateWorktree(repoRoot: repoRoot)
            return nil
        }
        return event
    }
}

// ============================================================================
// STEP 2b: Create New Worktree
// ============================================================================
func showCreateWorktree(repoRoot: String) {
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
        init(_ r: String, _ f: NSTextField, _ e: NSTextField) { root = r; field = f; errLabel = e }
        @objc func create(_ sender: Any) { doCreate() }
        func doCreate() {
            let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { errLabel.stringValue = "Name cannot be empty"; return }
            let existing = listWorktrees(root)
            if let match = existing.first(where: { lastPathComponent($0.path) == name }) {
                showNamingWorkspace(path: match.path, repoRoot: root)
                return
            }
            if let newPath = createWorktree(repoRoot: root, name: name) {
                showNamingWorkspace(path: newPath, repoRoot: root)
            } else {
                errLabel.stringValue = "Failed to create worktree"
            }
        }
    }
    class CancelAction: NSObject {
        @objc func cancel(_ sender: Any) { cancelAndDismiss() }
    }
    let createAction = CreateAction(repoRoot, nameField, errorLabel)
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
// STEP 3: Name Workspace
// ============================================================================
func showNamingWorkspace(path: String, repoRoot: String) {
    clearContent()

    let wsID = nextWorkspaceID()
    let defaultName = lastPathComponent(path)

    let titleLabel = NSTextField(labelWithString: "Name Your Workspace")
    titleLabel.translatesAutoresizingMaskIntoConstraints = false
    titleLabel.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
    titleLabel.textColor = dimWhite
    addView(titleLabel)

    let idLabel = NSTextField(labelWithString: "Workspace \(wsID)")
    idLabel.translatesAutoresizingMaskIntoConstraints = false
    idLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
    idLabel.textColor = greenColor
    addView(idLabel)

    let pathDisplayLabel = makeLabel("PATH")
    addView(pathDisplayLabel)
    let pathValue = NSTextField(labelWithString: path)
    pathValue.translatesAutoresizingMaskIntoConstraints = false
    pathValue.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    pathValue.textColor = NSColor(white: 1, alpha: 0.6)
    pathValue.lineBreakMode = .byTruncatingMiddle
    addView(pathValue)

    let nameLabel = makeLabel("NAME")
    addView(nameLabel)
    let nameField = makeField(placeholder: "workspace name", value: defaultName)
    addView(nameField)

    let createBtn = makeBtn(label: "CREATE WORKSPACE", shortcut: "enter", bg: accentBlue, fg: .white, bold: true)
    addView(createBtn)
    let cancelBtn = makeBtn(label: "CANCEL", shortcut: "esc", bg: itemBg, fg: NSColor(white: 1, alpha: 0.75))
    addView(cancelBtn)

    NSLayoutConstraint.activate([
        titleLabel.topAnchor.constraint(equalTo: cv.topAnchor, constant: 24),
        titleLabel.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 28),
        idLabel.topAnchor.constraint(equalTo: titleLabel.topAnchor),
        idLabel.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -28),
        pathDisplayLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 18),
        pathDisplayLabel.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 28),
        pathValue.topAnchor.constraint(equalTo: pathDisplayLabel.bottomAnchor, constant: 4),
        pathValue.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 28),
        pathValue.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -28),
        nameLabel.topAnchor.constraint(equalTo: pathValue.bottomAnchor, constant: 14),
        nameLabel.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 28),
        nameField.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 6),
        nameField.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 28),
        nameField.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -28),
        nameField.heightAnchor.constraint(equalToConstant: 36),
        createBtn.topAnchor.constraint(equalTo: nameField.bottomAnchor, constant: 20),
        createBtn.trailingAnchor.constraint(equalTo: cancelBtn.leadingAnchor, constant: -10),
        createBtn.heightAnchor.constraint(equalToConstant: 34),
        createBtn.widthAnchor.constraint(equalToConstant: 190),
        cancelBtn.topAnchor.constraint(equalTo: createBtn.topAnchor),
        cancelBtn.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -28),
        cancelBtn.heightAnchor.constraint(equalToConstant: 34),
        cancelBtn.widthAnchor.constraint(equalToConstant: 100),
        cancelBtn.bottomAnchor.constraint(equalTo: cv.bottomAnchor, constant: -20),
    ])

    relayout()
    win.makeFirstResponder(nameField)

    class SubmitAction: NSObject {
        let wsPath: String
        let root: String
        let id: String
        let field: NSTextField
        init(_ p: String, _ r: String, _ i: String, _ f: NSTextField) { wsPath = p; root = r; id = i; field = f }
        @objc func submit(_ sender: Any) { doSubmit() }
        func doSubmit() {
            let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return }
            writeResult("\(name)\t\(wsPath)\t\(root)\t\(id)")
            dismiss()
        }
    }
    class CancelAction: NSObject {
        @objc func cancel(_ sender: Any) { cancelAndDismiss() }
    }
    let submitAction = SubmitAction(path, repoRoot, wsID, nameField)
    let cancelAction = CancelAction()
    createBtn.target = submitAction; createBtn.action = #selector(SubmitAction.submit(_:))
    cancelBtn.target = cancelAction; cancelBtn.action = #selector(CancelAction.cancel(_:))
    objc_setAssociatedObject(createBtn, "a", submitAction, .OBJC_ASSOCIATION_RETAIN)
    objc_setAssociatedObject(cancelBtn, "a", cancelAction, .OBJC_ASSOCIATION_RETAIN)

    currentKeyHandler = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
        if event.keyCode == 53 { cancelAndDismiss(); return nil }
        if event.keyCode == 36 { submitAction.doSubmit(); return nil }
        return event
    }
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
