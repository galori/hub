import Cocoa

// Dock icon launcher for hub. Runs `hub toggle` (up if down, down if up) and
// quits immediately — no window, just a Dock click target.

let app = NSApplication.shared
app.setActivationPolicy(.regular)

func hubScriptPath() -> String? {
    let path = NSHomeDirectory() + "/.config/hub/hub_path"
    guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
    return content.trimmingCharacters(in: .whitespacesAndNewlines)
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ note: Notification) {
        guard let hub = hubScriptPath() else {
            NSApp.terminate(nil)
            return
        }
        let escapedHub = hub.replacingOccurrences(of: "'", with: "'\\''")
        let p = Process()
        p.launchPath = "/bin/sh"
        p.arguments = ["-c", "'\(escapedHub)' toggle"]
        p.terminationHandler = { _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
        do {
            try p.run()
        } catch {
            NSApp.terminate(nil)
        }
    }
}

let delegate = AppDelegate()
app.delegate = delegate
app.run()
