import CoreServices
import Foundation

// CLI tool to get/set the system default web browser via Launch Services.
// Usage:
//   browser_ctl get          → prints current http handler bundle ID
//   browser_ctl set <id>     → sets http+https handler to the given bundle ID

let args = CommandLine.arguments

func getCurrentBrowser() -> String {
    return LSCopyDefaultHandlerForURLScheme("http" as CFString)?
        .takeRetainedValue() as String? ?? ""
}

func setDefaultBrowser(_ bundleID: String) {
    LSSetDefaultHandlerForURLScheme("http" as CFString, bundleID as CFString)
    LSSetDefaultHandlerForURLScheme("https" as CFString, bundleID as CFString)
}

if args.count < 2 || args[1] == "get" {
    print(getCurrentBrowser())
} else if args[1] == "set" {
    guard args.count >= 3 else {
        fputs("Usage: browser_ctl set <bundle-id>\n", stderr)
        exit(1)
    }
    setDefaultBrowser(args[2])
} else {
    fputs("Usage: browser_ctl [get | set <bundle-id>]\n", stderr)
    exit(1)
}
