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

// ── App loading ──────────────────────────────────────────────────────────────

struct AppEntry {
    let name: String
    let icon: String
}

func loadApps() -> [AppEntry] {
    guard let data = FileManager.default.contents(atPath: appsPath),
          let json = try? JSONSerialization.jsonObject(with: data),
          let arr = json as? [[String: Any]] else { return [] }
    return arr.prefix(5).map { e in
        AppEntry(name: (e["name"] as? String) ?? "?", icon: (e["icon"] as? String) ?? "?")
    }
}

let apps = loadApps()
if apps.isEmpty {
    try? FileManager.default.removeItem(atPath: resultPath)
    exit(1)
}

// ── Icon resolution ───────────────────────────────────────────────────────────

func iconImage(for entry: AppEntry) -> NSImage {
    if let appPath = NSWorkspace.shared.fullPath(forApplication: entry.name) {
        let img = NSWorkspace.shared.icon(forFile: appPath)
        img.size = NSSize(width: 64, height: 64)
        return img
    }
    let png = "\(iconsDir)/\(entry.icon).png"
    if let img = NSImage(contentsOfFile: png) { return img }
    let generic = NSWorkspace.shared.icon(forFileType: "app")
    generic.size = NSSize(width: 64, height: 64)
    return generic
}

// ── Colors (all from Theme in theme.swift) ────────────────────────────────────

let CARD_BG      = Theme.Color.modalTop                    // #1C1E25 solid
let TITLE_COLOR  = Theme.Color.textPrimary
let TILE_HI_BG   = Theme.Color.accentBlue.withAlphaComponent(0.90)  // blue fill
let TILE_HI_GLOW = Theme.Color.accentBlue                             // glow
let CANCEL_HI    = Theme.Color.destructive.withAlphaComponent(0.85)
let CANCEL_GLOW  = Theme.Color.destructive

// ── Layout ────────────────────────────────────────────────────────────────────

let tileSize:    CGFloat = 80
let iconSize:    CGFloat = 56
let tileGap:     CGFloat = 8
let cardPadH:    CGFloat = 18    // horizontal inner padding
let cardPadV:    CGFloat = 14    // vertical inner padding
let cardRadius:  CGFloat = 20
let titleH:      CGFloat = 26    // title label height inside card
let titleGap:    CGFloat = 6     // gap between title and icon row
let hintH:       CGFloat = 28    // hint strip height outside card
let hintGap:     CGFloat = 10    // gap below card before hint
let monoFont   = Theme.Font.mono(13)
let monoFontSm = Theme.Font.mono(11)

let count        = apps.count
let cancelIndex  = count
let tileCount    = count + 1
let innerW       = CGFloat(tileCount) * tileSize + CGFloat(tileCount - 1) * tileGap
let cardW        = cardPadH * 2 + innerW
let cardH        = cardPadV + titleH + titleGap + tileSize + cardPadV
let winH         = cardH + hintGap + hintH

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let screen  = NSScreen.main ?? NSScreen.screens[0]
let sf      = screen.frame
let originX = sf.midX - cardW / 2
// Center over the bar (card is in upper portion of window)
let originY = sf.midY - cardH / 2 - hintGap - hintH

// ── Keycap view ───────────────────────────────────────────────────────────────

class KeycapView: NSView {
    init(text: String) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = Theme.Radius.keycap
        layer?.masksToBounds = true
        layer?.backgroundColor = Theme.Color.border.cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor(white: 1, alpha: 0.18).cgColor

        let lbl = NSTextField(labelWithString: text)
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.font = monoFontSm
        lbl.textColor = Theme.Color.textLabel
        lbl.isEditable = false; lbl.isBordered = false; lbl.backgroundColor = .clear
        lbl.alignment = .center
        addSubview(lbl)
        NSLayoutConstraint.activate([
            lbl.centerXAnchor.constraint(equalTo: centerXAnchor),
            lbl.centerYAnchor.constraint(equalTo: centerYAnchor),
            lbl.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            lbl.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
        ])
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
    }
    required init?(coder: NSCoder) { fatalError() }
}

// ── Tile (outer shadow + inner rounded clip) ──────────────────────────────────

class Tile: NSView {
    let isCancel: Bool
    private let innerView  = NSView()
    private let imageView  = NSImageView()

    init(image: NSImage, isCancel: Bool = false) {
        self.isCancel = isCancel
        super.init(frame: .zero)

        // Outer: unmasked, receives layer shadow
        wantsLayer = true
        layer?.masksToBounds = false
        layer?.shadowOpacity = 0

        // Inner: rounded, masked — no shadow bleeding through
        innerView.wantsLayer = true
        innerView.layer?.cornerRadius = 14
        innerView.layer?.masksToBounds = true
        innerView.layer?.backgroundColor = NSColor.clear.cgColor
        innerView.translatesAutoresizingMaskIntoConstraints = false

        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.translatesAutoresizingMaskIntoConstraints = false

        innerView.addSubview(imageView)
        addSubview(innerView)
        NSLayoutConstraint.activate([
            innerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            innerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            innerView.topAnchor.constraint(equalTo: topAnchor),
            innerView.bottomAnchor.constraint(equalTo: bottomAnchor),
            imageView.centerXAnchor.constraint(equalTo: innerView.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: innerView.centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: iconSize),
            imageView.heightAnchor.constraint(equalToConstant: iconSize),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func setHighlighted(_ on: Bool) {
        if on {
            let bg   = isCancel ? CANCEL_HI   : TILE_HI_BG
            let glow = isCancel ? CANCEL_GLOW : TILE_HI_GLOW
            innerView.layer?.backgroundColor = bg.cgColor
            layer?.shadowColor   = glow.cgColor
            layer?.shadowOpacity = 0.7
            layer?.shadowRadius  = 18
            layer?.shadowOffset  = .zero
        } else {
            innerView.layer?.backgroundColor = NSColor.clear.cgColor
            layer?.shadowOpacity = 0
        }
    }
}

// ── Window ────────────────────────────────────────────────────────────────────

class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

let win = KeyableWindow(
    contentRect: NSRect(x: originX, y: originY, width: cardW, height: winH),
    styleMask: .borderless, backing: .buffered, defer: false)
win.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)
win.backgroundColor = .clear
win.isOpaque = false
win.hasShadow = true
win.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

let wv = win.contentView!
wv.wantsLayer = true

// ── Card (lives at top of window) ─────────────────────────────────────────────

let cardFrame = NSRect(x: 0, y: winH - cardH, width: cardW, height: cardH)
let cardView  = NSView(frame: cardFrame)
cardView.wantsLayer = true
cardView.layer?.backgroundColor  = CARD_BG.cgColor
cardView.layer?.cornerRadius     = cardRadius
cardView.layer?.masksToBounds    = true
cardView.layer?.borderWidth      = 1
cardView.layer?.borderColor      = Theme.Color.borderStrong.cgColor
wv.addSubview(cardView)

// ── Title label (inside card, top-centered) ───────────────────────────────────

let nameLabel = NSTextField(labelWithString: apps[0].name)
nameLabel.translatesAutoresizingMaskIntoConstraints = false
nameLabel.font      = monoFont
nameLabel.textColor = TITLE_COLOR
nameLabel.alignment = .center
nameLabel.isEditable = false; nameLabel.isBordered = false; nameLabel.backgroundColor = .clear
cardView.addSubview(nameLabel)

// ── Tile row ──────────────────────────────────────────────────────────────────

let row = NSStackView()
row.orientation  = .horizontal
row.distribution = .fillEqually
row.spacing      = tileGap
row.translatesAutoresizingMaskIntoConstraints = false

var tiles: [Tile] = []
for entry in apps {
    let t = Tile(image: iconImage(for: entry))
    t.translatesAutoresizingMaskIntoConstraints = false
    t.widthAnchor.constraint(equalToConstant: tileSize).isActive  = true
    t.heightAnchor.constraint(equalToConstant: tileSize).isActive = true
    tiles.append(t)
    row.addArrangedSubview(t)
}

// Trailing ✕ cancel tile
func cancelImage() -> NSImage {
    let img = NSImage(size: NSSize(width: iconSize, height: iconSize))
    img.lockFocus()
    let str = "✕" as NSString
    let attrs: [NSAttributedString.Key: Any] = [
        .font: Theme.Font.ui(34, weight: .regular),
        .foregroundColor: Theme.Color.textPrimary,
    ]
    let sz = str.size(withAttributes: attrs)
    str.draw(at: NSPoint(x: (iconSize - sz.width) / 2, y: (iconSize - sz.height) / 2), withAttributes: attrs)
    img.unlockFocus()
    return img
}

let cancelTile = Tile(image: cancelImage(), isCancel: true)
cancelTile.translatesAutoresizingMaskIntoConstraints = false
cancelTile.widthAnchor.constraint(equalToConstant: tileSize).isActive  = true
cancelTile.heightAnchor.constraint(equalToConstant: tileSize).isActive = true
tiles.append(cancelTile)
row.addArrangedSubview(cancelTile)
cardView.addSubview(row)

NSLayoutConstraint.activate([
    // Title: top of card + padding, full width
    nameLabel.topAnchor.constraint(equalTo: cardView.topAnchor, constant: cardPadV),
    nameLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: cardPadH),
    nameLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -cardPadH),
    nameLabel.heightAnchor.constraint(equalToConstant: titleH),

    // Icon row: below the title
    row.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: titleGap),
    row.centerXAnchor.constraint(equalTo: cardView.centerXAnchor),
    row.heightAnchor.constraint(equalToConstant: tileSize),
])

// ── Keycap hint strip (below card, inside transparent window) ─────────────────

// "Hold  [⌥]  +  [N]  to cycle, release to launch"
let hintStack = NSStackView()
hintStack.orientation = .horizontal
hintStack.spacing     = 5
hintStack.alignment   = .centerY
hintStack.translatesAutoresizingMaskIntoConstraints = false

func dimLabel(_ text: String) -> NSTextField {
    let lbl = NSTextField(labelWithString: text)
    lbl.font = monoFontSm
    lbl.textColor = Theme.Color.textFaint
    lbl.isEditable = false; lbl.isBordered = false; lbl.backgroundColor = .clear
    return lbl
}

hintStack.addArrangedSubview(dimLabel("Hold"))
hintStack.addArrangedSubview(KeycapView(text: "⌥ Alt"))
hintStack.addArrangedSubview(dimLabel("+"))
hintStack.addArrangedSubview(KeycapView(text: "N"))
hintStack.addArrangedSubview(dimLabel("to cycle, release to launch"))

wv.addSubview(hintStack)
NSLayoutConstraint.activate([
    hintStack.centerXAnchor.constraint(equalTo: wv.centerXAnchor),
    // cardH pixels below the top of the content view (which is flipped in AutoLayout)
    hintStack.topAnchor.constraint(equalTo: wv.topAnchor, constant: cardH + hintGap),
    hintStack.heightAnchor.constraint(equalToConstant: hintH),
])

// ── Selection state ───────────────────────────────────────────────────────────

var selected = 0
func setHighlight(_ index: Int) {
    for (i, t) in tiles.enumerated() { t.setHighlighted(i == index) }
    selected = index
    if index == cancelIndex {
        nameLabel.stringValue = "Cancel"
        nameLabel.textColor   = Theme.Color.textMuted
    } else {
        nameLabel.stringValue = apps[index].name
        nameLabel.textColor   = TITLE_COLOR
    }
}
setHighlight(0)

// ── Commit / cancel ───────────────────────────────────────────────────────────

var finished = false
func commit() {
    if finished { return }
    finished = true
    if selected != cancelIndex {
        let slot = selected + 1
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

// ── SIGUSR1 to advance ────────────────────────────────────────────────────────

signal(SIGUSR1, SIG_IGN)
let sigSrc = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
sigSrc.setEventHandler { setHighlight((selected + 1) % tileCount) }
sigSrc.resume()

// ── Key events ────────────────────────────────────────────────────────────────

NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
    if event.keyCode == 53 { cancel(); return nil }   // Esc
    if event.keyCode == 36 { commit(); return nil }   // Return
    return event
}

// ── Option-release commit ─────────────────────────────────────────────────────

var sawOption         = false
var elapsed: TimeInterval = 0
let pollInterval: TimeInterval  = 0.025
let fastTapWindow: TimeInterval = 0.45
let safetyTimeout: TimeInterval = 15.0

Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { _ in
    elapsed += pollInterval
    let optionDown = NSEvent.modifierFlags.contains(.option)
    if optionDown          { sawOption = true }
    else if sawOption      { commit() }
    else if elapsed >= fastTapWindow { commit() }
    if elapsed >= safetyTimeout { cancel() }
}

// ── Show with fade ────────────────────────────────────────────────────────────

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
