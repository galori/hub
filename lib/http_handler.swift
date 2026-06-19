import Cocoa

// HTTP/HTTPS handler for hub.
// Persistent daemon: launched by `hub up`, killed by `hub down`.
// Receives URLs via Apple Events (GetURL), shows a brief HUD, opens the URL
// in the browser configured in slot 2 of ~/.config/hub/apps.json.

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let screen = NSScreen.main ?? NSScreen.screens[0]
let sf = screen.frame
let dialogW: CGFloat = min(sf.width * 0.55, 620)

class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

let win = KeyableWindow(
    contentRect: NSRect(x: 0, y: 0, width: dialogW, height: 120),
    styleMask: .borderless, backing: .buffered, defer: false)
win.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)
win.backgroundColor = .clear
win.isOpaque = false
win.hasShadow = true
win.collectionBehavior = [.canJoinAllSpaces, .stationary]

let cv = win.contentView!
Theme.applyCardBackground(to: cv, radius: Theme.Radius.modal, kind: .modal)

let titleLabel = NSTextField(labelWithString: "[hub]")
titleLabel.translatesAutoresizingMaskIntoConstraints = false
titleLabel.font = Theme.Font.mono(11, weight: .semibold)
titleLabel.textColor = Theme.Color.textMuted
cv.addSubview(titleLabel)

let urlLabel = NSTextField(wrappingLabelWithString: "")
urlLabel.translatesAutoresizingMaskIntoConstraints = false
urlLabel.font = Theme.Font.mono(14)
urlLabel.textColor = Theme.Color.textPrimary
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

func hubScriptPath() -> String? {
    let path = NSHomeDirectory() + "/.config/hub/hub_path"
    guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
    return content.trimmingCharacters(in: .whitespacesAndNewlines)
}

func focusedWorkspaceID() -> String? {
    let aerospace = FileManager.default.fileExists(atPath: "/opt/homebrew/bin/aerospace")
        ? "/opt/homebrew/bin/aerospace" : "/usr/local/bin/aerospace"
    let p = Process()
    p.launchPath = aerospace
    p.arguments = ["list-workspaces", "--focused"]
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = Pipe()
    try? p.run()
    p.waitUntilExit()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let out = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return out.isEmpty ? nil : out
}

func openURL(_ url: URL) {
    let urlString = url.absoluteString
    // Capture the focused workspace NOW (synchronously, before launching the
    // browser) so the new window is corralled to where the user actually is.
    // Delegate the launch + corral to `hub open-url`, which reuses the same
    // launch/poll/move-to-workspace logic as the keyboard launcher.
    guard let hub = hubScriptPath() else {
        try? "error: hub_path not found; cannot open \(urlString)\n".appendLine(to: "/tmp/hub_handler.log")
        return
    }
    let wsID = focusedWorkspaceID() ?? ""
    let escapedURL = urlString.replacingOccurrences(of: "'", with: "'\\''")
    let escapedWS = wsID.replacingOccurrences(of: "'", with: "'\\''")
    let cmd = "'\(hub)' open-url '\(escapedURL)' '\(escapedWS)'"
    try? "cmd: \(cmd)\nurl: \(urlString)\nws: \(wsID)\n".appendLine(to: "/tmp/hub_handler.log")
    Process.launchedProcess(launchPath: "/bin/sh", arguments: ["-c", cmd])
}

extension String {
    func appendLine(to path: String) throws {
        let data = (self).data(using: .utf8)!
        if let fh = FileHandle(forWritingAtPath: path) {
            fh.seekToEndOfFile(); fh.write(data); fh.closeFile()
        } else {
            try data.write(to: URL(fileURLWithPath: path))
        }
    }
}

var hideWork: DispatchWorkItem?

func showURL(_ urlString: String) {
    urlLabel.stringValue = "Opening URL in current workspace: \(urlString)"
    cv.layoutSubtreeIfNeeded()
    let fittingH = max(cv.fittingSize.height + 8, 100)
    let rect = NSRect(
        x: sf.midX - dialogW / 2,
        y: sf.midY - fittingH / 2 + 80,
        width: dialogW, height: fittingH)
    win.setFrame(rect, display: true)

    if !win.isVisible {
        win.alphaValue = 0
        win.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            win.animator().alphaValue = 1
        }
    }

    if let url = URL(string: urlString) {
        openURL(url)
    }

    hideWork?.cancel()
    let work = DispatchWorkItem {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            win.animator().alphaValue = 0
        }, completionHandler: {
            win.orderOut(nil)
        })
    }
    hideWork = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
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
        try? "received: \(urlString)\n".appendLine(to: "/tmp/hub_handler.log")
        showURL(urlString)
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        showURL(URL(fileURLWithPath: filename).absoluteString)
        return true
    }
}

let delegate = AppDelegate()
app.delegate = delegate
app.run()
