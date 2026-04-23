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
win.backgroundColor = NSColor(white: 0.08, alpha: 0.93)
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

let urlLabel = NSTextField(wrappingLabelWithString: "")
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

func launchCommandForSlot(_ index: Int) -> String? {
    let appsPath = NSHomeDirectory() + "/.config/hub/apps.json"
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: appsPath)),
          let apps = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
          index < apps.count,
          let launch = apps[index]["launch"] as? String
    else { return nil }
    return launch
}

func openURL(_ url: URL, withLaunchCommand launch: String) {
    let escaped = url.absoluteString.replacingOccurrences(of: "'", with: "'\\''")
    let cmd = "\(launch) '\(escaped)'"
    try? "cmd: \(cmd)\nurl: \(url.absoluteString)\n".appendLine(to: "/tmp/hub_handler.log")
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
    urlLabel.stringValue = "Opening \(urlString)"
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

    if let url = URL(string: urlString), let launch = launchCommandForSlot(1) {
        openURL(url, withLaunchCommand: launch)
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
