import Cocoa

// Confirmation dialog for helm.
// Usage: confirm_dialog "Title" "Message" ["Checkbox label"...]
// Checkbox labels prefixed with "!" default to OFF; others default to ON.
// Writes checkbox states to /tmp/helm-confirm-state on confirm: cb1=0/1, cb2=0/1, ...
// Exits 0 if confirmed, 1 if cancelled.

let statePath = "/tmp/helm-confirm-state"
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let screen = NSScreen.main ?? NSScreen.screens[0]
let sf = screen.frame

let bgColor = NSColor(white: 0.08, alpha: 0.93)
let itemBg = NSColor(red: 0.21, green: 0.22, blue: 0.27, alpha: 1)
let accentRed = NSColor(red: 0.85, green: 0.22, blue: 0.30, alpha: 1)
let dimWhite = NSColor(white: 1, alpha: 0.45)

class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

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

// Parse checkbox args: label starting with "!" defaults to OFF
struct CheckboxInfo {
    let label: String
    let defaultOn: Bool
}
var checkboxInfos: [CheckboxInfo] = []
for i in 3..<CommandLine.arguments.count {
    let raw = CommandLine.arguments[i]
    if raw.hasPrefix("!") {
        checkboxInfos.append(CheckboxInfo(label: String(raw.dropFirst()), defaultOn: false))
    } else {
        checkboxInfos.append(CheckboxInfo(label: raw, defaultOn: true))
    }
}

var checkboxButtons: [NSButton] = []

func dismiss(confirmed: Bool) {
    if confirmed {
        var lines: [String] = []
        for (i, cb) in checkboxButtons.enumerated() {
            lines.append("cb\(i+1)=\(cb.state == .on ? 1 : 0)")
        }
        try? lines.joined(separator: "\n").write(toFile: statePath, atomically: true, encoding: .utf8)
    }
    NSAnimationContext.runAnimationGroup({ ctx in
        ctx.duration = 0.2
        win.animator().alphaValue = 0
        backdrop.animator().alphaValue = 0
    }, completionHandler: {
        exit(confirmed ? 0 : 1)
    })
}

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

let titleText = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Confirm"
let messageText = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "Are you sure?"

let titleLabel = NSTextField(labelWithString: titleText)
titleLabel.translatesAutoresizingMaskIntoConstraints = false
titleLabel.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
titleLabel.textColor = dimWhite
cv.addSubview(titleLabel)

let msgLabel = NSTextField(wrappingLabelWithString: messageText)
msgLabel.translatesAutoresizingMaskIntoConstraints = false
msgLabel.font = NSFont.systemFont(ofSize: 13, weight: .regular)
msgLabel.textColor = NSColor(white: 1, alpha: 0.8)
msgLabel.isEditable = false
msgLabel.isBordered = false
msgLabel.backgroundColor = .clear
cv.addSubview(msgLabel)

// Build checkboxes
var prevAnchor: NSLayoutYAxisAnchor = msgLabel.bottomAnchor
for info in checkboxInfos {
    let cb = NSButton(checkboxWithTitle: info.label, target: nil, action: nil)
    cb.translatesAutoresizingMaskIntoConstraints = false
    cb.state = info.defaultOn ? .on : .off
    cb.attributedTitle = NSAttributedString(string: info.label, attributes: [
        .foregroundColor: NSColor(white: 1, alpha: 0.7),
        .font: NSFont.systemFont(ofSize: 12, weight: .regular),
    ])
    cb.contentTintColor = NSColor(red: 0.10, green: 0.45, blue: 0.91, alpha: 1)
    cv.addSubview(cb)
    NSLayoutConstraint.activate([
        cb.topAnchor.constraint(equalTo: prevAnchor, constant: 14),
        cb.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 28),
    ])
    prevAnchor = cb.bottomAnchor
    checkboxButtons.append(cb)
}

let confirmBtn = makeBtn("REMOVE", shortcut: "enter", bg: accentRed, fg: .white, bold: true)
cv.addSubview(confirmBtn)
let cancelBtn = makeBtn("CANCEL", shortcut: "esc", bg: itemBg, fg: NSColor(white: 1, alpha: 0.75))
cv.addSubview(cancelBtn)

NSLayoutConstraint.activate([
    titleLabel.topAnchor.constraint(equalTo: cv.topAnchor, constant: 24),
    titleLabel.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 28),
    titleLabel.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -28),
    msgLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
    msgLabel.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 28),
    msgLabel.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -28),
    confirmBtn.topAnchor.constraint(equalTo: prevAnchor, constant: 20),
    confirmBtn.trailingAnchor.constraint(equalTo: cancelBtn.leadingAnchor, constant: -10),
    confirmBtn.heightAnchor.constraint(equalToConstant: 34),
    confirmBtn.widthAnchor.constraint(equalToConstant: 100),
    cancelBtn.topAnchor.constraint(equalTo: confirmBtn.topAnchor),
    cancelBtn.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -28),
    cancelBtn.heightAnchor.constraint(equalToConstant: 34),
    cancelBtn.widthAnchor.constraint(equalToConstant: 100),
    cancelBtn.bottomAnchor.constraint(equalTo: cv.bottomAnchor, constant: -20),
])

class ConfirmAction: NSObject {
    @objc func confirm(_ sender: Any) { dismiss(confirmed: true) }
}
class CancelAction: NSObject {
    @objc func cancel(_ sender: Any) { dismiss(confirmed: false) }
}
let confirmAction = ConfirmAction()
let cancelAction = CancelAction()
confirmBtn.target = confirmAction; confirmBtn.action = #selector(ConfirmAction.confirm(_:))
cancelBtn.target = cancelAction; cancelBtn.action = #selector(CancelAction.cancel(_:))
objc_setAssociatedObject(confirmBtn, "a", confirmAction, .OBJC_ASSOCIATION_RETAIN)
objc_setAssociatedObject(cancelBtn, "a", cancelAction, .OBJC_ASSOCIATION_RETAIN)

NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
    if event.keyCode == 53 { dismiss(confirmed: false); return nil }
    if event.keyCode == 36 { dismiss(confirmed: true); return nil }
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
NSAnimationContext.runAnimationGroup { ctx in
    ctx.duration = 0.15
    win.animator().alphaValue = 1
    backdrop.animator().alphaValue = 1
}

app.run()
