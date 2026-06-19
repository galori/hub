import Cocoa

// Confirmation dialog for hub.
// Usage: confirm_dialog "Title" "Message" ["Checkbox label"...]
// Checkbox labels prefixed with "!" default to OFF; others default to ON.
// Writes checkbox states to /tmp/hub-confirm-state on confirm: cb1=0/1, cb2=0/1, ...
// Exits 0 if confirmed, 1 if cancelled.

let statePath = "/tmp/hub-confirm-state"
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let screen = NSScreen.main ?? NSScreen.screens[0]
let sf = screen.frame

class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

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

// Custom checkbox: 22×22 accent-fill square, rounded 6px
class CustomCheckbox: NSView {
    var isChecked: Bool { didSet { needsDisplay = true } }
    var label: String
    var onChange: (() -> Void)?

    init(label: String, checked: Bool) {
        self.label = label
        self.isChecked = checked
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        let click = NSClickGestureRecognizer(target: self, action: #selector(toggle))
        addGestureRecognizer(click)
    }
    required init?(coder: NSCoder) { fatalError() }

    @objc func toggle() { isChecked.toggle(); onChange?() }

    override func draw(_ dirtyRect: NSRect) {
        let size: CGFloat = Theme.Metric.checkboxSize
        let boxY = (bounds.height - size) / 2
        let boxRect = NSRect(x: 0, y: boxY, width: size, height: size)
        let path = NSBezierPath(roundedRect: boxRect, xRadius: Theme.Radius.checkbox, yRadius: Theme.Radius.checkbox)

        if isChecked {
            Theme.Color.accentBlue.setFill()
            path.fill()
            // Checkmark
            let check = NSBezierPath()
            check.move(to: NSPoint(x: boxRect.minX + 5, y: boxRect.midY))
            check.line(to: NSPoint(x: boxRect.minX + 9, y: boxRect.minY + 5))
            check.line(to: NSPoint(x: boxRect.maxX - 4, y: boxRect.maxY - 5))
            check.lineWidth = 2
            check.lineCapStyle = .round
            check.lineJoinStyle = .round
            NSColor.white.setStroke()
            check.stroke()
        } else {
            Theme.Color.inputField.setFill()
            path.fill()
            NSColor(white: 1, alpha: 0.22).setStroke()
            path.lineWidth = 1.5
            path.stroke()
        }

        // Label
        let labelX = size + 10
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: Theme.Color.textLabel,
            .font: Theme.Font.ui(14, weight: .medium),
        ]
        let str = NSAttributedString(string: label, attributes: attrs)
        let strSize = str.size()
        str.draw(at: NSPoint(x: labelX, y: (bounds.height - strSize.height) / 2))
    }

    override var intrinsicContentSize: NSSize {
        let attrs: [NSAttributedString.Key: Any] = [.font: Theme.Font.ui(14, weight: .medium)]
        let w = (label as NSString).size(withAttributes: attrs).width
        return NSSize(width: Theme.Metric.checkboxSize + 10 + w, height: 26)
    }
}

var customCheckboxes: [CustomCheckbox] = []

func dismiss(confirmed: Bool) {
    if confirmed {
        var lines: [String] = []
        for (i, cb) in customCheckboxes.enumerated() {
            lines.append("cb\(i+1)=\(cb.isChecked ? 1 : 0)")
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

// Keyed button matching design guide: slate secondary / accent primary
func makeBtn(_ label: String, shortcut: String, kind: BtnKind) -> NSView {
    let container = NSView()
    container.translatesAutoresizingMaskIntoConstraints = false
    container.wantsLayer = true
    container.layer?.cornerRadius = Theme.Radius.control
    container.layer?.masksToBounds = true

    switch kind {
    case .primary:
        container.layer?.backgroundColor = Theme.Color.accentBlue.cgColor
    case .destructive:
        container.layer?.backgroundColor = Theme.Color.destructive.cgColor
    case .secondary:
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
        stack.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 16),
        stack.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -16),
    ])

    let titleLbl = NSTextField(labelWithString: label)
    titleLbl.translatesAutoresizingMaskIntoConstraints = false
    titleLbl.font = Theme.Font.ui(13, weight: .bold)
    titleLbl.textColor = kind == .secondary ? Theme.Color.textLabel : .white
    titleLbl.isEditable = false; titleLbl.isBordered = false; titleLbl.backgroundColor = .clear
    stack.addArrangedSubview(titleLbl)

    let keyLbl = Theme.makeKeycapLabel(shortcut, onAccent: kind != .secondary)
    stack.addArrangedSubview(keyLbl)

    NSLayoutConstraint.activate([
        container.heightAnchor.constraint(equalToConstant: Theme.Metric.buttonH),
    ])
    return container
}

enum BtnKind { case primary, secondary, destructive }

let titleText   = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Confirm"
let messageText = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "Are you sure?"

// Title
let titleLabel = NSTextField(labelWithString: titleText)
titleLabel.translatesAutoresizingMaskIntoConstraints = false
titleLabel.font = Theme.Font.ui(19, weight: .bold)
titleLabel.textColor = Theme.Color.textPrimary
cv.addSubview(titleLabel)

// Message body
let msgLabel = NSTextField(wrappingLabelWithString: "")
msgLabel.translatesAutoresizingMaskIntoConstraints = false
msgLabel.isEditable = false
msgLabel.isBordered = false
msgLabel.backgroundColor = .clear
let normalAttrs: [NSAttributedString.Key: Any] = [
    .font: Theme.Font.ui(14, weight: .regular),
    .foregroundColor: Theme.Color.textSecondary,
]
let highlightAttrs: [NSAttributedString.Key: Any] = [
    .font: Theme.Font.mono(14, weight: .medium),
    .foregroundColor: Theme.Color.textPrimary,
]
let msgAttributed = NSMutableAttributedString()
var remaining = messageText
while let range = remaining.range(of: "Z General") {
    msgAttributed.append(NSAttributedString(string: String(remaining[..<range.lowerBound]), attributes: normalAttrs))
    msgAttributed.append(NSAttributedString(string: "Z\u{00A0}General", attributes: highlightAttrs))
    remaining = String(remaining[range.upperBound...])
}
msgAttributed.append(NSAttributedString(string: remaining, attributes: normalAttrs))
msgLabel.attributedStringValue = msgAttributed
cv.addSubview(msgLabel)

// Checkboxes
var prevAnchor: NSLayoutYAxisAnchor = msgLabel.bottomAnchor
for info in checkboxInfos {
    let cb = CustomCheckbox(label: info.label, checked: info.defaultOn)
    cv.addSubview(cb)
    NSLayoutConstraint.activate([
        cb.topAnchor.constraint(equalTo: prevAnchor, constant: 16),
        cb.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: Theme.Metric.dialogPadH),
    ])
    prevAnchor = cb.bottomAnchor
    customCheckboxes.append(cb)
}

// Determine action button kind from title text
let isCancelTitle = titleText.lowercased().contains("cancel")
let isDeleteTitle = titleText.lowercased().contains("remov") ||
                    titleText.lowercased().contains("delet") ||
                    titleText.lowercased().contains("destroy")
let primaryKind: BtnKind = isDeleteTitle ? .destructive : .primary
let primaryLabel = isDeleteTitle ? "REMOVE" : "CONFIRM"

let confirmBtn = makeBtn(primaryLabel, shortcut: "enter", kind: primaryKind)
cv.addSubview(confirmBtn)
let cancelBtn  = makeBtn("CANCEL",  shortcut: "esc",   kind: .secondary)
cv.addSubview(cancelBtn)

let padH = Theme.Metric.dialogPadH
let padV = Theme.Metric.dialogPadV
NSLayoutConstraint.activate([
    titleLabel.topAnchor.constraint(equalTo: cv.topAnchor, constant: padV),
    titleLabel.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: padH),
    titleLabel.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -padH),
    msgLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
    msgLabel.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: padH),
    msgLabel.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -padH),
    // Buttons row
    confirmBtn.topAnchor.constraint(equalTo: prevAnchor, constant: 22),
    confirmBtn.trailingAnchor.constraint(equalTo: cancelBtn.leadingAnchor, constant: -10),
    confirmBtn.widthAnchor.constraint(equalToConstant: 140),
    cancelBtn.topAnchor.constraint(equalTo: confirmBtn.topAnchor),
    cancelBtn.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -padH),
    cancelBtn.widthAnchor.constraint(equalToConstant: 110),
    cancelBtn.bottomAnchor.constraint(equalTo: cv.bottomAnchor, constant: -padV),
])

// Wire button actions
class ConfirmAction: NSObject {
    @objc func confirm(_ sender: Any) { dismiss(confirmed: true) }
}
class CancelAction: NSObject {
    @objc func cancel(_ sender: Any) { dismiss(confirmed: false) }
}
let confirmAction = ConfirmAction()
let cancelAction  = CancelAction()

let confirmGesture = NSClickGestureRecognizer(target: confirmAction, action: #selector(ConfirmAction.confirm(_:)))
let cancelGesture  = NSClickGestureRecognizer(target: cancelAction,  action: #selector(CancelAction.cancel(_:)))
confirmBtn.addGestureRecognizer(confirmGesture)
cancelBtn.addGestureRecognizer(cancelGesture)
objc_setAssociatedObject(confirmBtn, "a", confirmAction, .OBJC_ASSOCIATION_RETAIN)
objc_setAssociatedObject(cancelBtn,  "a", cancelAction,  .OBJC_ASSOCIATION_RETAIN)

NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
    if event.keyCode == 53 { dismiss(confirmed: false); return nil }
    if event.keyCode == 36 { dismiss(confirmed: true);  return nil }
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
    NSAnimationContext.runAnimationGroup { ctx in
        ctx.duration = 0.15
        win.animator().alphaValue = 1
        backdrop.animator().alphaValue = 1
    }
}

app.run()
