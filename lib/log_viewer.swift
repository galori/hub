import Cocoa

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

let win = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
    styleMask: [.titled, .closable, .resizable, .miniaturizable],
    backing: .buffered,
    defer: false)
win.title = "Hub Log"
win.backgroundColor = NSColor(white: 0.08, alpha: 1)
win.isMovableByWindowBackground = true
win.center()
win.makeKeyAndOrderFront(nil)
app.activate(ignoringOtherApps: true)

// Status bar at bottom
let statusBar = NSTextField(
    frame: NSRect(x: 0, y: 0, width: 800, height: statusBarHeight))
statusBar.isEditable = false
statusBar.isSelectable = false
statusBar.isBordered = false
statusBar.backgroundColor = NSColor(white: 0.05, alpha: 1)
statusBar.textColor = NSColor(white: 0.4, alpha: 1)
statusBar.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
statusBar.alignment = .center
statusBar.stringValue = logPath
statusBar.autoresizingMask = [.width, .maxYMargin]
win.contentView!.addSubview(statusBar)

let scrollView = NSScrollView(
    frame: NSRect(x: 0, y: statusBarHeight, width: 800, height: 600 - statusBarHeight))
scrollView.autoresizingMask = [.width, .height]
scrollView.hasVerticalScroller = true
scrollView.drawsBackground = false

let textView = NSTextView(frame: scrollView.contentView.bounds)
textView.isEditable = false
textView.isSelectable = true
textView.backgroundColor = NSColor(white: 0.08, alpha: 1)
textView.textColor = .white
textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
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

// Color coding for log levels
let baseFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
let colorTimestamp = NSColor(white: 0.45, alpha: 1)
let colorInput    = NSColor(red: 0.62, green: 0.82, blue: 0.45, alpha: 1) // green
let colorCmd      = NSColor(red: 0.46, green: 0.80, blue: 0.88, alpha: 1) // cyan
let colorOutput   = NSColor(white: 0.75, alpha: 1)
let colorError    = NSColor(red: 0.99, green: 0.36, blue: 0.49, alpha: 1) // red
let colorSep      = NSColor(white: 0.30, alpha: 1)
let colorDefault  = NSColor(white: 0.85, alpha: 1)

func colorForLine(_ line: String) -> NSColor {
    if line.hasPrefix("[") {
        // timestamp prefix — dim it
        if line.contains("] INPUT:") { return colorInput }
        if line.contains("] CMD:") { return colorCmd }
        if line.contains("] OUT:") { return colorOutput }
        if line.contains("] ERR:") { return colorError }
        if line.contains("] ---") { return colorSep }
        return colorDefault
    }
    return colorDefault
}

func appendLine(_ line: String) {
    let color = colorForLine(line)
    let attr = NSAttributedString(string: line + "\n", attributes: [
        .foregroundColor: color, .font: baseFont])
    textView.textStorage?.append(attr)
}

func loadFile() {
    textView.textStorage?.setAttributedString(NSAttributedString(string: ""))
    guard let content = try? String(contentsOfFile: logPath, encoding: .utf8) else {
        appendLine("(log file not found: \(logPath))")
        return
    }
    let lines = content.components(separatedBy: "\n")
    for line in lines {
        if line.isEmpty { continue }
        appendLine(line)
    }
    textView.scrollToEndOfDocument(nil)
}

loadFile()

// Watch for file changes using kqueue via a GCD source
var fileSource: DispatchSourceFileSystemObject?
let fd = open(logPath, O_RDONLY)
if fd >= 0 {
    fileSource = DispatchSource.makeFileSystemObjectSource(
        fileDescriptor: fd, eventMask: .extend, queue: DispatchQueue.global(qos: .background))
    fileSource?.setEventHandler {
        DispatchQueue.main.async { loadFile() }
    }
    fileSource?.setCancelHandler { close(fd) }
    fileSource?.resume()
}

app.run()
