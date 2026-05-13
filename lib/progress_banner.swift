import Cocoa

// Floating progress banner shown to hub users during workspace setup.
// Top-right corner, always above other windows, no backdrop, no focus steal.
// Usage: progress_banner ["initial message"]
// Stdin: lines update message, "QUIT" or EOF dismisses.
// Dismiss button (×) lets the user close it manually.

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let screen = NSScreen.main ?? NSScreen.screens[0]
let sf = screen.frame

let msg = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "Setting up workspace…"

let bannerW: CGFloat = 340
let bannerH: CGFloat = 64
let margin: CGFloat = 16
let barClearance: CGFloat = 100
let originX = sf.maxX - bannerW - margin
let originY = sf.maxY - bannerH - barClearance

let win = NSWindow(
    contentRect: NSRect(x: originX, y: originY, width: bannerW, height: bannerH),
    styleMask: .borderless, backing: .buffered, defer: false)
win.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)
win.backgroundColor = NSColor(red: 0.08, green: 0.10, blue: 0.14, alpha: 0.94)
win.isOpaque = false
win.hasShadow = true
win.ignoresMouseEvents = false
win.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

let cv = win.contentView!
cv.wantsLayer = true
cv.layer?.cornerRadius = 10
cv.layer?.masksToBounds = true
cv.layer?.borderWidth = 1
cv.layer?.borderColor = NSColor(red: 0.25, green: 0.55, blue: 0.95, alpha: 0.80).cgColor

let spinner = NSProgressIndicator()
spinner.translatesAutoresizingMaskIntoConstraints = false
spinner.style = .spinning
spinner.controlSize = .small
spinner.appearance = NSAppearance(named: .darkAqua)
spinner.startAnimation(nil)
cv.addSubview(spinner)

let label = NSTextField(wrappingLabelWithString: msg)
label.translatesAutoresizingMaskIntoConstraints = false
label.isEditable = false
label.isBordered = false
label.backgroundColor = .clear
label.font = NSFont.systemFont(ofSize: 13, weight: .medium)
label.textColor = NSColor(white: 1, alpha: 0.90)
label.lineBreakMode = .byWordWrapping
label.maximumNumberOfLines = 2
cv.addSubview(label)

// Dismiss button
let closeBtn = NSButton(frame: .zero)
closeBtn.translatesAutoresizingMaskIntoConstraints = false
closeBtn.bezelStyle = .regularSquare
closeBtn.isBordered = false
closeBtn.title = ""
closeBtn.wantsLayer = true
closeBtn.layer?.cornerRadius = 8
closeBtn.layer?.backgroundColor = NSColor(white: 1, alpha: 0.10).cgColor

let xLabel = NSTextField(labelWithString: "✕")
xLabel.translatesAutoresizingMaskIntoConstraints = false
xLabel.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
xLabel.textColor = NSColor(white: 1, alpha: 0.55)
xLabel.isEditable = false
xLabel.isBordered = false
xLabel.backgroundColor = .clear
closeBtn.addSubview(xLabel)

NSLayoutConstraint.activate([
    xLabel.centerXAnchor.constraint(equalTo: closeBtn.centerXAnchor),
    xLabel.centerYAnchor.constraint(equalTo: closeBtn.centerYAnchor),
])

cv.addSubview(closeBtn)

NSLayoutConstraint.activate([
    // Spinner: left edge, vertically centered
    spinner.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 16),
    spinner.centerYAnchor.constraint(equalTo: cv.centerYAnchor),
    spinner.widthAnchor.constraint(equalToConstant: 16),
    spinner.heightAnchor.constraint(equalToConstant: 16),

    // Close button: right edge, vertically centered
    closeBtn.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -12),
    closeBtn.centerYAnchor.constraint(equalTo: cv.centerYAnchor),
    closeBtn.widthAnchor.constraint(equalToConstant: 20),
    closeBtn.heightAnchor.constraint(equalToConstant: 20),

    // Label: between spinner and close button
    label.leadingAnchor.constraint(equalTo: spinner.trailingAnchor, constant: 12),
    label.trailingAnchor.constraint(equalTo: closeBtn.leadingAnchor, constant: -8),
    label.centerYAnchor.constraint(equalTo: cv.centerYAnchor),
    label.topAnchor.constraint(greaterThanOrEqualTo: cv.topAnchor, constant: 10),
    label.bottomAnchor.constraint(lessThanOrEqualTo: cv.bottomAnchor, constant: -10),
])

func dismiss() {
    NSAnimationContext.runAnimationGroup({ ctx in
        ctx.duration = 0.15
        win.animator().alphaValue = 0
    }, completionHandler: {
        NSApp.terminate(nil)
    })
}

closeBtn.target = nil
closeBtn.action = nil
// Use tracking area for click detection since NSButton in borderless window needs help
let tracking = NSTrackingArea(rect: .zero,
    options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
    owner: closeBtn, userInfo: nil)
closeBtn.addTrackingArea(tracking)

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
}

// Replace the plain NSButton with a ClickView
closeBtn.removeFromSuperview()
let dismissView = ClickView(frame: .zero)
dismissView.translatesAutoresizingMaskIntoConstraints = false
dismissView.wantsLayer = true
dismissView.layer?.cornerRadius = 8
dismissView.layer?.backgroundColor = NSColor(white: 1, alpha: 0.10).cgColor
dismissView.onPress = { dismiss() }

let xLabel2 = NSTextField(labelWithString: "✕")
xLabel2.translatesAutoresizingMaskIntoConstraints = false
xLabel2.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
xLabel2.textColor = NSColor(white: 1, alpha: 0.55)
xLabel2.isEditable = false
xLabel2.isBordered = false
xLabel2.backgroundColor = .clear
dismissView.addSubview(xLabel2)

NSLayoutConstraint.activate([
    xLabel2.centerXAnchor.constraint(equalTo: dismissView.centerXAnchor),
    xLabel2.centerYAnchor.constraint(equalTo: dismissView.centerYAnchor),
])

cv.addSubview(dismissView)
NSLayoutConstraint.activate([
    dismissView.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -12),
    dismissView.centerYAnchor.constraint(equalTo: cv.centerYAnchor),
    dismissView.widthAnchor.constraint(equalToConstant: 20),
    dismissView.heightAnchor.constraint(equalToConstant: 20),

    label.trailingAnchor.constraint(equalTo: dismissView.leadingAnchor, constant: -8),
])

win.alphaValue = 0
win.orderFrontRegardless()
DispatchQueue.main.async {
    NSAnimationContext.runAnimationGroup { ctx in
        ctx.duration = 0.15
        win.animator().alphaValue = 1
    }
}

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
