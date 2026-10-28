#!/usr/bin/env python3
"""Transparency helpers so images with an alpha channel survive the pipeline.

The neural engine and the JPEG print finisher both discard transparency. For a transparent
PNG the pipeline therefore upscales the alpha mask (and the colour, unless it is one solid
colour) separately, then recombines them into a transparent PNG.

  probe  Print "transparent" or "opaque".
  split  Write the alpha mask (and colour, if it varies) as engine-ready RGB PNGs.
  merge  Recombine upscaled pieces and resize to the target width.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from PIL import Image


def has_transparency(image: Image.Image) -> bool:
    if image.mode in ("RGBA", "LA"):
        return image.getchannel("A").getextrema()[0] < 255
    return image.mode == "P" and "transparency" in image.info


def probe(args: argparse.Namespace) -> None:
    with Image.open(args.input) as image:
        print("transparent" if has_transparency(image) else "opaque")


def split(args: argparse.Namespace) -> None:
    with Image.open(args.input) as opened:
        image = opened.convert("RGBA")

    alpha = image.getchannel("A")
    Image.merge("RGB", (alpha, alpha, alpha)).save(args.mask)

    # Only pixels that are visible say anything about the colour.
    rgb = image.convert("RGB").tobytes()
    coverage = alpha.tobytes()
    colours = {rgb[i * 3 : i * 3 + 3] for i, a in enumerate(coverage) if a > 0}
    if len(colours) == 1:
        print("solid {} {} {}".format(*next(iter(colours))))
    else:
        image.convert("RGB").save(args.color)
        print("varied")


def merge(args: argparse.Namespace) -> None:
    mask = Image.open(args.mask).convert("L")
    height = round(mask.height * args.width / mask.width)
    size = (args.width, height)
    mask = mask.resize(size, Image.Resampling.LANCZOS)

    if args.color:
        base = Image.open(args.color).convert("RGB").resize(size, Image.Resampling.LANCZOS)
    else:
        base = Image.new("RGB", size, tuple(args.solid))
    base.putalpha(mask)

    Path(args.output).parent.mkdir(parents=True, exist_ok=True)
    base.save(args.output, format="PNG", dpi=(args.ppi, args.ppi), optimize=True)
    print(f"Saved: {args.output}")
    print(f"Dimensions: {size[0]}x{size[1]} px at {args.ppi} ppi (transparent PNG)")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("probe")
    p.add_argument("--input", required=True)
    p.set_defaults(func=probe)

    p = sub.add_parser("split")
    p.add_argument("--input", required=True)
    p.add_argument("--mask", required=True, help="Where to write the alpha mask")
    p.add_argument("--color", required=True, help="Where to write the colour, if it varies")
    p.set_defaults(func=split)

    p = sub.add_parser("merge")
    p.add_argument("--mask", required=True, help="AI-upscaled alpha mask")
    p.add_argument("--color", help="AI-upscaled colour; omit for a solid colour")
    p.add_argument("--solid", type=int, nargs=3, metavar=("R", "G", "B"))
    p.add_argument("--output", required=True)
    p.add_argument("--width", required=True, type=int)
    p.add_argument("--ppi", required=True, type=int)
    p.set_defaults(func=merge)

    args = parser.parse_args()
    if args.command == "merge" and not args.color and not args.solid:
        parser.error("merge needs --color or --solid")
    return args


if __name__ == "__main__":
    try:
        args = parse_args()
        args.func(args)
    except Exception as error:  # Show a concise, actionable error in PowerShell.
        print(f"ERROR: {error}", file=sys.stderr)
        raise SystemExit(1)
