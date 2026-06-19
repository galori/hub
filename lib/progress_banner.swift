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

let bannerW: CGFloat = Theme.Metric.bannerW
let margin: CGFloat = Theme.Metric.bannerMargin
let barClearance: CGFloat = Theme.Metric.barClearance

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

// ── SpinnerRing — style-guide accent ring ─────────────────────────────────────
//
// 15×15 ring: thin white track + a short accentBlue arc, spinning linearly.
// Used in the "running" state of StepRow instead of NSProgressIndicator.

class SpinnerRing: NSView {
    private let trackLayer = CAShapeLayer()
    private let arcLayer   = CAShapeLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        setupLayers()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func setupLayers() {
        let size: CGFloat = 15
        let lineW: CGFloat = 2
        let r = (size - lineW) / 2
        let center = CGPoint(x: size / 2, y: size / 2)
        let circlePath = NSBezierPath()
        circlePath.appendArc(withCenter: center, radius: r,
                             startAngle: 0, endAngle: 360, clockwise: false)

        // Full-circle dim track
        trackLayer.path         = circlePath.cgPath
        trackLayer.fillColor    = nil
        trackLayer.strokeColor  = NSColor(white: 1, alpha: 0.15).cgColor
        trackLayer.lineWidth    = lineW
        trackLayer.frame        = CGRect(x: 0, y: 0, width: size, height: size)
        layer?.addSublayer(trackLayer)

        // Short accent arc (~30% of circle)
        arcLayer.path          = circlePath.cgPath
        arcLayer.fillColor     = nil
        arcLayer.strokeColor   = Theme.Color.accentBlue.cgColor
        arcLayer.lineWidth     = lineW
        arcLayer.lineCap       = .round
        arcLayer.strokeStart   = 0
        arcLayer.strokeEnd     = 0.28
        arcLayer.frame         = CGRect(x: 0, y: 0, width: size, height: size)
        layer?.addSublayer(arcLayer)

        startSpinning()
    }

    func startSpinning() {
        let anim = CABasicAnimation(keyPath: "transform.rotation.z")
        anim.fromValue = 0
        anim.toValue   = 2 * Double.pi
        anim.duration  = 0.7
        anim.repeatCount = .infinity
        anim.timingFunction = CAMediaTimingFunction(name: .linear)
        arcLayer.add(anim, forKey: "spin")
    }

    func stopSpinning() {
        arcLayer.removeAnimation(forKey: "spin")
    }
}

// Helper: CGPath from NSBezierPath
extension NSBezierPath {
    var cgPath: CGPath {
        let path = CGMutablePath()
        var pts = [NSPoint](repeating: .zero, count: 3)
        for i in 0..<elementCount {
            let type = element(at: i, associatedPoints: &pts)
            switch type {
            case .moveTo:       path.move(to: pts[0])
            case .lineTo:       path.addLine(to: pts[0])
            case .curveTo:      path.addCurve(to: pts[2], control1: pts[0], control2: pts[1])
            case .cubicCurveTo: path.addCurve(to: pts[2], control1: pts[0], control2: pts[1])
            case .quadraticCurveTo: path.addQuadCurve(to: pts[1], control: pts[0])
            case .closePath:    path.closeSubpath()
            @unknown default:   break
            }
        }
        return path
    }
}

// ── StepRow class ─────────────────────────────────────────────────────────────
//
// Three visual states per the style guide "Progress & state" component:
//   pending  — 6px dim dot white@16% + textMuted label
//   active   — raised row bg white@4% + accent SpinnerRing + textPrimary bold label
//   done     — okSoft circle badge + green ✓ with pop-in animation
//   error    — destructive ✗ badge + destructive-colored label

class StepRow: NSView {
    // The 18×18 slot that holds the dot / spinner / badge
    private let indicatorSlot = NSView()

    // Indicator states (only one visible at a time)
    private let pendingDot  = NSView()       // 6px circle white@16%
    private let spinner     = SpinnerRing()  // accent spinning ring
    private let badgeCircle = NSView()       // okSoft filled circle
    private let checkLabel  = NSTextField(labelWithString: "✓")
    private let errorLabel  = NSTextField(labelWithString: "✗")

    let stepLabel = NSTextField(labelWithString: "")

    // Raised row background (active state only)
    private var rowBgLayer: CALayer?

    init(text: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true

        // ── Raised-row bg layer (hidden initially) ──
        let bg = CALayer()
        bg.backgroundColor = NSColor(white: 1, alpha: 0.04).cgColor
        bg.cornerRadius    = 9
        bg.frame           = .zero   // sized in layout
        bg.opacity         = 0
        layer?.addSublayer(bg)
        rowBgLayer = bg

        // ── Indicator slot (18×18) ──
        indicatorSlot.translatesAutoresizingMaskIntoConstraints = false
        indicatorSlot.wantsLayer = true
        addSubview(indicatorSlot)

        // Pending dot (6×6, centered in slot)
        pendingDot.translatesAutoresizingMaskIntoConstraints = false
        pendingDot.wantsLayer = true
        pendingDot.layer?.cornerRadius = 3
        pendingDot.layer?.backgroundColor = NSColor(white: 1, alpha: 0.16).cgColor
        indicatorSlot.addSubview(pendingDot)

        // Spinner (15×15, centered in slot)
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.isHidden = true
        indicatorSlot.addSubview(spinner)

        // Badge circle (18×18, okSoft fill)
        badgeCircle.translatesAutoresizingMaskIntoConstraints = false
        badgeCircle.wantsLayer = true
        badgeCircle.layer?.cornerRadius = 9
        badgeCircle.layer?.backgroundColor = Theme.Color.okSoft.cgColor
        badgeCircle.isHidden = true
        indicatorSlot.addSubview(badgeCircle)

        // Check label (centered in badge)
        checkLabel.translatesAutoresizingMaskIntoConstraints = false
        checkLabel.font = Theme.Font.mono(10, weight: .bold)
        checkLabel.textColor = Theme.Color.ok
        checkLabel.isEditable = false; checkLabel.isBordered = false
        checkLabel.backgroundColor = .clear
        checkLabel.isHidden = true
        indicatorSlot.addSubview(checkLabel)

        // Error label (centered in slot)
        errorLabel.translatesAutoresizingMaskIntoConstraints = false
        errorLabel.font = Theme.Font.mono(11, weight: .semibold)
        errorLabel.textColor = Theme.Color.destructive
        errorLabel.isEditable = false; errorLabel.isBordered = false
        errorLabel.backgroundColor = .clear
        errorLabel.isHidden = true
        indicatorSlot.addSubview(errorLabel)

        // ── Step label ──
        stepLabel.translatesAutoresizingMaskIntoConstraints = false
        stepLabel.font = Theme.Font.mono(12, weight: .regular)
        stepLabel.textColor = Theme.Color.textMuted
        stepLabel.lineBreakMode = .byTruncatingTail
        stepLabel.maximumNumberOfLines = 1
        stepLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        stepLabel.stringValue = text
        addSubview(stepLabel)

        // ── Constraints ──
        NSLayoutConstraint.activate([
            // slot: fixed 18×18, leading edge, vertically centered
            indicatorSlot.widthAnchor.constraint(equalToConstant: 18),
            indicatorSlot.heightAnchor.constraint(equalToConstant: 18),
            indicatorSlot.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            indicatorSlot.centerYAnchor.constraint(equalTo: centerYAnchor),

            // pending dot: 6×6 centered in slot
            pendingDot.widthAnchor.constraint(equalToConstant: 6),
            pendingDot.heightAnchor.constraint(equalToConstant: 6),
            pendingDot.centerXAnchor.constraint(equalTo: indicatorSlot.centerXAnchor),
            pendingDot.centerYAnchor.constraint(equalTo: indicatorSlot.centerYAnchor),

            // spinner: 15×15 centered in slot
            spinner.widthAnchor.constraint(equalToConstant: 15),
            spinner.heightAnchor.constraint(equalToConstant: 15),
            spinner.centerXAnchor.constraint(equalTo: indicatorSlot.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: indicatorSlot.centerYAnchor),

            // badge: fills slot
            badgeCircle.widthAnchor.constraint(equalToConstant: 18),
            badgeCircle.heightAnchor.constraint(equalToConstant: 18),
            badgeCircle.centerXAnchor.constraint(equalTo: indicatorSlot.centerXAnchor),
            badgeCircle.centerYAnchor.constraint(equalTo: indicatorSlot.centerYAnchor),

            // check: centered in slot
            checkLabel.centerXAnchor.constraint(equalTo: indicatorSlot.centerXAnchor),
            checkLabel.centerYAnchor.constraint(equalTo: indicatorSlot.centerYAnchor),

            // error: centered in slot
            errorLabel.centerXAnchor.constraint(equalTo: indicatorSlot.centerXAnchor),
            errorLabel.centerYAnchor.constraint(equalTo: indicatorSlot.centerYAnchor),

            // label: 8px right of slot, vertically centered, fills remaining width
            stepLabel.leadingAnchor.constraint(equalTo: indicatorSlot.trailingAnchor, constant: 8),
            stepLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            stepLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            // self height
            heightAnchor.constraint(equalToConstant: 28),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    // Called when this step becomes the active (running) step.
    func markActive() {
        // Show spinner, hide dot
        pendingDot.isHidden = true
        spinner.isHidden = false

        // Bold label, textPrimary
        stepLabel.font = Theme.Font.mono(12, weight: .semibold)
        stepLabel.textColor = Theme.Color.textPrimary

        // Raise row background
        rowBgLayer?.opacity = 1
    }

    // Called when the next STEP arrives or QUIT is received — marks this step done.
    func markDone() {
        // Hide spinner, show badge + check
        spinner.isHidden = true
        spinner.stopSpinning()
        badgeCircle.isHidden = false
        checkLabel.isHidden = false

        // Restore label weight/color (done = muted, non-bold)
        stepLabel.font = Theme.Font.mono(12, weight: .regular)
        stepLabel.textColor = Theme.Color.textSecondary

        // Dismiss raised bg
        rowBgLayer?.opacity = 0

        // Pop-in animation: scale 0.6→1 + fade in, 0.2s
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 0.6
        scale.toValue   = 1.0
        scale.duration  = 0.2
        scale.timingFunction = CAMediaTimingFunction(name: .easeOut)

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue   = 1
        fade.duration  = 0.2

        let group = CAAnimationGroup()
        group.animations = [scale, fade]
        group.duration   = 0.2
        badgeCircle.layer?.add(group, forKey: "popin")
        checkLabel.layer?.add(group, forKey: "popin")
    }

    func markError() {
        spinner.isHidden = true
        spinner.stopSpinning()
        errorLabel.isHidden = false
        pendingDot.isHidden = true
        rowBgLayer?.opacity = 0
        stepLabel.textColor = Theme.Color.destructive
    }

    // Size the raised-bg layer to match our bounds (called after layout).
    override func layout() {
        super.layout()
        rowBgLayer?.frame = bounds
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
    row.markActive()
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
