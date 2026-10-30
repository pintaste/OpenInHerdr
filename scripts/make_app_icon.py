#!/usr/bin/env python3
"""Build the OpenInHerdr AppIcon set from the installed Herdr.app icon.

Pipeline:
  1. Render Herdr.app's icon at 1024×1024 with AppKit (Swift helper).
  2. Add a small "open in" arrow badge in the bottom-right corner so the
     toolbar button is distinguishable from Herdr itself.
  3. Write all macOS AppIcon sizes.

Usage:
  python3 scripts/make_app_icon.py
  python3 scripts/make_app_icon.py --herdr ~/Applications/Herdr.app
"""

from __future__ import annotations

import argparse
import subprocess
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
ICONSET = ROOT / "OpenInHerdr" / "Assets.xcassets" / "AppIcon.appiconset"
SIZES = {
    "icon_16x16.png": 16,
    "icon_32x32.png": 32,
    "icon_64x64.png": 64,
    "icon_128x128.png": 128,
    "icon_256x256.png": 256,
    "icon_512x512.png": 512,
    "icon_1024x1024.png": 1024,
}
CANDIDATES = [Path.home() / "Applications/Herdr.app", Path("/Applications/Herdr.app")]


def extract_via_swift(app: Path, out_png: Path) -> None:
    """Render the app's icon at 1024×1024 with AppKit."""
    swift_src = out_png.with_suffix(".swift")
    bin_path = out_png.with_suffix("")
    swift_src.write_text(
        f"""
import AppKit
let icon = NSWorkspace.shared.icon(forFile: "{app}")
let size: CGFloat = 1024
let rect = NSRect(x: 0, y: 0, width: size, height: size)
guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
) else {{ fputs("rep fail\\n", stderr); exit(1) }}
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSColor.clear.setFill(); rect.fill()
icon.size = NSSize(width: size, height: size)
icon.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)
NSGraphicsContext.restoreGraphicsState()
guard let png = rep.representation(using: .png, properties: [:]) else {{
    fputs("png fail\\n", stderr); exit(1)
}}
try png.write(to: URL(fileURLWithPath: "{out_png}"))
""",
        encoding="utf-8",
    )
    subprocess.check_call(
        ["swiftc", str(swift_src), "-o", str(bin_path), "-framework", "AppKit"],
        stdout=subprocess.DEVNULL,
    )
    subprocess.check_call([str(bin_path)])


def add_badge(src: Image.Image) -> Image.Image:
    """Draw a white circle with an ↗ arrow in the bottom-right corner."""
    scale = 4  # supersample for smooth edges
    size = 1024 * scale
    base = src.convert("RGBA").resize((size, size), Image.Resampling.LANCZOS)
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)

    r = 150 * scale
    cx, cy = 800 * scale, 800 * scale
    shadow = 10 * scale
    d.ellipse([cx - r, cy - r + shadow, cx + r, cy + r + shadow], fill=(0, 0, 0, 70))
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(255, 255, 255, 255))

    ink = (28, 28, 30, 255)
    w = 34 * scale
    a = 62 * scale  # half-length of the arrow shaft
    d.line([cx - a, cy + a, cx + a, cy - a], fill=ink, width=w)
    head = 78 * scale
    tip = (cx + a + w // 3, cy - a - w // 3)
    d.polygon([tip, (tip[0] - head, tip[1]), (tip[0], tip[1] + head)], fill=ink)

    out = Image.alpha_composite(base, layer)
    return out.resize((1024, 1024), Image.Resampling.LANCZOS)


def write_iconset(master: Image.Image, dest: Path) -> None:
    dest.mkdir(parents=True, exist_ok=True)
    for name, size in SIZES.items():
        master.resize((size, size), Image.Resampling.LANCZOS).save(dest / name)
        print(f"  wrote {name}")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--herdr", type=Path, default=None, help="Path to Herdr.app")
    ap.add_argument("--out", type=Path, default=ICONSET, help="AppIcon.appiconset directory")
    args = ap.parse_args()
    app = args.herdr or next((p for p in CANDIDATES if p.is_dir()), None)
    if app is None or not app.is_dir():
        raise SystemExit("Herdr.app not found; pass --herdr /path/to/Herdr.app")

    with tempfile.TemporaryDirectory(prefix="openinherdr-icon-") as tmp:
        raw = Path(tmp) / "herdr_raw_1024.png"
        print(f"extracting icon from {app} …")
        extract_via_swift(app, raw)
        master = add_badge(Image.open(raw))
        print(f"writing iconset → {args.out}")
        write_iconset(master, args.out)
    print("done")


if __name__ == "__main__":
    main()
