import Cocoa

// Rename dialog for hub.
// Usage: rename_dialog "workspace_id" "current_name"
// Writes new name to HUB_RENAME_RESULT, or /tmp/hub-rename as fallback, on success. Exits 0 if renamed, 1 if cancelled.

let resultPath = ProcessInfo.processInfo.environment["HUB_RENAME_RESULT"] ?? "/tmp/hub-rename"

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

let wsID        = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "?"
let currentName = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : ""

let dialogW: CGFloat = min(sf.width * 0.4, Theme.Metric.dialogW)
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

var exitCode: Int32 = 1

func dismiss(newName: String?) {
    if let name = newName {
        try? name.write(toFile: resultPath, atomically: true, encoding: .utf8)
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

// Title
let titleLabel = NSTextField(labelWithString: "Rename Workspace \(wsID)")
titleLabel.translatesAutoresizingMaskIntoConstraints = false
titleLabel.font = Theme.Font.ui(19, weight: .bold)
titleLabel.textColor = Theme.Color.textPrimary
cv.addSubview(titleLabel)

// Field label
let fieldLabel = NSTextField(labelWithString: "NAME")
fieldLabel.translatesAutoresizingMaskIntoConstraints = false
fieldLabel.font = Theme.Font.mono(11, weight: .semibold)
fieldLabel.textColor = Theme.Color.textMuted
fieldLabel.isEditable = false; fieldLabel.isBordered = false; fieldLabel.backgroundColor = .clear
cv.addSubview(fieldLabel)

// Input field
let nameField: NSTextField = {
    let f = StyledField()
    f.cell = PaddedCell()
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
        string: "workspace name",
        attributes: [.foregroundColor: Theme.Color.textFaint,
                     .font: Theme.Font.mono(15, weight: .regular)])
    f.stringValue = currentName
    return f
}()
cv.addSubview(nameField)

// Buttons
func makeBtn(_ label: String, shortcut: String, isPrimary: Bool) -> NSView {
    let container = NSView()
    container.translatesAutoresizingMaskIntoConstraints = false
    container.wantsLayer = true
    container.layer?.cornerRadius = Theme.Radius.control
    container.layer?.masksToBounds = true
    if isPrimary {
        container.layer?.backgroundColor = Theme.Color.accentBlue.cgColor
    } else {
        container.layer?.backgroundColor = Theme.Color.inputField.cgColor
        container.layer?.borderWidth = 1
        container.layer?.borderColor = Theme.Color.border.cgColor
    }
    let stack = NSStackView()
    stack.translatesAutoresizingMaskIntoConstraints = false
    stack.orientation = .horizontal
    stack.alignment = .centerY
    stack.spacing = 9
    container.addSubview(stack)
    NSLayoutConstraint.activate([
        stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
        stack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
    ])
    let titleLbl = NSTextField(labelWithString: label)
    titleLbl.translatesAutoresizingMaskIntoConstraints = false
    titleLbl.font = Theme.Font.ui(13, weight: .bold)
    titleLbl.textColor = isPrimary ? .white : Theme.Color.textLabel
    titleLbl.isEditable = false; titleLbl.isBordered = false; titleLbl.backgroundColor = .clear
    stack.addArrangedSubview(titleLbl)
    stack.addArrangedSubview(Theme.makeKeycapLabel(shortcut, onAccent: isPrimary))
    NSLayoutConstraint.activate([
        container.heightAnchor.constraint(equalToConstant: Theme.Metric.buttonH),
    ])
    return container
}

let renameBtn = makeBtn("RENAME", shortcut: "enter", isPrimary: true)
cv.addSubview(renameBtn)
let cancelBtn = makeBtn("CANCEL", shortcut: "esc", isPrimary: false)
cv.addSubview(cancelBtn)

let padH = Theme.Metric.dialogPadH
let padV = Theme.Metric.dialogPadV
NSLayoutConstraint.activate([
    titleLabel.topAnchor.constraint(equalTo: cv.topAnchor, constant: padV),
    titleLabel.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: padH),
    titleLabel.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -padH),
    fieldLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 20),
    fieldLabel.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: padH),
    nameField.topAnchor.constraint(equalTo: fieldLabel.bottomAnchor, constant: 8),
    nameField.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: padH),
    nameField.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -padH),
    nameField.heightAnchor.constraint(equalToConstant: Theme.Metric.inputH),
    renameBtn.topAnchor.constraint(equalTo: nameField.bottomAnchor, constant: 22),
    renameBtn.trailingAnchor.constraint(equalTo: cancelBtn.leadingAnchor, constant: -10),
    renameBtn.widthAnchor.constraint(equalToConstant: 120),
    cancelBtn.topAnchor.constraint(equalTo: renameBtn.topAnchor),
    cancelBtn.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -padH),
    cancelBtn.widthAnchor.constraint(equalToConstant: 110),
    cancelBtn.bottomAnchor.constraint(equalTo: cv.bottomAnchor, constant: -padV),
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

let renameGesture = NSClickGestureRecognizer(target: renameAction, action: #selector(RenameAction.rename(_:)))
let cancelGesture = NSClickGestureRecognizer(target: cancelAction, action: #selector(CancelAction.cancel(_:)))
renameBtn.addGestureRecognizer(renameGesture)
cancelBtn.addGestureRecognizer(cancelGesture)
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
DispatchQueue.main.async {
    app.activate(ignoringOtherApps: true)
    win.makeFirstResponder(nameField)
    NSAnimationContext.runAnimationGroup { ctx in
        ctx.duration = 0.15
        win.animator().alphaValue = 1
        backdrop.animator().alphaValue = 1
    }
}

app.run()
