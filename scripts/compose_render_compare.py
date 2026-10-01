#!/usr/bin/env python3
"""Compose the side-by-side comparison images in design/visual-language/native-renders/compare.

Inputs are the prototype screenshots (native-renders/prototype) and the offscreen native renders
written by the render tests (native-renders/native and native-renders/shadow; run
SignalOverlayRenderTests and SignalFloatShadowTests with
TEST_RUNNER_LIQUID_VOICE_RENDER_DIR=<folder>, then copy the PNGs in).

    python3 scripts/compose_render_compare.py [--shadow-label "r18 y9"]

Each compare/<theme>-<state>.png is the prototype on the left and the native render on the right,
under a 40 px mono caption; compare/shadow-<theme>.png is the flat pill and card beside the same
over their floating shadow. Needs Pillow.
"""
import argparse
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent / "design/visual-language/native-renders"
HEADER = 40
GAP = 24
BG = {"dark": (40, 41, 46), "light": (226, 227, 231)}
INK = {"dark": (214, 215, 219), "light": (17, 18, 20)}
FONT = ImageFont.truetype("/System/Library/Fonts/SFNSMono.ttf", 20)


def caption(draw, xy, text, theme):
    draw.text(xy, text, font=FONT, fill=INK[theme])


def pair(theme, left, right, labels, out):
    width = left.width + GAP + right.width
    height = HEADER + max(left.height, right.height)
    canvas = Image.new("RGB", (width, height), BG[theme])
    canvas.paste(left, (0, HEADER))
    canvas.paste(right, (left.width + GAP, HEADER))
    draw = ImageDraw.Draw(canvas)
    caption(draw, (8, 9), labels[0], theme)
    caption(draw, (left.width + GAP + 8, 9), labels[1], theme)
    canvas.save(out)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--shadow-label", default="r18 y9")
    args = parser.parse_args()
    compare = ROOT / "compare"
    compare.mkdir(exist_ok=True)
    for native in sorted((ROOT / "native").glob("*.png")):
        prototype = ROOT / "prototype" / native.name
        if not prototype.exists():
            continue
        theme = native.name.split("-", 1)[0]
        state = native.stem
        pair(
            theme,
            Image.open(prototype).convert("RGB"),
            Image.open(native).convert("RGB"),
            (f"PROTOTYPE  {state}", "NATIVE (SwiftUI, offscreen)"),
            compare / native.name,
        )
    for theme in ("dark", "light"):
        rows = []
        for state in ("01-listening", "07-failed"):
            flat = ROOT / "shadow" / f"{theme}-{state}-flat.png"
            shadow = ROOT / "shadow" / f"{theme}-{state}-shadow.png"
            if not (flat.exists() and shadow.exists()):
                break
            row = compare / f".row-{theme}-{state}.png"
            label = args.shadow_label if theme == "dark" else "r12 y5"
            pair(
                theme,
                Image.open(flat).convert("RGB"),
                Image.open(shadow).convert("RGB"),
                ("BEFORE  flat 2 pt drop rule", f"AFTER  floating shadow ({label}) + drop rule"),
                row,
            )
            rows.append(row)
        if len(rows) == 2:
            images = [Image.open(r) for r in rows]
            canvas = Image.new("RGB", (max(i.width for i in images), sum(i.height for i in images)), BG[theme])
            y = 0
            for image in images:
                canvas.paste(image, (0, y))
                y += image.height
            canvas.save(compare / f"shadow-{theme}.png")
        for row in rows:
            row.unlink()


if __name__ == "__main__":
    main()
