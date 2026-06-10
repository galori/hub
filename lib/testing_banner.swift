import Cocoa

// Small floating "stand by" banner for the top-right corner.
// Always above other windows, no backdrop, no keyboard focus stealing.
// Usage: testing_banner ["message"]
// Exits when stdin closes or a line "QUIT" is received.

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let screen = NSScreen.main ?? NSScreen.screens[0]
let sf = screen.frame

// Always prefix the banner text with the robot marker so it's unmistakably
// an automated-session indicator. Idempotent — won't double up if the caller
// already included it.
let robotPrefix = "[🤖] "
func withRobotPrefix(_ s: String) -> String {
    s.hasPrefix(robotPrefix) ? s : robotPrefix + s
}

let rawMsg = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "Claude Code is testing hub"
let msg = withRobotPrefix(rawMsg)

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
// Must accept mouse events so the ✕ dismiss button is clickable. Without a
// manual escape hatch the banner can outlive a crashed/cancelled caller.
win.ignoresMouseEvents = false
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

func dismiss() {
    NSAnimationContext.runAnimationGroup({ ctx in
        ctx.duration = 0.15
        win.animator().alphaValue = 0
    }, completionHandler: {
        NSApp.terminate(nil)
    })
}

// Manual dismiss button (✕). Escape hatch so the banner can always be closed
// even if the launching process crashed or was ^C'd before calling `stop`.
class ClickView: NSView {
    var onPress: (() -> Void)?
    override func mouseDown(with event: NSEvent) { onPress?() }
    override func mouseEntered(with event: NSEvent) {
        layer?.backgroundColor = NSColor(white: 1, alpha: 0.20).cgColor
    }
    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = NSColor(white: 1, alpha: 0.10).cgColor
    }
    override var acceptsFirstResponder: Bool { false }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self, userInfo: nil))
    }
}

let dismissView = ClickView(frame: .zero)
dismissView.translatesAutoresizingMaskIntoConstraints = false
dismissView.wantsLayer = true
dismissView.layer?.cornerRadius = 8
dismissView.layer?.backgroundColor = NSColor(white: 1, alpha: 0.10).cgColor
dismissView.onPress = { dismiss() }

let xLabel = NSTextField(labelWithString: "✕")
xLabel.translatesAutoresizingMaskIntoConstraints = false
xLabel.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
xLabel.textColor = NSColor(white: 1, alpha: 0.55)
xLabel.isEditable = false
xLabel.isBordered = false
xLabel.backgroundColor = .clear
dismissView.addSubview(xLabel)
cv.addSubview(dismissView)

NSLayoutConstraint.activate([
    spinner.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 24),
    spinner.centerYAnchor.constraint(equalTo: cv.centerYAnchor),
    spinner.widthAnchor.constraint(equalToConstant: 22),
    spinner.heightAnchor.constraint(equalToConstant: 22),
    label.leadingAnchor.constraint(equalTo: spinner.trailingAnchor, constant: 18),
    label.trailingAnchor.constraint(equalTo: dismissView.leadingAnchor, constant: -10),
    label.topAnchor.constraint(greaterThanOrEqualTo: cv.topAnchor, constant: 18),
    label.bottomAnchor.constraint(lessThanOrEqualTo: cv.bottomAnchor, constant: -18),
    label.centerYAnchor.constraint(equalTo: cv.centerYAnchor),
    // Dismiss button: top-right corner
    dismissView.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -12),
    dismissView.topAnchor.constraint(equalTo: cv.topAnchor, constant: 12),
    dismissView.widthAnchor.constraint(equalToConstant: 20),
    dismissView.heightAnchor.constraint(equalToConstant: 20),
    xLabel.centerXAnchor.constraint(equalTo: dismissView.centerXAnchor),
    xLabel.centerYAnchor.constraint(equalTo: dismissView.centerYAnchor),
])

win.alphaValue = 0
win.orderFrontRegardless()
DispatchQueue.main.async {
    NSAnimationContext.runAnimationGroup { ctx in
        ctx.duration = 0.15
        win.animator().alphaValue = 1
    }
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
            let next = withRobotPrefix(trimmed)
            DispatchQueue.main.async { label.stringValue = next }
        }
    }
    DispatchQueue.main.async { dismiss() }
}

app.run()
