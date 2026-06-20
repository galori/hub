# Hub Design Style Guide

**Source of truth:** `styleguide/Style Guide.html` (Figma export, full spec).  
**Tokens:** `lib/theme.swift` — `Theme.Color`, `Theme.Font`, `Theme.Radius`, `Theme.Metric`.  
This file is the fast working reference; it does not replace the HTML.

---

## Principles

1. **Floating & docked** — every UI is either a floating panel (blur/shadow) or docked to the Hub Bar. No native titlebars.
2. **Mono means machine** — monospace (`Theme.Font.mono`) for anything system-generated (paths, branch names, log output, step labels). Inter (`Theme.Font.ui`) for prose, titles, button labels.
3. **One bright thing** — at most one accent color per surface (teal for the Hub Bar, blue for modals/launchers). Never mix accents on the same card.

---

## Color Tokens

### Surfaces

| Token | Hex | Usage |
|---|---|---|
| `Theme.Color.canvas` | `#0D0E12` | Window/text-view background |
| `Theme.Color.panelTop` | `#1A1C22` | Panel gradient top |
| `Theme.Color.panelBot` | `#15171C` | Panel gradient bottom, status bars |
| `Theme.Color.modalTop` | `#1C1E25` | Modal/dialog gradient top |
| `Theme.Color.modalBot` | `#16181D` | Modal/dialog gradient bottom |
| `Theme.Color.inputField` | `#2C2F3B` | Text fields, list backgrounds, prompt areas |
| `Theme.Color.clusterBg` | `#181A20` | Bar cluster occluder |

Apply gradient surfaces with:
```swift
Theme.applyCardBackground(to: view, radius: Theme.Radius.modal, kind: .modal)
Theme.applyCardBackground(to: view, radius: Theme.Radius.panel, kind: .panel)
```

### Borders & Highlights

| Token | Value | Usage |
|---|---|---|
| `Theme.Color.border` | `white @6%` | Standard card/field border |
| `Theme.Color.borderStrong` | `white @8%` | Card border (progress container, autocomplete panel) |
| `Theme.Color.insetHighlight` | `white @5%` | Top-edge 1px highlight on raised surfaces |

### Text

| Token | Hex | Role |
|---|---|---|
| `Theme.Color.textTitle` | `#F0F1F4` | Largest headings |
| `Theme.Color.textPrimary` | `#E8EAF0` | Body copy, active step labels, field text |
| `Theme.Color.textLabel` | `#D4D7DE` | Button labels, checkbox labels |
| `Theme.Color.textSecondary` | `#AEB3BF` | Secondary info, done-step labels |
| `Theme.Color.textBody` | `#9AA0AC` | Body paragraphs |
| `Theme.Color.textMuted` | `#7D818C` | Subtitles, path labels, overlay title |
| `Theme.Color.textFaint` | `#5A5D68` | Timestamps, placeholder text, dim labels |

### Accents & Status

| Token | Hex | Usage |
|---|---|---|
| `Theme.Color.accentTeal` | `#41D1C4` | Hub Bar pills, Hub Bar elements |
| `Theme.Color.accentBlue` | `#3B82F6` | Modals, progress border, primary buttons |
| `Theme.Color.ok` | `#37D07A` | Success state, checkmarks, "new worktree" row |
| `Theme.Color.activity` | `#F0883E` | Activity indicator, orange accent |
| `Theme.Color.destructive` | `#E06C6C` | Delete/remove actions, error states |

### Soft / Glow Variants

| Token | Alpha | Usage |
|---|---|---|
| `Theme.Color.okSoft` | `ok @14%` | Done-badge circle background |
| `Theme.Color.accentBlueSoft` | `blue @16%` | Autocomplete row highlight |
| `Theme.Color.accentTealSoft` | `teal @13%` | Teal glow |
| `Theme.Color.activitySoft` | `activity @14%` | Activity glow |

---

## Typography

```swift
// Machine-readable / code / paths / step labels
Theme.Font.mono(size)                      // JetBrains Mono NF → Hack NF → system mono
Theme.Font.mono(size, weight: .semibold)   // Active/running step labels

// Prose / titles / button labels
Theme.Font.ui(size)                        // Inter → system font
Theme.Font.ui(size, weight: .bold)         // Button labels, dialog titles
```

**Progress rows:** `Theme.Font.mono(12)` — pending/done; `Theme.Font.mono(12, weight: .semibold)` — active.  
**Step labels spec:** 12pt mono (pending/done), 12pt semibold mono (active — matches 13.5pt spec scaled to macOS pt).  
**Dialog titles:** `Theme.Font.ui(15, weight: .semibold)`, color `textMuted`.  
**Section labels:** `Theme.Font.ui(10, weight: .semibold)`, color `textMuted`, ALL CAPS.

---

## Radius Tokens

| Token | Value | Usage |
|---|---|---|
| `Theme.Radius.pill` | `8pt` | Hub Bar window pills, small tiles |
| `Theme.Radius.control` | `11pt` | Inputs, buttons, branch/worktree rows |
| `Theme.Radius.panel` | `16pt` | Floating panels |
| `Theme.Radius.modal` | `18pt` | Dialogs, overlays, progress container |
| `Theme.Radius.keycap` | `6pt` | Keyboard shortcut chips, small buttons |
| `Theme.Radius.checkbox` | `6pt` | Checkbox corners |

---

## Metric Tokens

```swift
Theme.Metric.bannerW        // 360pt  — progress/testing banner width
Theme.Metric.bannerMargin   // 16pt   — gap from screen edge
Theme.Metric.barClearance   // 100pt  — vertical gap below Hub Bar
Theme.Metric.buttonH        // 44pt   — standard button height
Theme.Metric.inputH         // 48pt   — standard input height
Theme.Metric.dialogPadH     // 26pt   — dialog horizontal padding
Theme.Metric.dialogPadV     // 24pt   — dialog vertical padding
Theme.Metric.dialogW        // 480pt  — default max dialog width
Theme.Metric.checkboxSize   // 22pt   — checkbox box size
```

---

## Components

### Progress & State Container

```
Container:  applyCardBackground(.modal) with accent border (not the standard border)
            radius 14–18, rows gap 4, row padding 8×12
```

Row layout — always 18×18 indicator slot + 8pt gap + mono label:

**Pending** (not-yet-started step):
- Indicator: 6×6 dot, `white @16%`, corner radius 3
- Label: `Theme.Font.mono(12)`, `textMuted`

**Active / Running**:
- Row background: `white @4%`, corner radius 9 (`≈ Theme.Radius.pill`)
- Indicator: `SpinnerRing` — 15×15, 2pt track `white @15%`, accent arc `accentBlue`, rotates 0.7s linear
- Label: `Theme.Font.mono(12, weight: .semibold)`, `textPrimary`

**Done**:
- Indicator: 18×18 circle, fill `okSoft`, centered `✓` in `Theme.Font.mono(10, weight: .bold)`, color `ok`
- Animation: scale 0.6→1 + fade, 0.2s ease-out
- Label: `Theme.Font.mono(12)`, `textSecondary`

**Error**:
- Indicator: `✗`, `Theme.Font.mono(11, weight: .semibold)`, `destructive`
- Label: `destructive`

### Buttons

Three kinds — rendered as a container view with gesture recognizer (not NSButton):

```
.primary    bg: accentBlue           label: white bold
.destructive bg: destructive         label: white bold
.secondary  bg: inputField, border   label: textLabel medium
```

Width 110–140pt, height `buttonH` (44pt), radius `control` (11pt).  
Labels: `Theme.Font.ui(13, weight: .bold)`.  
Trailing keycap: `Theme.makeKeycapLabel("enter"/"esc")`.

Use `makeBtn` in each dialog file for `NSButton`-based buttons (new_workspace_dialog uses a slightly different helper that takes `bg:` / `fg:` params).

### Fields & Inputs

```swift
field.layer?.backgroundColor = Theme.Color.inputField.cgColor
field.layer?.cornerRadius    = Theme.Radius.control
field.textColor              = Theme.Color.textPrimary
field.font                   = Theme.Font.mono(14)
// Placeholder:
.foregroundColor: Theme.Color.textFaint
.font:            Theme.Font.mono(14)
```

### Checkboxes

```
Box:    22×22 (Metric.checkboxSize), radius Radius.checkbox (6pt)
On:     accentBlue fill + white checkmark (2pt lineWidth, round cap)
Off:    inputField fill + white@22% border (1.5pt)
Label:  Theme.Font.ui(14, weight: .medium), textLabel, 10pt right of box
```

Canonical implementation: `confirm_dialog.swift: CustomCheckbox` (also mirrored in `new_workspace_dialog.swift`).

### Keycap Chips

```swift
Theme.makeKeycapLabel("enter", onAccent: false)  // textFaint
Theme.makeKeycapLabel("enter", onAccent: true)   // white@65%
// Font: Theme.Font.mono(11, weight: .semibold)
```

### Dismiss Button (✕)

```swift
Theme.makeDismissButton(onPress: { dismiss() })
// bg white@10%, hover white@20%, radius keycap (6pt), label "✕" ui(10,.semibold) white@55%
```

All floating HUDs tied to an external process **must** include this button (`ignoresMouseEvents = false`).

### Hub Bar Pills

```swift
bg (idle):   Theme.Color.pillIdleBg   // white @3.5%
bg (hover):  Theme.Color.pillHoverBg  // white @9%
bg (active): Theme.Color.accentTeal   // teal fill
radius:      Theme.Radius.pill (8pt)
height:      Theme.Metric.pillH (28pt)
```

### App Switcher Card

```swift
bg:          Theme.Color.modalTop
border:      Theme.Color.borderStrong (white @8%)
radius:      20pt (intentionally larger than modal 18pt for the floating card look)
highlight:   TILE_HI_BG = accentBlue @90%, glow = accentBlue
cancel:      destructive @85%, glow = destructive
```

### Backdrop Scrims

Full-screen modal backdrops use `NSColor(white: 0, alpha: 0.85)` — intentionally pure black, not a token.

---

## Applying to a New Component

1. **Window**: `.borderless`, `.clear` background, `hasShadow = true`, `collectionBehavior = [.canJoinAllSpaces, .stationary]`
2. **Content view**: `Theme.applyCardBackground(to: cv, radius: …, kind: .modal/.panel)`
3. **Text**: use `Theme.Font.mono/ui`, color from `Theme.Color.text*`
4. **Interactive**: use `ClickView` + gesture recognizer (not NSButton for custom-drawn buttons); wire `Theme.makeDismissButton` for any persistent HUD
5. **ANSI output**: call `Theme.ansiColor(code)` — the single authoritative palette (do not add a local copy)

---

## Files Quick Reference

| File | Status | Notes |
|---|---|---|
| `lib/theme.swift` | ✅ Authoritative | All tokens, `applyCardBackground`, `makeDismissButton`, `makeKeycapLabel`, `ClickView`, `ansiColor` |
| `lib/hub_bar.swift` | ✅ Themed | Uses teal accent |
| `lib/progress_banner.swift` | ✅ Themed | Custom `SpinnerRing`, style-guide step rows |
| `lib/overlay.swift` | ✅ Themed | Short-lived modal overlay |
| `lib/confirm_dialog.swift` | ✅ Themed | Reference `CustomCheckbox` implementation |
| `lib/rename_dialog.swift` | ✅ Themed | |
| `lib/dashboard_dialog.swift` | ✅ Themed | |
| `lib/http_handler.swift` | ✅ Themed | |
| `lib/testing_banner.swift` | ✅ Themed | |
| `lib/new_workspace_dialog.swift` | ✅ Themed | Largest dialog; uses local `makeBtn(bg:fg:)` helper |
| `lib/app_switcher.swift` | ✅ Themed | Card radius 20pt (intentional) |
| `lib/output_window.swift` | ✅ Themed | |
| `lib/log_viewer.swift` | ✅ Themed | |
