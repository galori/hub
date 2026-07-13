import Cocoa

// ─────────────────────────────────────────────────────────────────────────────
// MARK: – NSColor helpers  (the ONLY copy in the codebase — do not re-declare)
// ─────────────────────────────────────────────────────────────────────────────

extension NSColor {
    /// Construct from 0xAARRGGBB
    convenience init(argb: UInt32) {
        let a = CGFloat((argb >> 24) & 0xff) / 255
        let r = CGFloat((argb >> 16) & 0xff) / 255
        let g = CGFloat((argb >>  8) & 0xff) / 255
        let b = CGFloat( argb        & 0xff) / 255
        self.init(srgbRed: r, green: g, blue: b, alpha: a)
    }
    /// Construct from 0xRRGGBB + explicit alpha
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xff) / 255,
                  green:   CGFloat((hex >>  8) & 0xff) / 255,
                  blue:    CGFloat( hex         & 0xff) / 255,
                  alpha:   alpha)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: – Theme
// ─────────────────────────────────────────────────────────────────────────────

enum Theme {

    // ── Colors ────────────────────────────────────────────────────────────────
    enum Color {
        // Surfaces
        static let canvas      = NSColor(argb: 0xFF0D0E12)
        static let panelTop    = NSColor(argb: 0xFF1A1C22)
        static let panelBot    = NSColor(argb: 0xFF15171C)
        static let modalTop    = NSColor(argb: 0xFF1C1E25)
        static let modalBot    = NSColor(argb: 0xFF16181D)
        static let inputField  = NSColor(argb: 0xFF2C2F3B)
        static let clusterBg   = NSColor(argb: 0xFF181A20)  // Hub Bar cluster occluder

        // Borders / highlights
        static let border          = NSColor(white: 1, alpha: 0.06)
        static let borderStrong    = NSColor(white: 1, alpha: 0.08)
        static let insetHighlight  = NSColor(white: 1, alpha: 0.05)  // top-edge 1px highlight

        // Text
        static let textTitle     = NSColor(argb: 0xFFF0F1F4)
        static let textPrimary   = NSColor(argb: 0xFFE8EAF0)
        static let textSecondary = NSColor(argb: 0xFFAEB3BF)
        static let textBody      = NSColor(argb: 0xFF9AA0AC)
        static let textLabel     = NSColor(argb: 0xFFD4D7DE)
        static let textMuted     = NSColor(argb: 0xFF7D818C)
        static let textFaint     = NSColor(argb: 0xFF5A5D68)

        // Accents
        static let accentTeal   = NSColor(argb: 0xFF41D1C4)  // Hub Bar // bar & teal highlights teal highlights
        static let accentBlue   = NSColor(argb: 0xFF3B82F6)  // launcher + modals
        static let ok           = NSColor(argb: 0xFF37D07A)  // active / ok / green
        static let activity     = NSColor(argb: 0xFFF0883E)  // activity dot / orange
        static let destructive  = NSColor(argb: 0xFFE06C6C)  // destructive action
        static let safari       = NSColor(argb: 0xFF2F7FE8)  // Safari brand blue

        // Soft / glow variants
        static let accentTealSoft = NSColor(argb: 0x2241D1C4)  // teal @13%
        static let accentBlueSoft = NSColor(argb: 0x293B82F6)  // blue @16%
        static let okSoft         = NSColor(argb: 0x2437D07A)  // ok @14%
        static let activitySoft   = NSColor(argb: 0x24F0883E)  // activity @14%

        // Pill states (Hub Bar window pills)
        static let pillIdleBg    = NSColor(argb: 0x09FFFFFF)   // white 3.5%
        static let pillHoverBg   = NSColor(argb: 0x17FFFFFF)   // white 9%
        static let pillIdxIdle   = NSColor(argb: 0xFF5A5D68)
        static let pillNameIdle  = NSColor(argb: 0xFFAEB3BF)
        static let pillIdxActive = NSColor(argb: 0x73000000)   // rgba(0,0,0,0.45)
        static let pillNameActive = NSColor(argb: 0xFF06201E)

        // App group cluster (Hub Bar)
        static let appGroupBg     = NSColor(argb: 0x0BFFFFFF)  // white 4.5%
        static let appGroupBorder = NSColor(argb: 0x0DFFFFFF)  // white 5%

        // Status dots (claude alert indicators on Hub Bar)
        static let dotOrange = NSColor(argb: 0xFFF0883E)
        static let dotBlue   = NSColor(argb: 0xFF76CCE0)

        // Workspace slot colors (per-workspace identity palette, 35 entries)
        static let slotColors: [UInt32] = [
            0xff1A73E8, 0xffFF7043, 0xff8E76D1, 0xff00C853, 0xffEC407A,
            0xff00D1FF, 0xffF9A825, 0xff5C6BC0, 0xffEF5350, 0xff26C6DA,
            0xffAEEA00, 0xff7E57C2, 0xfff39660, 0xff00A396, 0xffFFCA28,
            0xffAB47BC, 0xff66BB6A, 0xffE05297, 0xff42A5F5, 0xff8D6E63,
            0xff9CCC65, 0xffC62828, 0xff78909C, 0xffD4E157, 0xff4527A0,
            0xffFFA726, 0xff00897B, 0xff6A1B9A, 0xff29B6F6, 0xff2E7D32,
            0xff5C8AE6, 0xff1565C0, 0xff7889B3, 0xffFF6EC7, 0xff00838F,
        ]
    }

    // ── Fonts ─────────────────────────────────────────────────────────────────
    //
    // Mono:  JetBrainsMono Nerd Font → Hack Nerd Font → monospacedSystemFont
    //        (Nerd Font mono keeps the status bar's glyph icons working)
    // UI:    Inter → systemFont
    //
    enum Font {
        static func mono(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
            let jbName: String
            switch weight {
            case .bold, .heavy, .black:  jbName = "JetBrainsMonoNFM-Bold"
            case .semibold, .medium:     jbName = "JetBrainsMonoNFM-SemiBold"
            default:                     jbName = "JetBrainsMonoNFM-Regular"
            }
            if let f = NSFont(name: jbName, size: size) { return f }
            if let f = NSFont(name: "Hack Nerd Font", size: size) { return f }
            return NSFont.monospacedSystemFont(ofSize: size, weight: weight)
        }

        static func ui(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
            let interName: String
            switch weight {
            case .bold, .heavy, .black: interName = "Inter-Bold"
            case .semibold:             interName = "Inter-SemiBold"
            case .medium:               interName = "Inter-Medium"
            default:                    interName = "Inter-Regular"
            }
            if let f = NSFont(name: interName, size: size) { return f }
            return NSFont.systemFont(ofSize: size, weight: weight)
        }
    }

    // ── Radius ────────────────────────────────────────────────────────────────
    enum Radius {
        static let pill:     CGFloat = 8    // window pills, small tiles
        static let control:  CGFloat = 11   // inputs, buttons, app icon group
        static let panel:    CGFloat = 16   // floating panels
        static let modal:    CGFloat = 18   // dialogs / overlays
        static let keycap:   CGFloat = 6    // keyboard shortcut chips
        static let checkbox: CGFloat = 6    // checkbox corner
    }

    // ── Metrics ───────────────────────────────────────────────────────────────
    enum Metric {
        // Bar
        static let pillH:          CGFloat = 28
        static let pillPadH:       CGFloat = 10
        static let pillGap:        CGFloat = 5
        static let appIconSize:    CGFloat = 26
        static let appGroupGap:    CGFloat = 14
        static let appGroupRadius: CGFloat = 11

        // Dialogs
        static let checkboxSize:   CGFloat = 22
        static let buttonH:        CGFloat = 44
        static let inputH:         CGFloat = 48
        static let dialogPadH:     CGFloat = 26
        static let dialogPadV:     CGFloat = 24
        static let dialogW:        CGFloat = 480  // default max dialog width

        // Banner
        static let bannerW:        CGFloat = 360
        static let bannerMargin:   CGFloat = 16
        static let barClearance:   CGFloat = 100  // vertical gap below Hub Bar
    }

    // ── ANSI palette ─────────────────────────────────────────────────────────
    //
    // Unified 16-color ANSI palette — the single authoritative copy.
    // Replaces three divergent copies that previously existed in
    // new_workspace_dialog.swift, output_window.swift, and dashboard_dialog.swift.
    //
    static func ansiColor(_ code: Int) -> NSColor {
        switch code {
        // Normal
        case 30: return NSColor(argb: 0xFF3B3B3B)   // Black
        case 31: return Color.destructive             // Red
        case 32: return Color.ok                      // Green
        case 33: return NSColor(argb: 0xFFE5C07B)   // Yellow
        case 34: return Color.accentBlue              // Blue
        case 35: return NSColor(argb: 0xFF9B59B6)   // Magenta
        case 36: return Color.accentTeal              // Cyan
        case 37: return Color.textSecondary           // White
        // Bright
        case 90: return Color.textFaint               // Bright Black (grey)
        case 91: return NSColor(argb: 0xFFFF6B6B)   // Bright Red
        case 92: return NSColor(argb: 0xFF4CD988)   // Bright Green
        case 93: return NSColor(argb: 0xFFFFD080)   // Bright Yellow
        case 94: return NSColor(argb: 0xFF6FA8FF)   // Bright Blue
        case 95: return NSColor(argb: 0xFFBF85FF)   // Bright Magenta
        case 96: return NSColor(argb: 0xFF80E8DF)   // Bright Cyan
        case 97: return Color.textPrimary             // Bright White
        default: return Color.textSecondary
        }
    }

    // ── Card / surface helpers ────────────────────────────────────────────────

    enum SurfaceKind { case panel, modal }

    /// Apply the standard panel/modal gradient, border, and rounded corners to
    /// a layer-backed content view. Call after `view.wantsLayer = true`.
    static func applyCardBackground(to view: NSView,
                                    radius: CGFloat,
                                    kind: SurfaceKind = .modal) {
        view.wantsLayer = true
        let topColor = kind == .panel ? Color.panelTop : Color.modalTop
        let botColor = kind == .panel ? Color.panelBot : Color.modalBot

        // Insert gradient as the bottom-most sublayer of the content layer.
        let grad = CAGradientLayer()
        grad.frame = view.bounds
        grad.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        grad.colors = [topColor.cgColor, botColor.cgColor]
        // CALayer y=1 = top (no flip for NSWindow contentView by default)
        grad.startPoint = CGPoint(x: 0.5, y: 1)
        grad.endPoint   = CGPoint(x: 0.5, y: 0)
        view.layer!.insertSublayer(grad, at: 0)

        view.layer!.cornerRadius  = radius
        view.layer!.masksToBounds = true
        view.layer!.borderWidth   = 1
        view.layer!.borderColor   = Color.border.cgColor
    }

    // ── Dismiss button (ClickView) ─────────────────────────────────────────────
    //
    // Returns a pre-wired ClickView dismiss button following the AGENTS.md
    // "Dismissable HUDs" pattern. Caller adds it to the view hierarchy and
    // pins it to the top-right corner.
    //
    static func makeDismissButton(onPress: @escaping () -> Void) -> NSView {
        let cv = ClickView()
        cv.translatesAutoresizingMaskIntoConstraints = false
        cv.wantsLayer = true
        cv.layer?.cornerRadius = Radius.keycap
        cv.layer?.backgroundColor = NSColor(white: 1, alpha: 0.10).cgColor
        cv.onPress = onPress
        cv.hoverColor  = NSColor(white: 1, alpha: 0.20).cgColor
        cv.normalColor = NSColor(white: 1, alpha: 0.10).cgColor

        let lbl = NSTextField(labelWithString: "✕")
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.font      = Theme.Font.ui(10, weight: .semibold)
        lbl.textColor = NSColor(white: 1, alpha: 0.55)
        lbl.isEditable = false; lbl.isBordered = false; lbl.backgroundColor = .clear
        cv.addSubview(lbl)
        NSLayoutConstraint.activate([
            lbl.centerXAnchor.constraint(equalTo: cv.centerXAnchor),
            lbl.centerYAnchor.constraint(equalTo: cv.centerYAnchor),
        ])
        return cv
    }

    // ── Keycap label ──────────────────────────────────────────────────────────

    /// A muted monospace keycap label ("enter", "esc", "tab", "⌘[", …).
    /// Pass `onAccent: true` when placed on an accent-filled button.
    static func makeKeycapLabel(_ text: String, onAccent: Bool = false) -> NSTextField {
        let lbl = NSTextField(labelWithString: text)
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.font = Font.mono(11, weight: .semibold)
        lbl.textColor = onAccent ? NSColor(white: 1, alpha: 0.65) : Color.textFaint
        lbl.isEditable = false
        lbl.isBordered = false
        lbl.backgroundColor = .clear
        return lbl
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: – ClickView
// ─────────────────────────────────────────────────────────────────────────────
//
// Reusable hover-tracking view used for dismiss buttons and other clickable
// areas that need custom hover states. The single canonical implementation —
// previously duplicated in testing_banner.swift and progress_banner.swift.
//
class ClickView: NSView {
    var onPress: (() -> Void)?
    var normalColor: CGColor? { didSet { layer?.backgroundColor = normalColor } }
    var hoverColor:  CGColor?
    private var hoverTrackingArea: NSTrackingArea?

    override func mouseDown(with event: NSEvent) { onPress?() }
    override func mouseEntered(with event: NSEvent) {
        layer?.backgroundColor = hoverColor ?? NSColor(white: 1, alpha: 0.20).cgColor
    }
    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = normalColor ?? NSColor(white: 1, alpha: 0.10).cgColor
    }
    override var acceptsFirstResponder: Bool { false }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea { removeTrackingArea(hoverTrackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self, userInfo: nil)
        hoverTrackingArea = area
        addTrackingArea(area)
    }
}
