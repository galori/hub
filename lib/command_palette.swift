import Cocoa

// Command palette: fuzzy-search modal for jumping to a workspace by name or id.
//
// Invoked by `hub palette` (Ctrl-Alt-P). Shows a single search field with a
// live-filtered list of workspaces below it; the top match is always
// highlighted so Enter has an obvious default. Clicking a row, or pressing
// Enter/Down+Enter, selects it.
//
// Result: writes the chosen workspace_id to COMMAND_PALETTE_RESULT, or
// /tmp/hub-command-palette-result as fallback, and exits 0 on commit.
// On cancel, removes that file and exits 1.

let resultPath = ProcessInfo.processInfo.environment["COMMAND_PALETTE_RESULT"] ?? "/tmp/hub-command-palette-result"
let hubConfigDir = ProcessInfo.processInfo.environment["HUB_CONFIG_DIR"] ?? ("~/.config/hub" as NSString).expandingTildeInPath
let workspacesPath = ProcessInfo.processInfo.environment["WORKSPACES_FILE"] ?? (hubConfigDir as NSString).appendingPathComponent("workspaces.json")

// ── Workspace loading ─────────────────────────────────────────────────────────

struct WorkspaceEntry {
    let id: String
    let name: String
}

func loadWorkspaces() -> [WorkspaceEntry] {
    guard let data = FileManager.default.contents(atPath: workspacesPath),
          let json = try? JSONSerialization.jsonObject(with: data),
          let arr = json as? [[String: Any]] else { return [] }
    return arr.compactMap { e -> WorkspaceEntry? in
        guard let id = e["workspace_id"] as? String, let name = e["name"] as? String else { return nil }
        return WorkspaceEntry(id: id, name: name)
    }.sorted { $0.id < $1.id }
}

let allWorkspaces = loadWorkspaces()

if allWorkspaces.isEmpty {
    try? FileManager.default.removeItem(atPath: resultPath)
    exit(1)
}

// ── Window scaffolding (mirrors app_switcher.swift / rename_dialog.swift) ────

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let screen = NSScreen.main ?? NSScreen.screens[0]
let sf = screen.frame

class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

class PaddedCell: NSTextFieldCell {
    private func adjustedRect(_ rect: NSRect) -> NSRect {
        var r = rect.insetBy(dx: 8, dy: 0)
        let h = super.cellSize(forBounds: r).height
        if h < r.height {
            r.origin.y += (r.height - h) / 2
            r.size.height = h
        }
        return r
    }
    override func edit(withFrame rect: NSRect, in view: NSView, editor: NSText, delegate: Any?, event: NSEvent?) {
        super.edit(withFrame: adjustedRect(rect), in: view, editor: editor, delegate: delegate, event: event)
    }
    override func draw(withFrame rect: NSRect, in view: NSView) {
        super.draw(withFrame: adjustedRect(rect), in: view)
    }
    override func select(withFrame rect: NSRect, in view: NSView, editor: NSText, delegate: Any?, start: Int, length: Int) {
        super.select(withFrame: adjustedRect(rect), in: view, editor: editor, delegate: delegate, start: start, length: length)
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

let dialogW: CGFloat = min(sf.width * 0.32, Theme.Metric.dialogW)
let rowH: CGFloat = 32
let maxVisibleRows = 8
let listH: CGFloat = rowH * CGFloat(maxVisibleRows)

let win = KeyableWindow(contentRect: NSRect(x: 0, y: 0, width: dialogW, height: 100),
                        styleMask: .borderless, backing: .buffered, defer: false)
win.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)
win.backgroundColor = .clear
win.isOpaque = false
win.hasShadow = true
win.collectionBehavior = [.canJoinAllSpaces, .stationary]

let cv = win.contentView!
Theme.applyCardBackground(to: cv, radius: Theme.Radius.modal, kind: .modal)

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

var finished = false
func dismiss(chosenId: String?) {
    if finished { return }
    finished = true
    if let id = chosenId {
        try? id.write(toFile: resultPath, atomically: true, encoding: .utf8)
    } else {
        try? FileManager.default.removeItem(atPath: resultPath)
    }
    let exitCode: Int32 = chosenId != nil ? 0 : 1
    NSAnimationContext.runAnimationGroup({ ctx in
        ctx.duration = 0.15
        win.animator().alphaValue = 0
        backdrop.animator().alphaValue = 0
    }, completionHandler: {
        exit(exitCode)
    })
}

// ── Dismiss (✕) button — top-right of the card ────────────────────────────────

let closeBtn = Theme.makeDismissButton { dismiss(chosenId: nil) }
cv.addSubview(closeBtn)

// ── Search field ──────────────────────────────────────────────────────────────

let searchField: NSTextField = {
    let f = StyledField()
    f.cell = PaddedCell()
    f.stringValue = ""
    f.translatesAutoresizingMaskIntoConstraints = false
    f.isEditable = true
    f.isBordered = false
    f.wantsLayer = true
    f.layer?.backgroundColor = Theme.Color.inputField.cgColor
    f.layer?.cornerRadius = Theme.Radius.control
    f.layer?.borderWidth = 1
    f.layer?.borderColor = Theme.Color.border.cgColor
    f.textColor = Theme.Color.textPrimary
    f.font = Theme.Font.mono(15, weight: .regular)
    f.focusRingType = .none
    (f.cell as? NSTextFieldCell)?.placeholderAttributedString = NSAttributedString(
        string: "Go to workspace…",
        attributes: [.foregroundColor: Theme.Color.textFaint,
                     .font: Theme.Font.mono(15, weight: .regular)])
    return f
}()
cv.addSubview(searchField)

// ── Result list (scrollable stack of rows) ────────────────────────────────────

let scrollView = NSScrollView()
scrollView.translatesAutoresizingMaskIntoConstraints = false
scrollView.drawsBackground = false
scrollView.hasVerticalScroller = true
scrollView.autohidesScrollers = true
scrollView.scrollerStyle = .overlay
scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 6)
cv.addSubview(scrollView)

let listContainer = NSView()
listContainer.translatesAutoresizingMaskIntoConstraints = false
scrollView.documentView = listContainer
listContainer.widthAnchor.constraint(equalTo: scrollView.widthAnchor).isActive = true

// ── Filtering + highlight management ──────────────────────────────────────────

class PaletteListManager: NSObject, NSTextFieldDelegate {
    let allWorkspaces: [WorkspaceEntry]
    let container: NSView
    let field: NSTextField
    var rows: [(entry: WorkspaceEntry, button: NSButton)] = []
    var highlightedIndex: Int = -1

    init(workspaces: [WorkspaceEntry], container: NSView, field: NSTextField) {
        self.allWorkspaces = workspaces
        self.container = container
        self.field = field
        super.init()
    }

    func controlTextDidChange(_ obj: Notification) {
        // The workspace list is small and already in memory, so filtering is
        // effectively instant — no debounce needed.
        let query = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = query.isEmpty ? allWorkspaces : allWorkspaces.filter {
            $0.name.lowercased().contains(query) || $0.id.lowercased().contains(query)
        }
        rebuildList(filtered: filtered)
    }

    func rebuildList(filtered: [WorkspaceEntry]? = nil) {
        let workspaces = filtered ?? allWorkspaces
        for sub in container.subviews { sub.removeFromSuperview() }
        rows.removeAll()
        highlightedIndex = -1
        var prevAnchor: NSLayoutYAxisAnchor = container.topAnchor
        for (i, ws) in workspaces.enumerated() {
            let btn = NSButton()
            btn.translatesAutoresizingMaskIntoConstraints = false
            btn.isBordered = false
            btn.wantsLayer = true
            btn.layer?.cornerRadius = Theme.Radius.keycap
            btn.alignment = .left
            btn.attributedTitle = rowTitle(ws, highlighted: false)
            btn.tag = i
            btn.target = self; btn.action = #selector(pick(_:))
            container.addSubview(btn)
            rows.append((entry: ws, button: btn))
            NSLayoutConstraint.activate([
                btn.topAnchor.constraint(equalTo: prevAnchor, constant: i == 0 ? 4 : 1),
                btn.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                btn.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                btn.heightAnchor.constraint(equalToConstant: rowH - 2),
            ])
            prevAnchor = btn.bottomAnchor
        }
        if !workspaces.isEmpty {
            prevAnchor.constraint(equalTo: container.bottomAnchor, constant: -4).isActive = true
        } else {
            container.topAnchor.constraint(equalTo: container.bottomAnchor).isActive = true
        }
        container.layoutSubtreeIfNeeded()
        // Auto-highlight the top match so Enter has an obvious default.
        if !rows.isEmpty { setHighlight(0) }
    }

    func rowTitle(_ ws: WorkspaceEntry, highlighted: Bool) -> NSAttributedString {
        NSAttributedString(string: "  \(ws.id)   \(ws.name)", attributes: [
            .font: Theme.Font.mono(13),
            .foregroundColor: highlighted ? Theme.Color.textPrimary : Theme.Color.textSecondary,
        ])
    }

    func moveHighlight(by delta: Int) {
        guard !rows.isEmpty else { return }
        let newIndex = max(0, min(rows.count - 1, highlightedIndex + delta))
        setHighlight(newIndex)
    }

    func setHighlight(_ index: Int) {
        if highlightedIndex >= 0 && highlightedIndex < rows.count {
            let old = rows[highlightedIndex]
            old.button.layer?.backgroundColor = nil
            old.button.attributedTitle = rowTitle(old.entry, highlighted: false)
        }
        highlightedIndex = index
        if index >= 0 && index < rows.count {
            let row = rows[index]
            row.button.layer?.backgroundColor = Theme.Color.accentBlue.withAlphaComponent(0.28).cgColor
            row.button.attributedTitle = rowTitle(row.entry, highlighted: true)
            row.button.superview?.enclosingScrollView?.scrollToVisible(row.button.frame)
        }
    }

    func selectHighlighted() {
        guard highlightedIndex >= 0 && highlightedIndex < rows.count else { return }
        dismiss(chosenId: rows[highlightedIndex].entry.id)
    }

    @objc func pick(_ sender: NSButton) { dismiss(chosenId: rows[sender.tag].entry.id) }
}

let listMgr = PaletteListManager(workspaces: allWorkspaces, container: listContainer, field: searchField)
searchField.delegate = listMgr
listMgr.rebuildList()

// ── Layout ────────────────────────────────────────────────────────────────────

let padH = Theme.Metric.dialogPadH
let padV = Theme.Metric.dialogPadV
NSLayoutConstraint.activate([
    closeBtn.topAnchor.constraint(equalTo: cv.topAnchor, constant: 10),
    closeBtn.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -10),
    closeBtn.widthAnchor.constraint(equalToConstant: 20),
    closeBtn.heightAnchor.constraint(equalToConstant: 20),

    searchField.topAnchor.constraint(equalTo: cv.topAnchor, constant: padV),
    searchField.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: padH),
    searchField.trailingAnchor.constraint(equalTo: closeBtn.leadingAnchor, constant: -12),
    searchField.heightAnchor.constraint(equalToConstant: Theme.Metric.inputH),

    scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 14),
    scrollView.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: padH),
    scrollView.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -padH),
    scrollView.heightAnchor.constraint(equalToConstant: listH),
    scrollView.bottomAnchor.constraint(equalTo: cv.bottomAnchor, constant: -padV),
])

// ── Key events ────────────────────────────────────────────────────────────────

NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
    if event.keyCode == 53 { dismiss(chosenId: nil); return nil }   // Esc
    if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "w" { dismiss(chosenId: nil); return nil }
    if event.keyCode == 36 { listMgr.selectHighlighted(); return nil }  // Return
    if event.keyCode == 125 { listMgr.moveHighlight(by: 1); return nil }   // Down
    if event.keyCode == 126 { listMgr.moveHighlight(by: -1); return nil }  // Up
    return event
}

// ── Show ──────────────────────────────────────────────────────────────────────

cv.layoutSubtreeIfNeeded()
let fittingH = padV + Theme.Metric.inputH + 14 + listH + padV
let finalRect = NSRect(x: sf.midX - dialogW / 2, y: sf.midY - fittingH / 2 + 80,
                       width: dialogW, height: fittingH)
win.setFrame(finalRect, display: true)

win.alphaValue = 0
win.makeKeyAndOrderFront(nil)
DispatchQueue.main.async {
    app.activate(ignoringOtherApps: true)
    win.makeFirstResponder(searchField)
    listMgr.setHighlight(0)
    NSAnimationContext.runAnimationGroup { ctx in
        ctx.duration = 0.15
        win.animator().alphaValue = 1
        backdrop.animator().alphaValue = 1
    }
}

app.run()
