import Cocoa

// Status overlay HUD for hub — reads lines from stdin, displays them in a
// floating dark panel. Send "QUIT" to dismiss. Newlines encoded as literal "\n".

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let screen = NSScreen.main ?? NSScreen.screens[0]
let sf = screen.frame
let overlayW: CGFloat = sf.width * 0.75
let overlayH: CGFloat = 200

class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

let win = KeyableWindow(
    contentRect: NSRect(x: sf.midX - overlayW / 2, y: sf.midY - overlayH / 2 + 80, width: overlayW, height: overlayH),
    styleMask: .borderless, backing: .buffered, defer: false)
win.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)
win.backgroundColor = .clear
win.isOpaque = false
win.hasShadow = true
win.collectionBehavior = [.canJoinAllSpaces, .stationary]

let cv = win.contentView!
Theme.applyCardBackground(to: cv, radius: Theme.Radius.modal, kind: .modal)

// Full-screen backdrop
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

func dismiss() {
    NSAnimationContext.runAnimationGroup({ ctx in
        ctx.duration = 0.25
        win.animator().alphaValue = 0
        backdrop.animator().alphaValue = 0
    }, completionHandler: {
        NSApp.terminate(nil)
    })
}

// Title
let titleStr = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Hub"
let title = NSTextField(labelWithString: titleStr)
title.translatesAutoresizingMaskIntoConstraints = false
title.font = Theme.Font.ui(15, weight: .semibold)
title.textColor = Theme.Color.textMuted
cv.addSubview(title)

// Status text
let label = NSTextField(wrappingLabelWithString: "")
label.translatesAutoresizingMaskIntoConstraints = false
label.isEditable = false
label.isBordered = false
label.backgroundColor = .clear
label.textColor = Theme.Color.textPrimary
label.font = Theme.Font.mono(18, weight: .regular)
label.alignment = .left
label.maximumNumberOfLines = 0
label.cell?.truncatesLastVisibleLine = true
cv.addSubview(label)

NSLayoutConstraint.activate([
    title.topAnchor.constraint(equalTo: cv.topAnchor, constant: 24),
    title.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 28),
    label.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 16),
    label.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 28),
    label.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -28),
    label.bottomAnchor.constraint(lessThanOrEqualTo: cv.bottomAnchor, constant: -20),
])

// Read stdin on background thread
DispatchQueue.global(qos: .userInitiated).async {
    while let line = readLine() {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != "QUIT" else {
            DispatchQueue.main.async { dismiss() }
            return
        }
        let text = trimmed.replacingOccurrences(of: "\\n", with: "\n")
        DispatchQueue.main.async {
            label.stringValue = text
            if !win.isVisible {
                win.alphaValue = 0
                win.orderFrontRegardless()
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.15
                    win.animator().alphaValue = 1
                    backdrop.animator().alphaValue = 1
                }
            }
        }
    }
    DispatchQueue.main.async { dismiss() }
}

app.run()
