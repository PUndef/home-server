"""Build favicon.ico + apple-touch-icon.png from public/requiems/Oull.webp.

Uses the alpha channel of the source as a mask and renders the symbol
in white on a dark indigo circle, so the icon stays visible on both
light and dark browser tab backgrounds.
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "public" / "requiems" / "Oull.webp"
OUT_ICO = ROOT / "public" / "favicon.ico"
OUT_APPLE = ROOT / "public" / "apple-touch-icon.png"

BG = (30, 27, 75, 255)  # tailwind indigo-950
FG = (255, 255, 255, 255)
PADDING_RATIO = 0.16  # 16% margin around the symbol


def render(size: int) -> Image.Image:
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(canvas)
    draw.ellipse((0, 0, size - 1, size - 1), fill=BG)

    src = Image.open(SRC).convert("RGBA")
    alpha = src.split()[-1]

    pad = int(size * PADDING_RATIO)
    inner = size - 2 * pad
    alpha = alpha.resize((inner, inner), Image.LANCZOS)

    fg_layer = Image.new("RGBA", (inner, inner), FG)
    fg_layer.putalpha(alpha)

    canvas.alpha_composite(fg_layer, (pad, pad))
    return canvas


def main() -> None:
    sizes = [16, 32, 48, 64]
    base = render(256)
    base.save(
        OUT_ICO,
        format="ICO",
        sizes=[(s, s) for s in sizes],
    )
    render(180).save(OUT_APPLE, format="PNG", optimize=True)
    print(f"wrote {OUT_ICO.relative_to(ROOT)} ({OUT_ICO.stat().st_size} bytes)")
    print(f"wrote {OUT_APPLE.relative_to(ROOT)} ({OUT_APPLE.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
