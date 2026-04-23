import Cocoa

// Rename dialog for hub.
// Usage: rename_dialog "workspace_id" "current_name"
// Writes new name to /tmp/hub-rename on success. Exits 0 if renamed, 1 if cancelled.

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let screen = NSScreen.main ?? NSScreen.screens[0]
let sf = screen.frame

let bgColor = NSColor(white: 0.08, alpha: 0.93)
let itemBg = NSColor(red: 0.21, green: 0.22, blue: 0.27, alpha: 1)
let accentBlue = NSColor(red: 0.10, green: 0.45, blue: 0.91, alpha: 1)
let dimWhite = NSColor(white: 1, alpha: 0.45)

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

let wsID = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "?"
let currentName = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : ""

let dialogW: CGFloat = min(sf.width * 0.4, 480)
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

var exitCode: Int32 = 1

func dismiss(newName: String?) {
    if let name = newName {
        try? name.write(toFile: "/tmp/hub-rename", atomically: true, encoding: .utf8)
        exitCode = 0
    } else {
        exitCode = 1
    }
    NSAnimationContext.runAnimationGroup({ ctx in
        ctx.duration = 0.2
        win.animator().alphaValue = 0
        backdrop.animator().alphaValue = 0
    }, completionHandler: {
        exit(exitCode)
    })
}

let titleLabel = NSTextField(labelWithString: "Rename Workspace \(wsID)")
titleLabel.translatesAutoresizingMaskIntoConstraints = false
titleLabel.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
titleLabel.textColor = dimWhite
cv.addSubview(titleLabel)

let nameField: NSTextField = {
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
        string: "workspace name",
        attributes: [.foregroundColor: NSColor(white: 1, alpha: 0.25),
                     .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)])
    f.stringValue = currentName
    return f
}()
cv.addSubview(nameField)

func makeBtn(_ label: String, shortcut: String, bg: NSColor, fg: NSColor, bold: Bool = false) -> NSButton {
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
    attr.append(NSAttributedString(string: "  \(shortcut)", attributes: [
        .foregroundColor: fg.withAlphaComponent(0.4),
        .font: NSFont.systemFont(ofSize: 9, weight: .medium),
        .paragraphStyle: style,
    ]))
    b.attributedTitle = attr
    return b
}

let renameBtn = makeBtn("RENAME", shortcut: "enter", bg: accentBlue, fg: .white, bold: true)
cv.addSubview(renameBtn)

let cancelBtn = makeBtn("CANCEL", shortcut: "esc", bg: itemBg, fg: NSColor(white: 1, alpha: 0.75))
cv.addSubview(cancelBtn)

NSLayoutConstraint.activate([
    titleLabel.topAnchor.constraint(equalTo: cv.topAnchor, constant: 24),
    titleLabel.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 28),
    titleLabel.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -28),
    nameField.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 16),
    nameField.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 28),
    nameField.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -28),
    nameField.heightAnchor.constraint(equalToConstant: 34),
    renameBtn.topAnchor.constraint(equalTo: nameField.bottomAnchor, constant: 20),
    renameBtn.trailingAnchor.constraint(equalTo: cancelBtn.leadingAnchor, constant: -10),
    renameBtn.heightAnchor.constraint(equalToConstant: 34),
    renameBtn.widthAnchor.constraint(equalToConstant: 100),
    cancelBtn.topAnchor.constraint(equalTo: renameBtn.topAnchor),
    cancelBtn.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -28),
    cancelBtn.heightAnchor.constraint(equalToConstant: 34),
    cancelBtn.widthAnchor.constraint(equalToConstant: 100),
    cancelBtn.bottomAnchor.constraint(equalTo: cv.bottomAnchor, constant: -20),
])

class RenameAction: NSObject {
    @objc func rename(_ sender: Any) { doRename() }
    func doRename() {
        let name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        dismiss(newName: name)
    }
}
class CancelAction: NSObject {
    @objc func cancel(_ sender: Any) { dismiss(newName: nil) }
}
let renameAction = RenameAction()
let cancelAction = CancelAction()
renameBtn.target = renameAction; renameBtn.action = #selector(RenameAction.rename(_:))
cancelBtn.target = cancelAction; cancelBtn.action = #selector(CancelAction.cancel(_:))
objc_setAssociatedObject(renameBtn, "a", renameAction, .OBJC_ASSOCIATION_RETAIN)
objc_setAssociatedObject(cancelBtn, "a", cancelAction, .OBJC_ASSOCIATION_RETAIN)

NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
    if event.keyCode == 53 { dismiss(newName: nil); return nil }
    if event.keyCode == 36 { renameAction.doRename(); return nil }
    return event
}

cv.layoutSubtreeIfNeeded()
let fittingH = max(cv.fittingSize.height + 8, 120)
let finalRect = NSRect(x: sf.midX - dialogW / 2, y: sf.midY - fittingH / 2 + 80,
                       width: dialogW, height: fittingH)
win.setFrame(finalRect, display: true)

win.alphaValue = 0
win.makeKeyAndOrderFront(nil)
app.activate(ignoringOtherApps: true)
win.makeFirstResponder(nameField)
NSAnimationContext.runAnimationGroup { ctx in
    ctx.duration = 0.15
    win.animator().alphaValue = 1
    backdrop.animator().alphaValue = 1
}

app.run()
