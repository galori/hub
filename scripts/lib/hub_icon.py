#!/usr/bin/env python3
"""
hub_icon.py — composite a prominent POWER (⏻) badge onto the Hub logo.

Usage:
  python3 scripts/lib/hub_icon.py <input_png> <output_png> --state on|off|auto

- input_png: a 512x512 padded Hub logo (as produced by `sips -p 512 512`)
- output_png: destination 512x512 PNG with the power badge composited
- --state: color of the badge:
    on  -> green (#22c55e)  — Hub is up
    off -> red   (#ef4444)  — Hub is down
    auto defaults to on (green) if detection unavailable

The badge is intentionally large and high-contrast so it reads at Dock
sizes (16–48 pt). It sits in the lower-right quadrant so it doesn't
obscure the ship's wheel or the HUB wordmark.
"""

import argparse
import sys
from PIL import Image, ImageDraw, ImageFilter


def _hex_to_rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i : i + 2], 16) for i in (0, 2, 4))


# Styleguide-matched colors
GREEN_FILL = "#22c55e"   # close to #37d07a but higher contrast on dark
GREEN_RING = "#16a34a"
RED_FILL = "#ef4444"     # close to #e06c6c but higher contrast
RED_RING = "#dc2626"
NEUTRAL_FILL = "#6b7280"
DROP_SHADOW = (0, 0, 0, 90)

# Badge geometry on a 512x512 canvas — positioned to avoid the
# "HUB" wordmark (bottom-center) while remaining prominent at Dock sizes.
BADGE_CX = 410
BADGE_CY = 335
BADGE_R = 72          # outer radius of the colored disc
BADGE_BORDER = 7      # white ring thickness
BADGE_SHADOW_R = 84   # shadow slightly larger


def draw_power_symbol(draw: ImageDraw.ImageDraw, cx: int, cy: int, r: int, color, width: int):
    """
    Draw the IEC 5009 standby/power glyph:
      - a circular arc with a gap at the top (~36° gap)
      - a vertical bar through the gap from center upward
    r is the radius of the arc, color is (R,G,B,A), width is stroke width.
    """
    # Gap 36° centered at top (12 o'clock). In Pillow's coordinate system:
    #   0° = east, 90° = south, 180° = west, 270° = north (top).
    # So gap centered at 270°.
    gap = 36
    start = 270 + gap / 2  # 288
    end = 270 - gap / 2 + 360  # 612 == 252+360, draw the long way around
    bbox = [cx - r, cy - r, cx + r, cy + r]
    # Pillow's arc stroke is centered on the bbox edge; use width for thickness.
    # Draw the arc slightly thicker than the stem for visual balance.
    draw.arc(bbox, start=start, end=end, fill=color, width=width)

    # Vertical stem: rectangle centered at cx, from cy up to near top of arc.
    # The stem should stop just short of the gap so it doesn't touch the arc.
    stem_top = cy - r + 2
    stem_bottom = cy + 6  # small overshoot past center for balance
    stem_half = width // 2
    # Round caps via small ellipse at each end
    draw.rectangle([cx - stem_half, stem_top, cx + stem_half, stem_bottom], fill=color)
    # Round the top tip
    draw.ellipse(
        [cx - stem_half, stem_top - stem_half, cx + stem_half, stem_top + stem_half],
        fill=color,
    )
    draw.ellipse(
        [cx - stem_half, stem_bottom - stem_half, cx + stem_half, stem_bottom + stem_half],
        fill=color,
    )


def composite_power_badge(input_path: str, output_path: str, state: str):
    base = Image.open(input_path).convert("RGBA")
    # Ensure 512x512 — if input is 512x512 already we keep it, otherwise create centered canvas.
    if base.size != (512, 512):
        canvas = Image.new("RGBA", (512, 512), (0, 0, 0, 0))
        # scale to fit inside 512 preserving aspect, like sips -p
        w, h = base.size
        scale = min(512 / w, 512 / h)
        if scale < 1 or (w < 512 and h < 512):
            # If smaller than 512, upscale to fill (matching sips -p behavior approx)
            # Only upscale if image is substantially smaller (the hub-logo is 349x400 -> ~447x512)
            new_w, new_h = int(w * scale), int(h * scale)
            # Use high-quality resize
            base = base.resize((new_w, new_h), Image.LANCZOS)
            w, h = new_w, new_h
        # center
        off_x = (512 - w) // 2
        off_y = (512 - h) // 2
        canvas.alpha_composite(base, (off_x, off_y))
        base = canvas
    else:
        # Ensure we work on a copy so we can composite shadow beneath
        pass

    # Create overlay for badge (separate layer for blur shadow)
    overlay = Image.new("RGBA", (512, 512), (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)

    # Choose colors
    if state == "on":
        fill = _hex_to_rgb(GREEN_FILL)
        ring = _hex_to_rgb(GREEN_RING)
    elif state == "off":
        fill = _hex_to_rgb(RED_FILL)
        ring = _hex_to_rgb(RED_RING)
    else:
        fill = _hex_to_rgb(NEUTRAL_FILL)
        ring = _hex_to_rgb(NEUTRAL_FILL)

    # Drop shadow: draw a larger dark ellipse slightly offset (y+4), then blur
    shadow_layer = Image.new("RGBA", (512, 512), (0, 0, 0, 0))
    s_draw = ImageDraw.Draw(shadow_layer)
    s_draw.ellipse(
        [
            BADGE_CX - BADGE_SHADOW_R,
            BADGE_CY - BADGE_SHADOW_R + 6,
            BADGE_CX + BADGE_SHADOW_R,
            BADGE_CY + BADGE_SHADOW_R + 6,
        ],
        fill=DROP_SHADOW,
    )
    # Blur shadow for softness
    shadow_layer = shadow_layer.filter(ImageFilter.GaussianBlur(radius=10))
    # Composite shadow first (beneath badge)
    base = Image.alpha_composite(base, shadow_layer)

    # White outer ring (for separation against any background)
    draw.ellipse(
        [
            BADGE_CX - BADGE_R - BADGE_BORDER,
            BADGE_CY - BADGE_R - BADGE_BORDER,
            BADGE_CX + BADGE_R + BADGE_BORDER,
            BADGE_CY + BADGE_R + BADGE_BORDER,
        ],
        fill=(255, 255, 255, 255),
    )
    # Subtle outer stroke / drop for white ring: already have shadow

    # Colored fill disc
    draw.ellipse(
        [BADGE_CX - BADGE_R, BADGE_CY - BADGE_R, BADGE_CX + BADGE_R, BADGE_CY + BADGE_R],
        fill=fill + (255,),
    )
    # Inner highlight ring (thin darker ring at edge for depth)
    draw.ellipse(
        [BADGE_CX - BADGE_R, BADGE_CY - BADGE_R, BADGE_CX + BADGE_R, BADGE_CY + BADGE_R],
        outline=ring + (255,),
        width=3,
    )

    # Power glyph: white, slightly smaller than badge radius
    glyph_r = int(BADGE_R * 0.58)  # ~43px
    glyph_width = 9
    # Slight drop shadow for glyph for legibility
    # Draw shadow first offset by 1.5px
    draw_power_symbol(draw, BADGE_CX + 1, BADGE_CY + 2, glyph_r, (0, 0, 0, 50), glyph_width + 2)
    draw_power_symbol(draw, BADGE_CX, BADGE_CY, glyph_r, (255, 255, 255, 255), glyph_width)

    # Composite badge overlay onto base
    result = Image.alpha_composite(base, overlay)
    result.save(output_path, "PNG")
    return result


def main():
    p = argparse.ArgumentParser()
    p.add_argument("input_png", help="512x512 padded input PNG")
    p.add_argument("output_png", help="512x512 output PNG with badge")
    p.add_argument("--state", choices=["on", "off", "auto", "neutral"], default="on", help="badge color state")
    args = p.parse_args()
    state = args.state
    if state == "auto":
        state = "on"
    if state == "neutral":
        state = "off"  # fallback, but keep neutral gray if you change mapping
        # use neutral handling: we map neutral to gray inside composite
        # so override composite to use gray
        state_for_composite = "neutral"
        composite_power_badge(args.input_png, args.output_png, state_for_composite)
        return
    composite_power_badge(args.input_png, args.output_png, state)


if __name__ == "__main__":
    main()
