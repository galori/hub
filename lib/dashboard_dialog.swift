import Cocoa

// Dashboard modal for helm — reads two temp files passed as argv[1] (status) and argv[2] (keys),
// renders ANSI formatting side-by-side. Dismiss with Escape, Enter, Space, or Q.

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let screen = NSScreen.main ?? NSScreen.screens[0]
let sf = screen.frame

let statusPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ""
let keysPath   = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : ""

let statusRaw = (try? String(contentsOfFile: statusPath, encoding: .utf8)) ?? ""
let keysRaw   = (try? String(contentsOfFile: keysPath,   encoding: .utf8)) ?? ""

// --- Colors ---
let bgColor    = NSColor(white: 0.08, alpha: 0.96)
let divColor   = NSColor(white: 1, alpha: 0.08)
let baseColor  = NSColor(red: 0.89, green: 0.89, blue: 0.89, alpha: 1)

// ANSI color palette matching helm
let ansiColors: [String: NSColor] = [
    "31": NSColor(red: 0.86, green: 0.38, blue: 0.36, alpha: 1), // red
    "32": NSColor(red: 0.62, green: 0.82, blue: 0.45, alpha: 1), // green
    "33": NSColor(red: 0.95, green: 0.78, blue: 0.40, alpha: 1), // yellow
    "34": NSColor(red: 0.20, green: 0.55, blue: 0.95, alpha: 1), // blue
    "36": NSColor(red: 0.30, green: 0.78, blue: 0.85, alpha: 1), // cyan
]

// --- ANSI parser ---
func ansiToAttributedString(_ input: String, baseFont: NSFont) -> NSAttributedString {
    let result = NSMutableAttributedString()
    var bold = false
    var dim  = false
    var color: NSColor? = nil

    func attrs() -> [NSAttributedString.Key: Any] {
        let f = bold
            ? NSFontManager.shared.convert(baseFont, toHaveTrait: .boldFontMask)
            : baseFont
        let c = (color ?? baseColor).withAlphaComponent(dim ? 0.45 : 1.0)
        return [.font: f, .foregroundColor: c]
    }

    var i = input.startIndex
    while i < input.endIndex {
        if input[i] == "\u{001B}", input.index(after: i) < input.endIndex,
           input[input.index(after: i)] == "[" {
            var j = input.index(i, offsetBy: 2)
            var code = ""
            while j < input.endIndex && input[j] != "m" {
                code.append(input[j])
                j = input.index(after: j)
            }
            if j < input.endIndex {
                switch code {
                case "0":        bold = false; dim = false; color = nil
                case "1":        bold = true
                case "2":        dim  = true
                default:         color = ansiColors[code]
                }
                i = input.index(after: j)
                continue
            }
        }
        result.append(NSAttributedString(string: String(input[i]), attributes: attrs()))
        i = input.index(after: i)
    }
    return result
}

// --- Window ---
class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

let pad: CGFloat   = 32
let winW: CGFloat  = min(sf.width  * 0.88, 1400)
let winH: CGFloat  = min(sf.height * 0.82, 900)

let win = KeyableWindow(
    contentRect: NSRect(x: sf.midX - winW/2, y: sf.midY - winH/2, width: winW, height: winH),
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

// --- Backdrop ---
let backdrop: NSWindow = {
    let w = NSWindow(contentRect: sf, styleMask: .borderless, backing: .buffered, defer: false)
    w.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
    w.backgroundColor = NSColor(white: 0, alpha: 0.75)
    w.isOpaque = false
    w.hasShadow = false
    w.collectionBehavior = [.canJoinAllSpaces, .stationary]
    w.alphaValue = 0
    w.orderFrontRegardless()
    return w
}()

func dismiss() {
    NSAnimationContext.runAnimationGroup({ ctx in
        ctx.duration = 0.2
        win.animator().alphaValue = 0
        backdrop.animator().alphaValue = 0
    }, completionHandler: { NSApp.terminate(nil) })
}

// Global key monitor — catches Escape/Enter/Space/Q regardless of which subview has focus
NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
    let k = event.keyCode
    if k == 53 || k == 36 || k == 49 || k == 12 { dismiss() }
    return event
}

// Click on backdrop dismisses
class ClickView: NSView {
    override func mouseDown(with event: NSEvent) { dismiss() }
}
let clickView = ClickView(frame: sf)
backdrop.contentView = clickView

// --- Layout helpers ---
func makeScrollView(attributed: NSAttributedString) -> NSScrollView {
    let sv = NSScrollView()
    sv.translatesAutoresizingMaskIntoConstraints = false
    sv.hasVerticalScroller = true
    sv.hasHorizontalScroller = false
    sv.drawsBackground = false
    sv.borderType = .noBorder

    let tv = NSTextView()
    tv.isEditable = false
    tv.isSelectable = true
    tv.drawsBackground = false
    tv.textContainerInset = NSSize(width: 4, height: 8)
    tv.textContainer?.widthTracksTextView = true
    tv.textStorage?.setAttributedString(attributed)
    tv.textContainer?.lineBreakMode = .byCharWrapping

    sv.documentView = tv

    // Size tv to content
    tv.sizeToFit()
    return sv
}

// --- Title bar ---
let titleBar = NSView()
titleBar.translatesAutoresizingMaskIntoConstraints = false
cv.addSubview(titleBar)

// Bottom border line under title bar
let titleBorder = NSView()
titleBorder.translatesAutoresizingMaskIntoConstraints = false
titleBorder.wantsLayer = true
titleBorder.layer?.backgroundColor = divColor.cgColor
cv.addSubview(titleBorder)

func makeTitle(_ text: String) -> NSTextField {
    let t = NSTextField(labelWithString: text)
    t.translatesAutoresizingMaskIntoConstraints = false
    t.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
    t.textColor = NSColor(white: 1, alpha: 0.50)
    return t
}

let statusTitle = makeTitle("status")
let keysTitle   = makeTitle("keys")

class ClickLabel: NSTextField {
    override func mouseDown(with event: NSEvent) { dismiss() }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
}
let hint = ClickLabel(labelWithString: "esc to close")
hint.translatesAutoresizingMaskIntoConstraints = false
hint.font = NSFont.systemFont(ofSize: 11, weight: .regular)
hint.textColor = NSColor(white: 1, alpha: 0.50)

titleBar.addSubview(statusTitle)
titleBar.addSubview(keysTitle)
titleBar.addSubview(hint)

// --- Divider ---
let divider = NSView()
divider.translatesAutoresizingMaskIntoConstraints = false
divider.wantsLayer = true
divider.layer?.backgroundColor = divColor.cgColor
cv.addSubview(divider)

// --- Content panes ---
let baseFont = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
let statusAttr = ansiToAttributedString(statusRaw, baseFont: baseFont)
let keysAttr   = ansiToAttributedString(keysRaw,   baseFont: baseFont)

let statusScroll = makeScrollView(attributed: statusAttr)
let keysScroll   = makeScrollView(attributed: keysAttr)
cv.addSubview(statusScroll)
cv.addSubview(keysScroll)

// --- Constraints ---
let titleH: CGFloat = 40

NSLayoutConstraint.activate([
    // title bar
    titleBar.topAnchor.constraint(equalTo: cv.topAnchor),
    titleBar.leadingAnchor.constraint(equalTo: cv.leadingAnchor),
    titleBar.trailingAnchor.constraint(equalTo: cv.trailingAnchor),
    titleBar.heightAnchor.constraint(equalToConstant: titleH),

    // title border
    titleBorder.topAnchor.constraint(equalTo: titleBar.bottomAnchor),
    titleBorder.leadingAnchor.constraint(equalTo: cv.leadingAnchor),
    titleBorder.trailingAnchor.constraint(equalTo: cv.trailingAnchor),
    titleBorder.heightAnchor.constraint(equalToConstant: 1),

    // status title — left column
    statusTitle.centerYAnchor.constraint(equalTo: titleBar.centerYAnchor),
    statusTitle.leadingAnchor.constraint(equalTo: titleBar.leadingAnchor, constant: pad),

    // divider — vertical, center
    divider.topAnchor.constraint(equalTo: titleBorder.bottomAnchor),
    divider.bottomAnchor.constraint(equalTo: cv.bottomAnchor),
    divider.centerXAnchor.constraint(equalTo: cv.centerXAnchor),
    divider.widthAnchor.constraint(equalToConstant: 1),

    // keys title — right column
    keysTitle.centerYAnchor.constraint(equalTo: titleBar.centerYAnchor),
    keysTitle.leadingAnchor.constraint(equalTo: divider.trailingAnchor, constant: pad),

    // hint — far right
    hint.centerYAnchor.constraint(equalTo: titleBar.centerYAnchor),
    hint.trailingAnchor.constraint(equalTo: titleBar.trailingAnchor, constant: -pad),

    // status scroll — left pane
    statusScroll.topAnchor.constraint(equalTo: titleBorder.bottomAnchor, constant: 8),
    statusScroll.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: pad),
    statusScroll.trailingAnchor.constraint(equalTo: divider.leadingAnchor, constant: -pad/2),
    statusScroll.bottomAnchor.constraint(equalTo: cv.bottomAnchor, constant: -pad/2),

    // keys scroll — right pane
    keysScroll.topAnchor.constraint(equalTo: titleBorder.bottomAnchor, constant: 8),
    keysScroll.leadingAnchor.constraint(equalTo: divider.trailingAnchor, constant: pad/2),
    keysScroll.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -pad),
    keysScroll.bottomAnchor.constraint(equalTo: cv.bottomAnchor, constant: -pad/2),
])

// --- Show ---
win.alphaValue = 0
win.orderFrontRegardless()
win.makeFirstResponder(nil)
NSAnimationContext.runAnimationGroup { ctx in
    ctx.duration = 0.18
    win.animator().alphaValue = 1
    backdrop.animator().alphaValue = 1
}

app.run()
