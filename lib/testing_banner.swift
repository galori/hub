import Cocoa

// Small floating "stand by" banner for the top-right corner.
// Always above other windows, no backdrop, no keyboard focus stealing.
// Usage: testing_banner ["message"]
// Exits when stdin closes or a line "QUIT" is received.

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let screen = NSScreen.main ?? NSScreen.screens[0]
let sf = screen.frame

let msg = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "Claude Code is testing hub"

let bannerW: CGFloat = 360
let bannerH: CGFloat = 96
let margin: CGFloat = 16
// Top-right corner, sitting just below the bar area.
let barClearance: CGFloat = 100
let originX = sf.maxX - bannerW - margin
let originY = sf.maxY - bannerH - barClearance

let win = NSWindow(
    contentRect: NSRect(x: originX, y: originY, width: bannerW, height: bannerH),
    styleMask: .borderless, backing: .buffered, defer: false)
win.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)
win.backgroundColor = NSColor(white: 0.08, alpha: 0.92)
win.isOpaque = false
win.hasShadow = true
win.ignoresMouseEvents = true
win.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

let cv = win.contentView!
cv.wantsLayer = true
cv.layer?.cornerRadius = 10
cv.layer?.masksToBounds = true
cv.layer?.borderWidth = 1
cv.layer?.borderColor = NSColor(red: 0.99, green: 0.58, blue: 0.38, alpha: 0.75).cgColor

let spinner = NSProgressIndicator()
spinner.translatesAutoresizingMaskIntoConstraints = false
spinner.style = .spinning
spinner.controlSize = .regular
spinner.appearance = NSAppearance(named: .darkAqua)
spinner.startAnimation(nil)
cv.addSubview(spinner)

let label = NSTextField(wrappingLabelWithString: msg)
label.translatesAutoresizingMaskIntoConstraints = false
label.isEditable = false
label.isBordered = false
label.backgroundColor = .clear
label.font = NSFont.systemFont(ofSize: 13, weight: .medium)
label.textColor = NSColor(white: 1, alpha: 0.9)
label.lineBreakMode = .byWordWrapping
label.maximumNumberOfLines = 3
cv.addSubview(label)

NSLayoutConstraint.activate([
    spinner.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 24),
    spinner.centerYAnchor.constraint(equalTo: cv.centerYAnchor),
    spinner.widthAnchor.constraint(equalToConstant: 22),
    spinner.heightAnchor.constraint(equalToConstant: 22),
    label.leadingAnchor.constraint(equalTo: spinner.trailingAnchor, constant: 18),
    label.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -24),
    label.topAnchor.constraint(greaterThanOrEqualTo: cv.topAnchor, constant: 18),
    label.bottomAnchor.constraint(lessThanOrEqualTo: cv.bottomAnchor, constant: -18),
    label.centerYAnchor.constraint(equalTo: cv.centerYAnchor),
])

win.alphaValue = 0
win.orderFrontRegardless()
DispatchQueue.main.async {
    NSAnimationContext.runAnimationGroup { ctx in
        ctx.duration = 0.15
        win.animator().alphaValue = 1
    }
}

func dismiss() {
    NSAnimationContext.runAnimationGroup({ ctx in
        ctx.duration = 0.15
        win.animator().alphaValue = 0
    }, completionHandler: {
        NSApp.terminate(nil)
    })
}

// Read stdin so the caller can update the message or ask us to QUIT.
// Closing stdin also exits (process death triggers this naturally).
DispatchQueue.global(qos: .userInitiated).async {
    while let line = readLine() {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "QUIT" {
            DispatchQueue.main.async { dismiss() }
            return
        }
        if !trimmed.isEmpty {
            DispatchQueue.main.async { label.stringValue = trimmed }
        }
    }
    DispatchQueue.main.async { dismiss() }
}

app.run()
