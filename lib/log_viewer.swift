import Cocoa

// Fix selection highlight on dark background — default macOS selection is unreadable.
class LogTextView: NSTextView {
    override var selectedTextAttributes: [NSAttributedString.Key: Any] {
        get { [.backgroundColor: NSColor(red: 0.15, green: 0.35, blue: 0.60, alpha: 0.75)] }
        set { }
    }
}


let app = NSApplication.shared
app.setActivationPolicy(.regular)

let menuBar = NSMenu()
let appMenuItem = NSMenuItem(); menuBar.addItem(appMenuItem)
let appMenu = NSMenu(); appMenuItem.submenu = appMenu
appMenu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
let fileMenuItem = NSMenuItem(); menuBar.addItem(fileMenuItem)
let fileMenu = NSMenu(title: "File"); fileMenuItem.submenu = fileMenu
fileMenu.addItem(NSMenuItem(title: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
let editMenuItem = NSMenuItem(); menuBar.addItem(editMenuItem)
let editMenu = NSMenu(title: "Edit"); editMenuItem.submenu = editMenu
editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
app.mainMenu = menuBar

let args = CommandLine.arguments
guard args.count > 1 else {
    fputs("Usage: log_viewer <path-to-log-file>\n", stderr)
    exit(1)
}
let logPath = args[1]

let statusBarHeight: CGFloat = 26
var isWrapped = false

let win = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
    styleMask: [.titled, .closable, .resizable, .miniaturizable],
    backing: .buffered,
    defer: false)
win.title = "Hub Log"
win.backgroundColor = Theme.Color.canvas
win.isMovableByWindowBackground = true
win.center()
win.makeKeyAndOrderFront(nil)
app.activate(ignoringOtherApps: true)

NotificationCenter.default.addObserver(
    forName: NSWindow.willCloseNotification, object: win, queue: .main) { _ in
    NSApp.terminate(nil)
}

// --- Status bar: path label + Wrap toggle button (Auto Layout) ---
let statusBarView = NSView()
statusBarView.wantsLayer = true
statusBarView.layer?.backgroundColor = Theme.Color.panelBot.cgColor
statusBarView.translatesAutoresizingMaskIntoConstraints = false

let pathLabel = NSTextField()
pathLabel.isEditable = false; pathLabel.isSelectable = false; pathLabel.isBordered = false
pathLabel.backgroundColor = .clear
pathLabel.textColor = Theme.Color.textMuted
pathLabel.font = Theme.Font.mono(11)
pathLabel.stringValue = logPath
pathLabel.lineBreakMode = .byTruncatingMiddle
pathLabel.translatesAutoresizingMaskIntoConstraints = false

// Use a custom NSView pill button — NSButton bezel styles are invisible on dark views
class PillButton: NSView {
    var action: () -> Void = {}
    var isActive = false {
        didSet { needsDisplay = true }
    }
    private let label = NSTextField()

    init(title: String) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 4
        label.stringValue = title
        label.isEditable = false
        label.isSelectable = false
        label.isBordered = false
        label.backgroundColor = .clear
        label.textColor = Theme.Color.textMuted
        label.font = Theme.Font.mono(11, weight: .medium)
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        let click = NSClickGestureRecognizer(target: self, action: #selector(handleClick))
        addGestureRecognizer(click)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let bg = isActive ? Theme.Color.accentBlue.withAlphaComponent(0.85) : Theme.Color.inputField
        bg.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4).fill()
        Theme.Color.border.setStroke()
        let border = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4)
        border.lineWidth = 0.5
        border.stroke()
        label.textColor = isActive ? Theme.Color.textPrimary : Theme.Color.textMuted
    }

    @objc private func handleClick() { action() }
}

let wrapBtn = PillButton(title: "Wrap")
wrapBtn.translatesAutoresizingMaskIntoConstraints = false

statusBarView.addSubview(pathLabel)
statusBarView.addSubview(wrapBtn)

let cv = win.contentView!
cv.addSubview(statusBarView)

NSLayoutConstraint.activate([
    // status bar: pinned to bottom of content view, full width, fixed height
    statusBarView.leadingAnchor.constraint(equalTo: cv.leadingAnchor),
    statusBarView.trailingAnchor.constraint(equalTo: cv.trailingAnchor),
    statusBarView.bottomAnchor.constraint(equalTo: cv.bottomAnchor),
    statusBarView.heightAnchor.constraint(equalToConstant: statusBarHeight),
    // path label: left edge to right edge of button
    pathLabel.leadingAnchor.constraint(equalTo: statusBarView.leadingAnchor, constant: 8),
    pathLabel.centerYAnchor.constraint(equalTo: statusBarView.centerYAnchor),
    pathLabel.trailingAnchor.constraint(equalTo: wrapBtn.leadingAnchor, constant: -6),
    // wrap button: fixed size, pinned to right
    wrapBtn.trailingAnchor.constraint(equalTo: statusBarView.trailingAnchor, constant: -8),
    wrapBtn.centerYAnchor.constraint(equalTo: statusBarView.centerYAnchor),
    wrapBtn.widthAnchor.constraint(equalToConstant: 46),
    wrapBtn.heightAnchor.constraint(equalToConstant: 18),
])

// --- Scroll + text view ---
let scrollView = NSScrollView()
scrollView.hasVerticalScroller = true
scrollView.drawsBackground = false
scrollView.translatesAutoresizingMaskIntoConstraints = false

let textView = LogTextView(frame: scrollView.contentView.bounds)
textView.isEditable = false
textView.isSelectable = true
textView.backgroundColor = Theme.Color.canvas
textView.textColor = Theme.Color.textPrimary
textView.font = Theme.Font.mono(12)
textView.isVerticallyResizable = true
textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
textView.textContainerInset = NSSize(width: 10, height: 10)

scrollView.documentView = textView
cv.addSubview(scrollView)

NSLayoutConstraint.activate([
    scrollView.leadingAnchor.constraint(equalTo: cv.leadingAnchor),
    scrollView.trailingAnchor.constraint(equalTo: cv.trailingAnchor),
    scrollView.topAnchor.constraint(equalTo: cv.topAnchor),
    scrollView.bottomAnchor.constraint(equalTo: statusBarView.topAnchor),
])

// Apply wrap/no-wrap layout to scroll + text view.
func applyWrapMode() {
    if isWrapped {
        scrollView.hasHorizontalScroller = false
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
    } else {
        scrollView.hasHorizontalScroller = true
        textView.isHorizontallyResizable = true
        textView.autoresizingMask = []
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    }
    wrapBtn.isActive = isWrapped
    scrollView.tile()
}

wrapBtn.action = {
    isWrapped = !isWrapped
    applyWrapMode()
    loadFile()
}

applyWrapMode()

// --- ANSI color parsing (uses Theme.ansiColor — canonical single palette) ---
let baseFont  = Theme.Font.mono(12)
let baseColor = Theme.Color.textPrimary

func parseANSI(_ raw: String) -> NSAttributedString {
    let result = NSMutableAttributedString()
    var curColor = baseColor
    var curFont = baseFont
    let esc = Character("\u{1B}")
    var i = raw.startIndex
    var plain = ""
    while i < raw.endIndex {
        if raw[i] == esc {
            if !plain.isEmpty {
                result.append(NSAttributedString(string: plain,
                    attributes: [.foregroundColor: curColor, .font: curFont]))
                plain = ""
            }
            let next = raw.index(after: i)
            if next < raw.endIndex && raw[next] == "[" {
                var j = raw.index(after: next)
                var seq = ""
                while j < raw.endIndex && raw[j] != "m" {
                    seq.append(raw[j]); j = raw.index(after: j)
                }
                if j < raw.endIndex && raw[j] == "m" {
                    let codes = seq.split(separator: ";").compactMap { Int($0) }
                    for c in (codes.isEmpty ? [0] : codes) {
                        switch c {
                        case 0: curColor = baseColor; curFont = baseFont
                        case 1: curFont = Theme.Font.mono(baseFont.pointSize, weight: .bold)
                        case 2: curColor = Theme.Color.textFaint  // dim → timestamp gray
                        default: curColor = Theme.ansiColor(c)
                        }
                    }
                    i = raw.index(after: j); continue
                }
            }
            plain.append(raw[i]); i = raw.index(after: i)
        } else {
            plain.append(raw[i]); i = raw.index(after: i)
        }
    }
    if !plain.isEmpty {
        result.append(NSAttributedString(string: plain,
            attributes: [.foregroundColor: curColor, .font: curFont]))
    }
    return result
}

func loadFile() {
    guard let content = try? String(contentsOfFile: logPath, encoding: .utf8) else {
        let attr = NSAttributedString(string: "(log file not found: \(logPath))\n",
            attributes: [.foregroundColor: Theme.Color.textMuted, .font: baseFont])
        textView.textStorage?.setAttributedString(attr)
        return
    }
    let full = NSMutableAttributedString()
    for line in content.components(separatedBy: "\n") {
        guard !line.isEmpty else { continue }
        full.append(parseANSI(line))
        full.append(NSAttributedString(string: "\n", attributes: [.font: baseFont, .foregroundColor: baseColor]))
    }
    textView.textStorage?.setAttributedString(full)
    textView.scrollToEndOfDocument(nil)
}

loadFile()

// Live-reload on file append via kqueue
var fileSource: DispatchSourceFileSystemObject?
let fd = open(logPath, O_RDONLY)
if fd >= 0 {
    fileSource = DispatchSource.makeFileSystemObjectSource(
        fileDescriptor: fd, eventMask: .extend, queue: DispatchQueue.global(qos: .background))
    fileSource?.setEventHandler { DispatchQueue.main.async { loadFile() } }
    fileSource?.setCancelHandler { close(fd) }
    fileSource?.resume()
}

app.run()
