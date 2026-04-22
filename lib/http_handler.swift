import Cocoa

// HTTP/HTTPS handler for helm.
// Registered as the default web browser; receives URLs via Apple Events (GetURL).
// Displays a modal HUD showing the URL, then dismisses after 4 seconds.

let app = NSApplication.shared
app.setActivationPolicy(.regular)

let screen = NSScreen.main ?? NSScreen.screens[0]
let sf = screen.frame
let dialogW: CGFloat = min(sf.width * 0.55, 620)

let bgColor = NSColor(white: 0.08, alpha: 0.93)

class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

let win = KeyableWindow(
    contentRect: NSRect(x: 0, y: 0, width: dialogW, height: 120),
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

let titleLabel = NSTextField(labelWithString: "URL Handler")
titleLabel.translatesAutoresizingMaskIntoConstraints = false
titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
titleLabel.textColor = NSColor(white: 1, alpha: 0.45)
cv.addSubview(titleLabel)

let urlLabel = NSTextField(wrappingLabelWithString: "Waiting for URL…")
urlLabel.translatesAutoresizingMaskIntoConstraints = false
urlLabel.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
urlLabel.textColor = NSColor.white
urlLabel.isEditable = false
urlLabel.isBordered = false
urlLabel.backgroundColor = .clear
urlLabel.maximumNumberOfLines = 4
cv.addSubview(urlLabel)

NSLayoutConstraint.activate([
    titleLabel.topAnchor.constraint(equalTo: cv.topAnchor, constant: 22),
    titleLabel.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 28),
    titleLabel.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -28),
    urlLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),
    urlLabel.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 28),
    urlLabel.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -28),
    urlLabel.bottomAnchor.constraint(equalTo: cv.bottomAnchor, constant: -22),
])

func showURL(_ urlString: String) {
    urlLabel.stringValue = urlString
    cv.layoutSubtreeIfNeeded()
    let fittingH = max(cv.fittingSize.height + 8, 100)
    let rect = NSRect(
        x: sf.midX - dialogW / 2,
        y: sf.midY - fittingH / 2 + 80,
        width: dialogW, height: fittingH)
    win.setFrame(rect, display: true)

    win.alphaValue = 0
    win.makeKeyAndOrderFront(nil)
    app.activate(ignoringOtherApps: true)
    NSAnimationContext.runAnimationGroup { ctx in
        ctx.duration = 0.15
        win.animator().alphaValue = 1
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            win.animator().alphaValue = 0
        }, completionHandler: {
            NSApp.terminate(nil)
        })
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ note: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURL(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL))
    }

    @objc func handleGetURL(_ event: NSAppleEventDescriptor, withReplyEvent: NSAppleEventDescriptor) {
        let urlString = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue ?? "(no URL)"
        showURL(urlString)
    }
}

let delegate = AppDelegate()
app.delegate = delegate
app.run()
