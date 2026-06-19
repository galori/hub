import Cocoa

let app = NSApplication.shared
app.setActivationPolicy(.regular)

// Minimal menu so Cmd+C (copy) and Cmd+W (close) are handled
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
let titleArg = args.count > 1 ? args[1] : "Output"

let statusBarHeight: CGFloat = 26

let win = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 700, height: 400),
    styleMask: [.titled, .closable, .resizable, .miniaturizable],
    backing: .buffered,
    defer: false)
win.title = titleArg
win.backgroundColor = Theme.Color.canvas
win.isMovableByWindowBackground = true
win.center()
win.makeKeyAndOrderFront(nil)
app.activate(ignoringOtherApps: true)

// Status bar pinned to bottom — shows countdown after process exits
let statusBar = NSTextField(
    frame: NSRect(x: 0, y: 0, width: 700, height: statusBarHeight))
statusBar.isEditable = false
statusBar.isSelectable = false
statusBar.isBordered = false
statusBar.backgroundColor = Theme.Color.panelBot
statusBar.textColor = Theme.Color.textMuted
statusBar.font = Theme.Font.mono(11)
statusBar.alignment = .center
statusBar.autoresizingMask = [.width, .maxYMargin]
win.contentView!.addSubview(statusBar)

let scrollView = NSScrollView(
    frame: NSRect(x: 0, y: statusBarHeight, width: 700, height: 400 - statusBarHeight))
scrollView.autoresizingMask = [.width, .height]
scrollView.hasVerticalScroller = true
scrollView.drawsBackground = false

let textView = NSTextView(frame: scrollView.contentView.bounds)
textView.isEditable = false
textView.isSelectable = true
textView.backgroundColor = Theme.Color.canvas
textView.textColor = Theme.Color.textPrimary
textView.font = Theme.Font.mono(13)
textView.autoresizingMask = [.width]
textView.isVerticallyResizable = true
textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
textView.textContainer?.widthTracksTextView = true
textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
textView.textContainerInset = NSSize(width: 10, height: 10)

scrollView.documentView = textView
win.contentView!.addSubview(scrollView)

NotificationCenter.default.addObserver(
    forName: NSWindow.willCloseNotification, object: win, queue: .main) { _ in
    NSApp.terminate(nil)
}

let baseFont  = Theme.Font.mono(13)
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
                result.append(NSAttributedString(string: plain, attributes: [
                    .foregroundColor: curColor, .font: curFont]))
                plain = ""
            }
            let next = raw.index(after: i)
            if next < raw.endIndex && raw[next] == "[" {
                var j = raw.index(after: next)
                var seq = ""
                while j < raw.endIndex && raw[j] != "m" {
                    seq.append(raw[j])
                    j = raw.index(after: j)
                }
                if j < raw.endIndex && raw[j] == "m" {
                    let codes = seq.split(separator: ";").compactMap { Int($0) }
                    for c in (codes.isEmpty ? [0] : codes) {
                        switch c {
                        case 0: curColor = baseColor; curFont = baseFont
                        case 1: curFont = Theme.Font.mono(baseFont.pointSize, weight: .bold)
                        default: curColor = Theme.ansiColor(c)
                        }
                    }
                    i = raw.index(after: j)
                    continue
                }
            }
            plain.append(raw[i])
            i = raw.index(after: i)
        } else {
            plain.append(raw[i])
            i = raw.index(after: i)
        }
    }
    if !plain.isEmpty {
        result.append(NSAttributedString(string: plain, attributes: [
            .foregroundColor: curColor, .font: curFont]))
    }
    return result
}

func appendText(_ text: String, color: NSColor? = nil) {
    if let c = color {
        let attr = NSAttributedString(string: text + "\n", attributes: [
            .foregroundColor: c, .font: baseFont])
        textView.textStorage?.append(attr)
    } else {
        let parsed = parseANSI(text + "\n")
        textView.textStorage?.append(parsed)
    }
    textView.scrollToEndOfDocument(nil)
}

var countdownRemaining = 10
var countdownTimer: Timer?

func startCountdown() {
    statusBar.stringValue = "Closing in \(countdownRemaining)…"
    countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
        countdownRemaining -= 1
        if countdownRemaining <= 0 {
            countdownTimer?.invalidate()
            NSApp.terminate(nil)
        } else {
            statusBar.stringValue = "Closing in \(countdownRemaining)…"
        }
    }
}

DispatchQueue.global(qos: .userInitiated).async {
    while let line = readLine() {
        // "EXIT:<code>" signals completion — act immediately, don't wait for pipe closure
        if line.hasPrefix("EXIT:"), let code = Int32(line.dropFirst(5)) {
            DispatchQueue.main.async {
                appendText("\n--- Done (exit \(code)) — Closing in 10s ---", color: Theme.Color.textMuted)
                startCountdown()
            }
            return
        }
        DispatchQueue.main.async { appendText(line) }
    }
    // Pipe closed without EXIT line
    DispatchQueue.main.async {
        appendText("\n--- Done — Closing in 10s ---", color: Theme.Color.textMuted)
        startCountdown()
    }
}

app.run()
