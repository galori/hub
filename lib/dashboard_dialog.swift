import Cocoa

// Dashboard modal for hub — reads two temp files passed as argv[1] (status) and argv[2] (keys).
// The files are written by background shell jobs; a corresponding .done sentinel signals completion.
// Shows immediately with spinners, then renders content when each pane's data is ready.
// Dismiss with Escape, Enter, Space, or Q.

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let screen = NSScreen.main ?? NSScreen.screens[0]
let sf = screen.frame

let statusPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ""
let keysPath   = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : ""

// --- Colors ---
let bgColor   = NSColor(white: 0.08, alpha: 0.96)
let divColor  = NSColor(white: 1, alpha: 0.08)
let baseColor = NSColor(red: 0.89, green: 0.89, blue: 0.89, alpha: 1)

let ansiColors: [String: NSColor] = [
    "31": NSColor(red: 0.86, green: 0.38, blue: 0.36, alpha: 1),
    "32": NSColor(red: 0.62, green: 0.82, blue: 0.45, alpha: 1),
    "33": NSColor(red: 0.95, green: 0.78, blue: 0.40, alpha: 1),
    "34": NSColor(red: 0.20, green: 0.55, blue: 0.95, alpha: 1),
    "36": NSColor(red: 0.30, green: 0.78, blue: 0.85, alpha: 1),
]

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
                case "0":  bold = false; dim = false; color = nil
                case "1":  bold = true
                case "2":  dim  = true
                default:   color = ansiColors[code]
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

let pad: CGFloat  = 32
let winW: CGFloat = sf.width - 60
let winH: CGFloat = min(sf.height * 0.88, 1000)

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

NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
    let k = event.keyCode
    if k == 53 || k == 36 || k == 49 || k == 12 { dismiss() }
    return event
}

class ClickView: NSView {
    override func mouseDown(with event: NSEvent) { dismiss() }
}
let clickView = ClickView(frame: sf)
backdrop.contentView = clickView

// --- Scroll pane factory (no-wrap, horizontal scroll) ---
func makeScrollPane() -> (NSScrollView, NSTextView) {
    let sv = NSScrollView()
    sv.translatesAutoresizingMaskIntoConstraints = false
    sv.hasVerticalScroller = true
    sv.hasHorizontalScroller = true
    sv.autohidesScrollers = true
    sv.drawsBackground = false
    sv.borderType = .noBorder

    let tv = NSTextView(frame: .zero)
    tv.isEditable = false
    tv.isSelectable = true
    tv.drawsBackground = false
    tv.isVerticallyResizable = true
    tv.isHorizontallyResizable = true
    tv.autoresizingMask = []
    tv.textContainerInset = NSSize(width: 4, height: 8)
    tv.textContainer?.widthTracksTextView = false
    tv.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                              height: CGFloat.greatestFiniteMagnitude)
    tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

    sv.documentView = tv
    return (sv, tv)
}

func makeSpinner() -> NSProgressIndicator {
    let s = NSProgressIndicator()
    s.translatesAutoresizingMaskIntoConstraints = false
    s.style = .spinning
    s.controlSize = .regular
    s.startAnimation(nil)
    return s
}

// --- Title bar ---
let titleBar = NSView()
titleBar.translatesAutoresizingMaskIntoConstraints = false
cv.addSubview(titleBar)

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
class ClickLabel: NSTextField {
    override func mouseDown(with event: NSEvent) { dismiss() }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
}

let statusTitle = makeTitle("status")
let keysTitle   = makeTitle("keys")
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

// --- Panes ---
let baseFont = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)

let statusPane = NSView()
statusPane.translatesAutoresizingMaskIntoConstraints = false
let keysPane = NSView()
keysPane.translatesAutoresizingMaskIntoConstraints = false

let statusSpinner = makeSpinner()
let (statusScroll, statusTextView) = makeScrollPane()
statusScroll.isHidden = true

let keysSpinner = makeSpinner()
let (keysScroll, keysTextView) = makeScrollPane()
keysScroll.isHidden = true

cv.addSubview(statusPane)
cv.addSubview(keysPane)
for v in [statusSpinner, statusScroll] as [NSView] { statusPane.addSubview(v) }
for v in [keysSpinner, keysScroll] as [NSView] { keysPane.addSubview(v) }

// --- Constraints ---
let titleH: CGFloat = 40

NSLayoutConstraint.activate([
    titleBar.topAnchor.constraint(equalTo: cv.topAnchor),
    titleBar.leadingAnchor.constraint(equalTo: cv.leadingAnchor),
    titleBar.trailingAnchor.constraint(equalTo: cv.trailingAnchor),
    titleBar.heightAnchor.constraint(equalToConstant: titleH),

    titleBorder.topAnchor.constraint(equalTo: titleBar.bottomAnchor),
    titleBorder.leadingAnchor.constraint(equalTo: cv.leadingAnchor),
    titleBorder.trailingAnchor.constraint(equalTo: cv.trailingAnchor),
    titleBorder.heightAnchor.constraint(equalToConstant: 1),

    statusTitle.centerYAnchor.constraint(equalTo: titleBar.centerYAnchor),
    statusTitle.leadingAnchor.constraint(equalTo: titleBar.leadingAnchor, constant: pad),

    divider.topAnchor.constraint(equalTo: titleBorder.bottomAnchor),
    divider.bottomAnchor.constraint(equalTo: cv.bottomAnchor),
    divider.centerXAnchor.constraint(equalTo: cv.centerXAnchor),
    divider.widthAnchor.constraint(equalToConstant: 1),

    keysTitle.centerYAnchor.constraint(equalTo: titleBar.centerYAnchor),
    keysTitle.leadingAnchor.constraint(equalTo: divider.trailingAnchor, constant: pad),

    hint.centerYAnchor.constraint(equalTo: titleBar.centerYAnchor),
    hint.trailingAnchor.constraint(equalTo: titleBar.trailingAnchor, constant: -pad),

    // Status pane container (left)
    statusPane.topAnchor.constraint(equalTo: titleBorder.bottomAnchor, constant: 8),
    statusPane.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: pad),
    statusPane.trailingAnchor.constraint(equalTo: divider.leadingAnchor, constant: -pad/2),
    statusPane.bottomAnchor.constraint(equalTo: cv.bottomAnchor, constant: -pad/2),
    // Spinner centered in pane
    statusSpinner.centerXAnchor.constraint(equalTo: statusPane.centerXAnchor),
    statusSpinner.topAnchor.constraint(equalTo: statusPane.topAnchor, constant: 40),
    // Scroll fills pane
    statusScroll.topAnchor.constraint(equalTo: statusPane.topAnchor),
    statusScroll.leadingAnchor.constraint(equalTo: statusPane.leadingAnchor),
    statusScroll.trailingAnchor.constraint(equalTo: statusPane.trailingAnchor),
    statusScroll.bottomAnchor.constraint(equalTo: statusPane.bottomAnchor),

    // Keys pane container (right)
    keysPane.topAnchor.constraint(equalTo: titleBorder.bottomAnchor, constant: 8),
    keysPane.leadingAnchor.constraint(equalTo: divider.trailingAnchor, constant: pad/2),
    keysPane.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -pad),
    keysPane.bottomAnchor.constraint(equalTo: cv.bottomAnchor, constant: -pad/2),
    // Spinner centered in pane
    keysSpinner.centerXAnchor.constraint(equalTo: keysPane.centerXAnchor),
    keysSpinner.topAnchor.constraint(equalTo: keysPane.topAnchor, constant: 40),
    // Scroll fills pane
    keysScroll.topAnchor.constraint(equalTo: keysPane.topAnchor),
    keysScroll.leadingAnchor.constraint(equalTo: keysPane.leadingAnchor),
    keysScroll.trailingAnchor.constraint(equalTo: keysPane.trailingAnchor),
    keysScroll.bottomAnchor.constraint(equalTo: keysPane.bottomAnchor),
])

// --- Show immediately ---
win.alphaValue = 0
win.makeKeyAndOrderFront(nil)
app.activate(ignoringOtherApps: true)
NSAnimationContext.runAnimationGroup { ctx in
    ctx.duration = 0.18
    win.animator().alphaValue = 1
    backdrop.animator().alphaValue = 1
}

// --- Poll for content ---
var statusLoaded = false
var keysLoaded = false
let fm = FileManager.default

func loadPane(path: String, textView: NSTextView, scroll: NSScrollView, spinner: NSProgressIndicator) -> Bool {
    guard fm.fileExists(atPath: path + ".done"),
          let content = try? String(contentsOfFile: path, encoding: .utf8),
          !content.isEmpty else { return false }
    let attr = ansiToAttributedString(content, baseFont: baseFont)
    textView.textStorage?.setAttributedString(attr)
    textView.sizeToFit()
    spinner.stopAnimation(nil)
    spinner.isHidden = true
    scroll.isHidden = false
    return true
}

let pollTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { timer in
    if !statusLoaded { statusLoaded = loadPane(path: statusPath, textView: statusTextView, scroll: statusScroll, spinner: statusSpinner) }
    if !keysLoaded   { keysLoaded   = loadPane(path: keysPath,   textView: keysTextView,   scroll: keysScroll,   spinner: keysSpinner) }
    if statusLoaded && keysLoaded { timer.invalidate() }
}
RunLoop.main.add(pollTimer, forMode: .common)

app.run()
