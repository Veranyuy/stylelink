#!/usr/bin/env python3
"""Generate StyleLink brand assets — official coral→purple branding.

Official palette:
    coral     #FA5252
    purple    #9333EA
    charcoal  #1F2937
    off-white #FDFBF7

The emblem is the reference logo: a coral→purple gradient ring around a
coral serif "S". Everything is drawn vector-style at 4× supersampling, so
outputs stay crisp at every density (no JPEG-sourced artifacts).

Outputs (all under the `stylelink/` project root):
    assets/images/logo.png             transparent emblem — native splash image
    assets/images/icon_app.png         full-bleed master icon 1024×1024
    assets/images/icon_foreground.png  Android adaptive foreground (transparent)
    web/favicon.png                    32×32
    web/icons/Icon-192.png, Icon-512.png
    web/icons/Icon-maskable-192.png, Icon-maskable-512.png
    android/app/src/main/res/mipmap-*/ic_launcher.png        48/72/96/144/192
    android/app/src/main/res/mipmap-*/ic_launcher_foreground.png
    android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml
    (ic_launcher_background color lives in values/colors.xml, written by
    flutter_launcher_icons — not emitted here, see NOTE below)
    ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-*.png (classic set)
    macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_*.png + Contents.json
    windows/runner/resources/app_icon.ico  (16→256 px embedded sizes)

Desktop paths match Flutter's `flutter create --platforms=macos,windows .`
templates, so the files land (or drop in) exactly where the runners expect
them — generating them before adding the platforms is safe.

The sizes above match what `flutter_launcher_icons` emits for the config in
`flutter_launcher_icons.yaml` — this script is the zero-network fallback and
the source of truth for the emblem design.

Usage:
    "C:\\Users\\veran\\AppData\\Local\\Programs\\Python\\Python312\\python.exe" tool/generate_brand_assets.py
"""

from __future__ import annotations

import math
import os

from PIL import Image, ImageDraw, ImageFont

# ── Official palette ─────────────────────────────────────────────────────────
CORAL = (0xFA, 0x52, 0x52)      # #FA5252
PURPLE = (0x93, 0x33, 0xEA)     # #9333EA
CHARCOAL = (0x1F, 0x29, 0x37)   # #1F2937
OFFWHITE = (0xFD, 0xFB, 0xF7)   # #FDFBF7

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SS = 4  # supersampling factor (draw big, downscale with LANCZOS)

GEORGIA_BOLD = r"C:\Windows\Fonts\georgiab.ttf"
FALLBACK_FONTS = [
    GEORGIA_BOLD,
    r"C:\Windows\Fonts\timesbd.ttf",
    r"C:\Windows\Fonts\arialbd.ttf",
]


def lerp_color(a: tuple, b: tuple, t: float) -> tuple:
    """Linear interpolation between two RGB tuples, t in [0, 1]."""
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def gradient_stop(t: float) -> tuple:
    """Coral (t=0) → purple (t=1) along the official gradient."""
    return lerp_color(CORAL, PURPLE, t)


def draw_emblem(canvas: Image.Image, cx: int, cy: int, ring_diameter: int) -> None:
    """Paint the emblem (gradient ring + coral serif S) onto `canvas`.

    `canvas` is a supersampled RGBA image; `ring_diameter` is the outer
    diameter of the ring at that scale. Stroke ≈ 3.5% of the diameter and the
    "S" ink height ≈ 36% of the diameter, matching the reference logo.
    """
    stroke = max(2, int(ring_diameter * 0.035))
    r_outer = ring_diameter / 2
    r_mid = r_outer - stroke / 2

    # ── Gradient ring: many short arc segments, color interpolated along the
    #    top-left (coral) → bottom-right (purple) axis. ──
    painter = ImageDraw.Draw(canvas)
    segments = 1440
    seg = 360 / segments
    bbox = [cx - r_outer, cy - r_outer, cx + r_outer, cy + r_outer]
    for i in range(segments):
        start = i * seg
        mid = math.radians(start + seg / 2)
        # Projection of the arc midpoint onto the (1,1)/√2 gradient axis,
        # normalized to [0, 1]: bottom-right → 1 (purple), top-left → 0 (coral).
        proj = (math.cos(mid) + math.sin(mid)) / math.sqrt(2)  # [-1, 1]
        t = (proj + 1) / 2
        painter.arc(bbox, start=start, end=start + seg * 1.6, fill=gradient_stop(t), width=stroke)

    # ── Coral serif "S", pasted centered on its exact ink bounding box. ──
    font_size = int(ring_diameter * 0.52)  # Georgia cap height ≈ 0.69×size
    font = None
    for path in FALLBACK_FONTS:
        try:
            font = ImageFont.truetype(path, font_size)
            break
        except OSError:
            continue
    if font is None:
        raise RuntimeError("No serif font found for the emblem 'S'")

    layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(layer).text((cx, cy), "S", font=font, fill=CORAL + (255,))
    ink = layer.getbbox()
    if ink is None:
        raise RuntimeError("Failed to rasterize the emblem 'S'")
    sx, sy, ex, ey = ink
    paste_x = int(cx - (ex - sx) / 2 - sx)
    paste_y = int(cy - (ey - sy) / 2 - sy)
    canvas.alpha_composite(layer, (paste_x, paste_y))


def render_emblem(outer: int, ring_ratio: float = 0.74) -> Image.Image:
    """Render the emblem alone (transparent background) at `outer` size."""
    canvas = Image.new("RGBA", (outer * SS, outer * SS), (0, 0, 0, 0))
    draw_emblem(canvas, canvas.width // 2, canvas.height // 2,
                int(outer * ring_ratio * SS))
    return canvas.resize((outer, outer), Image.LANCZOS)


def render_icon(outer: int, ring_ratio: float = 0.70) -> Image.Image:
    """Full-bleed app icon: off-white background + centered emblem."""
    icon = Image.new("RGBA", (outer, outer), OFFWHITE + (255,))
    emblem = render_emblem(outer, ring_ratio)
    offset = ((outer - emblem.width) // 2, (outer - emblem.height) // 2)
    icon.alpha_composite(emblem, offset)
    return icon.convert("RGB")  # opaque — App Store / mipmap safe


def save(img: Image.Image, rel_path: str) -> None:
    path = os.path.join(ROOT, rel_path)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path)
    print(f"  wrote {rel_path}  {img.size[0]}x{img.size[1]}")


# ── Android ──────────────────────────────────────────────────────────────────────────────────
ANDROID_MIPMAPS = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}

ADAPTIVE_XML = """<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
</adaptive-icon>
"""

# NOTE: the ic_launcher_background color lives in values/colors.xml (written
# by flutter_launcher_icons). Do NOT also emit values/ic_launcher_background.xml
# here — duplicate color definitions make the Gradle resource build fail.

# ── iOS classic AppIcon set (matches the existing Contents.json) ─────────────
IOS_ICONS = {
    "Icon-App-20x20@1x.png": 20,
    "Icon-App-20x20@2x.png": 40,
    "Icon-App-20x20@3x.png": 60,
    "Icon-App-29x29@1x.png": 29,
    "Icon-App-29x29@2x.png": 58,
    "Icon-App-29x29@3x.png": 87,
    "Icon-App-40x40@1x.png": 40,
    "Icon-App-40x40@2x.png": 80,
    "Icon-App-40x40@3x.png": 120,
    "Icon-App-60x60@2x.png": 120,
    "Icon-App-60x60@3x.png": 180,
    "Icon-App-76x76@1x.png": 76,
    "Icon-App-76x76@2x.png": 152,
    "Icon-App-83.5x83.5@2x.png": 167,
    "Icon-App-1024x1024@1x.png": 1024,
}

# ── macOS dock icon — classic 10-slot AppIcon set (every Xcode version) ──────
MACOS_SIZES = {
    "app_icon_16.png": 16,
    "app_icon_32.png": 32,
    "app_icon_64.png": 64,
    "app_icon_128.png": 128,
    "app_icon_256.png": 256,
    "app_icon_512.png": 512,
    "app_icon_1024.png": 1024,
}

MACOS_CONTENTS_JSON = """{
  "images" : [
    {"size":"16x16","idiom":"mac","filename":"app_icon_16.png","scale":"1x"},
    {"size":"16x16","idiom":"mac","filename":"app_icon_32.png","scale":"2x"},
    {"size":"32x32","idiom":"mac","filename":"app_icon_32.png","scale":"1x"},
    {"size":"32x32","idiom":"mac","filename":"app_icon_64.png","scale":"2x"},
    {"size":"128x128","idiom":"mac","filename":"app_icon_128.png","scale":"1x"},
    {"size":"128x128","idiom":"mac","filename":"app_icon_256.png","scale":"2x"},
    {"size":"256x256","idiom":"mac","filename":"app_icon_256.png","scale":"1x"},
    {"size":"256x256","idiom":"mac","filename":"app_icon_512.png","scale":"2x"},
    {"size":"512x512","idiom":"mac","filename":"app_icon_512.png","scale":"1x"},
    {"size":"512x512","idiom":"mac","filename":"app_icon_1024.png","scale":"2x"}
  ],
  "info" : {"author" : "xcode", "version" : 1}
}
"""

# ── Windows — multi-resolution ICO (taskbar, explorer, desktop, shortcuts) ───
WINDOWS_ICO_SIZES = [(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)]


def main() -> None:
    print("Rendering master assets…")
    # Transparent emblem for the native splash (floats on the #FDFBF7 bg).
    save(render_emblem(1024), "assets/images/logo.png")
    # Full-bleed master icon (launcher + favicon source).
    icon1024 = render_icon(1024)
    save(icon1024, "assets/images/icon_app.png")
    # Adaptive foreground: emblem inside the 66dp safe zone (≈0.61 of layer).
    fg = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
    emblem = render_emblem(1024, ring_ratio=0.55)
    fg.alpha_composite(emblem, ((1024 - emblem.width) // 2, (1024 - emblem.height) // 2))
    save(fg, "assets/images/icon_foreground.png")

    print("Web…")
    save(render_icon(32, ring_ratio=0.78), "web/favicon.png")
    save(render_icon(192), "web/icons/Icon-192.png")
    save(render_icon(512), "web/icons/Icon-512.png")
    # The full-bleed icon is already maskable-safe (emblem at 0.70 ≤ safe zone).
    save(render_icon(192), "web/icons/Icon-maskable-192.png")
    save(render_icon(512), "web/icons/Icon-maskable-512.png")

    print("Android…")
    for density, px in ANDROID_MIPMAPS.items():
        save(render_icon(px), f"android/app/src/main/res/{density}/ic_launcher.png")
        save(
            render_emblem(px, ring_ratio=0.55).resize((px, px), Image.LANCZOS),
            f"android/app/src/main/res/{density}/ic_launcher_foreground.png",
        )
    res = os.path.join(ROOT, "android/app/src/main/res")
    os.makedirs(os.path.join(res, "mipmap-anydpi-v26"), exist_ok=True)
    with open(os.path.join(res, "mipmap-anydpi-v26/ic_launcher.xml"), "w", encoding="utf-8") as f:
        f.write(ADAPTIVE_XML)
    print("  wrote mipmap-anydpi-v26/ic_launcher.xml")
    # ic_launcher_background color is intentionally NOT written here; it is
    # owned by values/colors.xml (see NOTE at ADAPTIVE_XML above).

    print("iOS…")
    for name, px in IOS_ICONS.items():
        save(render_icon(px), f"ios/Runner/Assets.xcassets/AppIcon.appiconset/{name}")

    print("macOS…")
    appiconset = "macos/Runner/Assets.xcassets/AppIcon.appiconset"
    for name, px in MACOS_SIZES.items():
        save(render_icon(px), f"{appiconset}/{name}")
    with open(os.path.join(ROOT, appiconset, "Contents.json"), "w", encoding="utf-8") as f:
        f.write(MACOS_CONTENTS_JSON)
    print(f"  wrote {appiconset}/Contents.json")

    print("Windows…")
    ico_path = os.path.join(ROOT, "windows/runner/resources/app_icon.ico")
    os.makedirs(os.path.dirname(ico_path), exist_ok=True)
    # Downscale each embedded size from the 1024 master (Pillow uses LANCZOS).
    icon1024.save(ico_path, sizes=WINDOWS_ICO_SIZES)
    print(f"  wrote windows/runner/resources/app_icon.ico  "
          f"({len(WINDOWS_ICO_SIZES)} embedded sizes, 16-256 px)")

    print("Done — official branding assets generated.")


if __name__ == "__main__":
    main()
