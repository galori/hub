import Cocoa

// Hierarchical progress HUD — shown to hub users during multi-step operations.
// Top-right corner by default; centered modal (with backdrop) when --modal is passed.
// Always above other windows, no focus steal, ✕ dismiss button.
//
// Usage: progress_banner [options] ["parent title"]
//   --accent blue|orange      Border color (default: blue)
//   --modal                   Add full-screen backdrop, center window (for install)
//   --prefix "<str>"          Prepend string to title idempotently (for testing banner)
//
// Stdin protocol (line-based):
//   TITLE\t<text>   — Replace parent title
//   STEP\t<text>    — Complete current active step (✔), append new active step
//   QUIT / EOF      — Dismiss
//   ERROR:<text>    — Show error state, auto-dismiss after 2.5 s

// ── Argument parsing ─────────────────────────────────────────────────────────

var accentColor = Theme.Color.accentBlue.withAlphaComponent(0.80)
var isModal = false
var titlePrefix = ""
var initialTitle = "Setting up workspace…"

var args = CommandLine.arguments.dropFirst()
while !args.isEmpty {
    let a = args.first!
    args = args.dropFirst()
    switch a {
    case "--accent":
        let val = args.first ?? "blue"
        args = args.dropFirst()
        switch val {
        case "orange": accentColor = Theme.Color.activity.withAlphaComponent(0.75)
        case "blue":   accentColor = Theme.Color.accentBlue.withAlphaComponent(0.80)
        default:       break
        }
    case "--modal":
        isModal = true
    case "--prefix":
        titlePrefix = args.first ?? ""
        args = args.dropFirst()
    default:
        if !a.hasPrefix("-") { initialTitle = a }
    }
}

// Apply prefix to the title idempotently.
func withPrefix(_ s: String) -> String {
    titlePrefix.isEmpty || s.hasPrefix(titlePrefix) ? s : titlePrefix + s
}
initialTitle = withPrefix(initialTitle)

// ── App / Window setup ───────────────────────────────────────────────────────

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let screen = NSScreen.main ?? NSScreen.screens[0]
let sf = screen.frame

let bannerW: CGFloat = 360
let margin: CGFloat = 16
let barClearance: CGFloat = 100

let win = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: bannerW, height: 60),
    styleMask: .borderless, backing: .buffered, defer: false)
win.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)
win.backgroundColor = .clear
win.isOpaque = false
win.hasShadow = true
win.ignoresMouseEvents = false
win.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

let cv = win.contentView!
cv.wantsLayer = true
cv.layer?.cornerRadius = Theme.Radius.control
cv.layer?.masksToBounds = true
cv.layer?.backgroundColor = Theme.Color.modalTop.cgColor
cv.layer?.borderWidth = 1
cv.layer?.borderColor = accentColor.cgColor

// Modal backdrop (only when --modal)
var backdrop: NSWindow? = nil
if isModal {
    let bd = NSWindow(contentRect: sf, styleMask: .borderless, backing: .buffered, defer: false)
    bd.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
    bd.backgroundColor = NSColor(white: 0, alpha: 0.85)
    bd.isOpaque = false
    bd.hasShadow = false
    bd.collectionBehavior = [.canJoinAllSpaces, .stationary]
    bd.alphaValue = 0
    bd.orderFrontRegardless()
    backdrop = bd
}

// ── Dismiss button ────────────────────────────────────────────────────────────

func dismiss() {
    NSAnimationContext.runAnimationGroup({ ctx in
        ctx.duration = 0.15
        win.animator().alphaValue = 0
        backdrop?.animator().alphaValue = 0
    }, completionHandler: {
        NSApp.terminate(nil)
    })
}

let dismissView = Theme.makeDismissButton(onPress: { dismiss() })
cv.addSubview(dismissView)

NSLayoutConstraint.activate([
    dismissView.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -12),
    dismissView.topAnchor.constraint(equalTo: cv.topAnchor, constant: 12),
    dismissView.widthAnchor.constraint(equalToConstant: 20),
    dismissView.heightAnchor.constraint(equalToConstant: 20),
])

// ── Parent row ───────────────────────────────────────────────────────────────

// Outer stack — fills the content view, padded.
let outerStack = NSStackView()
outerStack.translatesAutoresizingMaskIntoConstraints = false
outerStack.orientation = .vertical
outerStack.alignment = .leading
outerStack.spacing = 4
outerStack.edgeInsets = NSEdgeInsets(top: 12, left: 14, bottom: 12, right: 38)
cv.addSubview(outerStack)
NSLayoutConstraint.activate([
    outerStack.leadingAnchor.constraint(equalTo: cv.leadingAnchor),
    outerStack.trailingAnchor.constraint(equalTo: cv.trailingAnchor),
    outerStack.topAnchor.constraint(equalTo: cv.topAnchor),
    outerStack.bottomAnchor.constraint(equalTo: cv.bottomAnchor),
])

// Parent row: spinner + bold label
let parentRow = NSStackView()
parentRow.translatesAutoresizingMaskIntoConstraints = false
parentRow.orientation = .horizontal
parentRow.alignment = .centerY
parentRow.spacing = 10

let parentSpinner = NSProgressIndicator()
parentSpinner.translatesAutoresizingMaskIntoConstraints = false
parentSpinner.style = .spinning
parentSpinner.controlSize = .small
parentSpinner.appearance = NSAppearance(named: .darkAqua)
parentSpinner.startAnimation(nil)
NSLayoutConstraint.activate([
    parentSpinner.widthAnchor.constraint(equalToConstant: 16),
    parentSpinner.heightAnchor.constraint(equalToConstant: 16),
])
parentRow.addArrangedSubview(parentSpinner)

let parentLabel = NSTextField(labelWithString: initialTitle)
parentLabel.translatesAutoresizingMaskIntoConstraints = false
parentLabel.font = Theme.Font.ui(13, weight: .semibold)
parentLabel.textColor = Theme.Color.textPrimary
parentLabel.lineBreakMode = .byTruncatingTail
parentLabel.maximumNumberOfLines = 1
parentLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
parentRow.addArrangedSubview(parentLabel)

outerStack.addArrangedSubview(parentRow)
NSLayoutConstraint.activate([
    parentRow.widthAnchor.constraint(equalTo: outerStack.widthAnchor,
                                     constant: -(outerStack.edgeInsets.left + outerStack.edgeInsets.right))
])

// ── StepRow class ─────────────────────────────────────────────────────────────

class StepRow: NSStackView {
    private let stepSpinner = NSProgressIndicator()
    private let stepCheck  = NSTextField(labelWithString: "✔")
    private let stepError  = NSTextField(labelWithString: "✗")
    let stepLabel = NSTextField(labelWithString: "")

    init(text: String) {
        super.init(frame: .zero)
        orientation  = .horizontal
        alignment    = .centerY
        spacing      = 8
        translatesAutoresizingMaskIntoConstraints = false

        // Leading indent to distinguish from parent
        let indent = NSView()
        indent.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            indent.widthAnchor.constraint(equalToConstant: 6),
            indent.heightAnchor.constraint(equalToConstant: 1),
        ])
        addArrangedSubview(indent)

        // Spinner
        stepSpinner.translatesAutoresizingMaskIntoConstraints = false
        stepSpinner.style = .spinning
        stepSpinner.controlSize = .small
        stepSpinner.appearance = NSAppearance(named: .darkAqua)
        stepSpinner.startAnimation(nil)
        NSLayoutConstraint.activate([
            stepSpinner.widthAnchor.constraint(equalToConstant: 13),
            stepSpinner.heightAnchor.constraint(equalToConstant: 13),
        ])
        addArrangedSubview(stepSpinner)

        // Check mark
        stepCheck.translatesAutoresizingMaskIntoConstraints = false
        stepCheck.font = Theme.Font.mono(12, weight: .medium)
        stepCheck.textColor = Theme.Color.ok
        stepCheck.isEditable = false; stepCheck.isBordered = false
        stepCheck.backgroundColor = .clear
        stepCheck.isHidden = true
        NSLayoutConstraint.activate([
            stepCheck.widthAnchor.constraint(equalToConstant: 13),
        ])
        addArrangedSubview(stepCheck)

        // Error mark
        stepError.translatesAutoresizingMaskIntoConstraints = false
        stepError.font = Theme.Font.mono(12, weight: .semibold)
        stepError.textColor = Theme.Color.destructive
        stepError.isEditable = false; stepError.isBordered = false
        stepError.backgroundColor = .clear
        stepError.isHidden = true
        NSLayoutConstraint.activate([
            stepError.widthAnchor.constraint(equalToConstant: 13),
        ])
        addArrangedSubview(stepError)

        // Label
        stepLabel.translatesAutoresizingMaskIntoConstraints = false
        stepLabel.font = Theme.Font.mono(12, weight: .regular)
        stepLabel.textColor = Theme.Color.textSecondary
        stepLabel.lineBreakMode = .byTruncatingTail
        stepLabel.maximumNumberOfLines = 1
        stepLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        stepLabel.stringValue = text
        addArrangedSubview(stepLabel)
    }

    required init?(coder: NSCoder) { fatalError() }

    func markDone() {
        stepSpinner.stopAnimation(nil)
        stepSpinner.isHidden = true
        stepCheck.isHidden = false
    }

    func markError() {
        stepSpinner.stopAnimation(nil)
        stepSpinner.isHidden = true
        stepError.isHidden = false
    }
}

// ── Steps state ───────────────────────────────────────────────────────────────

var activeStep: StepRow? = nil

func addStep(_ text: String) {
    // Complete whatever was active before.
    activeStep?.markDone()

    let row = StepRow(text: text)
    outerStack.addArrangedSubview(row)
    // Row must fill available width (accounting for the outer padding).
    NSLayoutConstraint.activate([
        row.widthAnchor.constraint(equalTo: outerStack.widthAnchor,
                                   constant: -(outerStack.edgeInsets.left + outerStack.edgeInsets.right))
    ])
    activeStep = row
    resizeWindow(animated: true)
}

func completeFinalStep() {
    activeStep?.markDone()
    activeStep = nil
}

// ── Dynamic window sizing ─────────────────────────────────────────────────────

// Re-layout and resize, keeping the window anchored to the top-right (or center if modal).
func resizeWindow(animated: Bool) {
    outerStack.layoutSubtreeIfNeeded()
    let fitting = outerStack.fittingSize
    let newH = max(44, fitting.height)

    var newOrigin: NSPoint
    if isModal {
        newOrigin = NSPoint(x: sf.midX - bannerW / 2, y: sf.midY - newH / 2 + 80)
    } else {
        // Anchor top edge: keep maxY the same as before, grow downward.
        newOrigin = NSPoint(x: sf.maxX - bannerW - margin,
                            y: win.frame.maxY - newH)
    }
    let newFrame = NSRect(origin: newOrigin, size: CGSize(width: bannerW, height: newH))

    if animated {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            win.animator().setFrame(newFrame, display: true)
        }
    } else {
        win.setFrame(newFrame, display: true)
    }
}

// Set initial position (no animation yet).
let initH: CGFloat = 44
let initOrigin: NSPoint = isModal
    ? NSPoint(x: sf.midX - bannerW / 2, y: sf.midY - initH / 2 + 80)
    : NSPoint(x: sf.maxX - bannerW - margin, y: sf.maxY - initH - barClearance)
win.setFrame(NSRect(origin: initOrigin, size: CGSize(width: bannerW, height: initH)), display: false)

// ── Show ──────────────────────────────────────────────────────────────────────

win.alphaValue = 0
win.orderFrontRegardless()
DispatchQueue.main.async {
    // Size to actual content before fading in.
    resizeWindow(animated: false)
    NSAnimationContext.runAnimationGroup { ctx in
        ctx.duration = 0.15
        win.animator().alphaValue = 1
        backdrop?.animator().alphaValue = 1
    }
}

// ── Error state ───────────────────────────────────────────────────────────────

func showError(_ msg: String) {
    cv.layer?.borderColor = Theme.Color.destructive.withAlphaComponent(0.90).cgColor
    parentSpinner.stopAnimation(nil)
    parentSpinner.isHidden = true

    let errIcon = NSTextField(labelWithString: "✗")
    errIcon.translatesAutoresizingMaskIntoConstraints = false
    errIcon.font = Theme.Font.ui(15, weight: .semibold)
    errIcon.textColor = Theme.Color.destructive
    errIcon.isEditable = false; errIcon.isBordered = false
    errIcon.backgroundColor = .clear
    NSLayoutConstraint.activate([
        errIcon.widthAnchor.constraint(equalToConstant: 16),
        errIcon.heightAnchor.constraint(equalToConstant: 16),
    ])
    // Replace spinner in the parent row (insert at index 0, before parentLabel).
    parentRow.insertArrangedSubview(errIcon, at: 0)
    parentRow.removeArrangedSubview(parentSpinner)
    parentSpinner.removeFromSuperview()

    // Mark any active sub-step as errored too.
    activeStep?.markError()
    activeStep = nil

    parentLabel.stringValue = msg
    resizeWindow(animated: true)
    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { dismiss() }
}

// ── Stdin protocol ────────────────────────────────────────────────────────────

DispatchQueue.global(qos: .userInitiated).async {
    while let line = readLine() {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "QUIT" {
            DispatchQueue.main.async {
                completeFinalStep()
                dismiss()
            }
            return
        }
        if trimmed.hasPrefix("ERROR:") {
            let msg = String(trimmed.dropFirst("ERROR:".count))
            DispatchQueue.main.async { showError(msg) }
            return
        }
        if trimmed.hasPrefix("STEP\t") {
            let text = String(trimmed.dropFirst("STEP\t".count))
            DispatchQueue.main.async { addStep(text) }
        } else if trimmed.hasPrefix("TITLE\t") {
            let text = String(trimmed.dropFirst("TITLE\t".count))
            DispatchQueue.main.async { parentLabel.stringValue = withPrefix(text) }
        } else if !trimmed.isEmpty {
            // Legacy plain-text update → replace parent title (backward compat).
            DispatchQueue.main.async { parentLabel.stringValue = withPrefix(trimmed) }
        }
    }
    // EOF — dismiss cleanly.
    DispatchQueue.main.async {
        completeFinalStep()
        dismiss()
    }
}

app.run()
