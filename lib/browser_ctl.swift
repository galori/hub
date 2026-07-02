//
// browser_ctl.swift
// Hub
//

import Cocoa

func getDefaultBrowser() -> String? {
    if let url = LSCopyDefaultApplicationURLForURL(URL(string: "http:")! as CFURL, .all, nil) {
        let bundle = Bundle(url: url.takeRetainedValue() as URL)
        return bundle?.bundleIdentifier
    }
    return nil
}

func setDefaultBrowser(bundleIdentifier: String) -> Bool {
    let result = LSSetDefaultHandlerForURLScheme("http" as CFString, bundleIdentifier as CFString)
    LSSetDefaultHandlerForURLScheme("https" as CFString, bundleIdentifier as CFString)
    return result == noErr
}

func saveDefaultBrowser(to path: String) -> Bool {
    if let browser = getDefaultBrowser() {
        do {
            try browser.write(toFile: path, atomically: true, encoding: .utf8)
            return true
        } catch {
            return false
        }
    }
    return false
}

func restoreDefaultBrowser(from path: String) -> Bool {
    if let browser = try? String(contentsOfFile: path, encoding: .utf8) {
        return setDefaultBrowser(bundleIdentifier: browser.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    return false
}

// MARK: - Main

let args = CommandLine.arguments
if args.count < 2 {
    fputs("Usage: browser_ctl <command> [args]\n", stderr)
    exit(1)
}

let command = args[1]

switch command {
case "save":
    let savePath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/hub/prev_browser.txt").path
    let success = saveDefaultBrowser(to: savePath)
    exit(success ? 0 : 1)

case "restore":
    let restorePath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/hub/prev_browser.txt").path
    let success = restoreDefaultBrowser(from: restorePath)
    exit(success ? 0 : 1)

case "save_original":
    let originalPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/hub/original_default_browser.txt").path
    let success = saveDefaultBrowser(to: originalPath)
    exit(success ? 0 : 1)

case "restore_original":
    let originalPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/hub/original_default_browser.txt").path
    let success = restoreDefaultBrowser(from: originalPath)
    exit(success ? 0 : 1)

case "get":
    if let browser = getDefaultBrowser() {
        print(browser)
    }
    exit(0)

case "set":
    guard args.count >= 3 else {
        fputs("Usage: browser_ctl set <bundle-id>\n", stderr)
        exit(1)
    }
    let success = setDefaultBrowser(bundleIdentifier: args[2])
    exit(success ? 0 : 1)

default:
    fputs("Usage: browser_ctl [get | set <bundle-id> | save | restore | save_original | restore_original]\n", stderr)
    exit(1)
}
