import Cocoa

// Cmd-Tab-style app switcher for the hub mini launch bar.
//
// Invoked by `hub app-switcher` when the user presses Alt-N. Shows a horizontal
// row of the launch-bar app icons with one highlighted. While the user keeps
// Alt (Option) held, each subsequent Alt-N press re-invokes `hub`, which signals
// this process (SIGUSR1) to advance the highlight. Releasing Alt commits the
// highlighted app; Esc cancels.
//
// Result: writes the chosen 1-based slot number to /tmp/hub-app-switcher-result
// and exits 0 on commit. On cancel, removes that file and exits 1.

let resultPath = "/tmp/hub-app-switcher-result"
let appsPath = ("~/.config/hub/apps.json" as NSString).expandingTildeInPath
let iconsDir = ("~/.config/hub/icons" as NSString).expandingTildeInPath

// --- Load apps from apps.json ---
struct AppEntry {
    let name: String
    let icon: String
}

func loadApps() -> [AppEntry] {
    guard let data = FileManager.default.contents(atPath: appsPath),
          let json = try? JSONSerialization.jsonObject(with: data),
          let arr = json as? [[String: Any]] else {
        return []
    }
    return arr.prefix(5).map { entry in
        let name = (entry["name"] as? String) ?? "?"
        let icon = (entry["icon"] as? String) ?? name
        return AppEntry(name: name, icon: icon)
    }
}

let apps = loadApps()
if apps.isEmpty {
    // Nothing to show — leave no result and exit as a cancel.
    try? FileManager.default.removeItem(atPath: resultPath)
    exit(1)
}

// --- Icon resolution: high-res app icon, then cached 36px PNG, then generic ---
func iconImage(for entry: AppEntry) -> NSImage {
    // Prefer the live app icon (crisp at any size) by resolving the app path.
    if let appPath = NSWorkspace.shared.fullPath(forApplication: entry.name) {
        let img = NSWorkspace.shared.icon(forFile: appPath)
        img.size = NSSize(width: 64, height: 64)
        return img
    }
    // Fall back to the cached PNG that `hub install` extracts.
    let png = "\(iconsDir)/\(entry.icon).png"
    if let img = NSImage(contentsOfFile: png) {
        return img
    }
    // Last resort: a generic application icon.
    let generic = NSWorkspace.shared.icon(forFileType: "app")
    generic.size = NSSize(width: 64, height: 64)
    return generic
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let screen = NSScreen.main ?? NSScreen.screens[0]
let sf = screen.frame

// --- Colors (matching hub palette) ---
let cardBg = NSColor(red: 0.08, green: 0.10, blue: 0.14, alpha: 0.96)
let tileIdle = NSColor(white: 1, alpha: 0.0)
let tileHi = NSColor(red: 0.20, green: 0.45, blue: 0.85, alpha: 0.95)
let labelColor = NSColor(white: 1, alpha: 0.92)

// --- Layout metrics ---
let tileSize: CGFloat = 80
let iconSize: CGFloat = 56
let tileGap: CGFloat = 12
let padding: CGFloat = 20
let labelH: CGFloat = 22

// One tile per app, plus a trailing ✕ "cancel" tile. Releasing Alt while the
// cancel tile is highlighted dismisses the switcher without launching anything.
let count = apps.count
let cancelIndex = count          // index of the cancel tile in the cycle
let tileCount = count + 1        // apps + cancel tile
let cardW = padding * 2 + CGFloat(tileCount) * tileSize + CGFloat(tileCount - 1) * tileGap
let cardH = padding * 2 + tileSize + labelH

let originX = sf.midX - cardW / 2
let originY = sf.midY - cardH / 2

class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

let win = KeyableWindow(
    contentRect: NSRect(x: originX, y: originY, width: cardW, height: cardH),
    styleMask: .borderless, backing: .buffered, defer: false)
win.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)
win.backgroundColor = cardBg
win.isOpaque = false
win.hasShadow = true
win.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

let cv = win.contentView!
cv.wantsLayer = true
cv.layer?.cornerRadius = 16
cv.layer?.masksToBounds = true
cv.layer?.borderWidth = 1
cv.layer?.borderColor = NSColor(white: 1, alpha: 0.08).cgColor

// --- Tiles ---
let cancelHi = NSColor(red: 0.80, green: 0.30, blue: 0.30, alpha: 0.95)

class Tile: NSView {
    let imageView = NSImageView()
    let isCancel: Bool
    init(image: NSImage, isCancel: Bool = false) {
        self.isCancel = isCancel
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.backgroundColor = tileIdle.cgColor
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: iconSize),
            imageView.heightAnchor.constraint(equalToConstant: iconSize),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
    func setHighlighted(_ on: Bool) {
        let hi = isCancel ? cancelHi : tileHi
        layer?.backgroundColor = (on ? hi : tileIdle).cgColor
    }
}

// Build a ✕ image for the cancel tile, drawn to match the icon footprint.
func cancelImage() -> NSImage {
    let img = NSImage(size: NSSize(width: iconSize, height: iconSize))
    img.lockFocus()
    let symbolColor = NSColor(white: 1, alpha: 0.85)
    let str = "✕" as NSString
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 34, weight: .regular),
        .foregroundColor: symbolColor,
    ]
    let size = str.size(withAttributes: attrs)
    let pt = NSPoint(x: (iconSize - size.width) / 2, y: (iconSize - size.height) / 2)
    str.draw(at: pt, withAttributes: attrs)
    img.unlockFocus()
    return img
}

let row = NSStackView()
row.orientation = .horizontal
row.distribution = .fillEqually
row.spacing = tileGap
row.translatesAutoresizingMaskIntoConstraints = false

var tiles: [Tile] = []
for entry in apps {
    let t = Tile(image: iconImage(for: entry))
    t.translatesAutoresizingMaskIntoConstraints = false
    t.widthAnchor.constraint(equalToConstant: tileSize).isActive = true
    t.heightAnchor.constraint(equalToConstant: tileSize).isActive = true
    tiles.append(t)
    row.addArrangedSubview(t)
}
// Trailing cancel tile.
let cancelTile = Tile(image: cancelImage(), isCancel: true)
cancelTile.translatesAutoresizingMaskIntoConstraints = false
cancelTile.widthAnchor.constraint(equalToConstant: tileSize).isActive = true
cancelTile.heightAnchor.constraint(equalToConstant: tileSize).isActive = true
tiles.append(cancelTile)
row.addArrangedSubview(cancelTile)
cv.addSubview(row)

let nameLabel = NSTextField(labelWithString: apps[0].name)
nameLabel.translatesAutoresizingMaskIntoConstraints = false
nameLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
nameLabel.textColor = labelColor
nameLabel.alignment = .center
cv.addSubview(nameLabel)

NSLayoutConstraint.activate([
    row.topAnchor.constraint(equalTo: cv.topAnchor, constant: padding),
    row.centerXAnchor.constraint(equalTo: cv.centerXAnchor),
    row.heightAnchor.constraint(equalToConstant: tileSize),

    nameLabel.topAnchor.constraint(equalTo: row.bottomAnchor, constant: 6),
    nameLabel.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: padding),
    nameLabel.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -padding),
])

// --- Selection state ---
var selected = 0
func setHighlight(_ index: Int) {
    for (i, t) in tiles.enumerated() { t.setHighlighted(i == index) }
    selected = index
    nameLabel.stringValue = (index == cancelIndex) ? "Cancel" : apps[index].name
}
setHighlight(0)

// --- Commit / cancel ---
var finished = false
func commit() {
    if finished { return }
    finished = true
    // Landing on the cancel tile launches nothing.
    if selected != cancelIndex {
        let slot = selected + 1  // apps.json is 0-based; hub slots are 1-based
        try? "\(slot)".write(toFile: resultPath, atomically: true, encoding: .utf8)
    } else {
        try? FileManager.default.removeItem(atPath: resultPath)
    }
    NSApp.terminate(nil)
}
func cancel() {
    if finished { return }
    finished = true
    try? FileManager.default.removeItem(atPath: resultPath)
    NSApp.terminate(nil)
}

// --- Advance on SIGUSR1 (sent by re-invoked `hub app-switcher`) ---
signal(SIGUSR1, SIG_IGN)
let sigSrc = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
sigSrc.setEventHandler {
    setHighlight((selected + 1) % tileCount)  // cycles apps then the cancel tile
}
sigSrc.resume()

// --- Esc to cancel ---
// NOTE: while Option is held, macOS claims Option+Esc ("Speak selection"), so
// Esc can't be the in-flight cancel — the trailing ✕ cancel tile handles that.
// Esc still works once Option is released, and Return commits.
NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
    if event.keyCode == 53 { cancel(); return nil }  // Esc
    if event.keyCode == 36 { commit(); return nil }  // Return also commits
    return event
}

// --- Commit when Option is released ---
// AeroSpace fires alt-n with Option held, so we watch the global modifier
// state. Once we've seen Option down, its release means "launch the selection".
var sawOption = false
var elapsed: TimeInterval = 0
let pollInterval: TimeInterval = 0.025
let fastTapWindow: TimeInterval = 0.45   // commit if Option never observed (tap+release before arm)
let safetyTimeout: TimeInterval = 15.0   // never linger forever

Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { _ in
    elapsed += pollInterval
    let optionDown = NSEvent.modifierFlags.contains(.option)
    if optionDown {
        sawOption = true
    } else if sawOption {
        commit()
    } else if elapsed >= fastTapWindow {
        // Option was never seen — user tapped and released before we armed.
        commit()
    }
    if elapsed >= safetyTimeout { cancel() }
}

win.alphaValue = 0
win.makeKeyAndOrderFront(nil)
DispatchQueue.main.async {
    app.activate(ignoringOtherApps: true)
    NSAnimationContext.runAnimationGroup { ctx in
        ctx.duration = 0.12
        win.animator().alphaValue = 1
    }
}

app.run()
