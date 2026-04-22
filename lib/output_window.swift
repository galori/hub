import Cocoa

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let titleArg = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Output"

let win = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 700, height: 400),
    styleMask: [.titled, .closable, .resizable, .miniaturizable],
    backing: .buffered,
    defer: false)
win.title = titleArg
win.backgroundColor = NSColor(white: 0.08, alpha: 1)
win.isMovableByWindowBackground = true
win.center()
win.makeKeyAndOrderFront(nil)
app.activate(ignoringOtherApps: true)

let scrollView = NSScrollView(frame: win.contentView!.bounds)
scrollView.autoresizingMask = [.width, .height]
scrollView.hasVerticalScroller = true
scrollView.drawsBackground = false

let textView = NSTextView(frame: scrollView.contentView.bounds)
textView.isEditable = false
textView.isSelectable = true
textView.backgroundColor = NSColor(white: 0.08, alpha: 1)
textView.textColor = .white
textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
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

func appendLine(_ text: String, color: NSColor = .white) {
    let attr = NSAttributedString(string: text + "\n", attributes: [
        .foregroundColor: color,
        .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    ])
    textView.textStorage?.append(attr)
    textView.scrollToEndOfDocument(nil)
}

DispatchQueue.global(qos: .userInitiated).async {
    while let line = readLine() {
        DispatchQueue.main.async { appendLine(line) }
    }
    DispatchQueue.main.async {
        appendLine("\n--- Done ---", color: NSColor(white: 1, alpha: 0.4))
    }
}

app.run()
