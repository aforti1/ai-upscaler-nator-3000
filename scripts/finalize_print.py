#!/usr/bin/env python3
"""Finish a neural-upscaled image for a fixed physical print size.

The neural network produces the restoration. This script performs only deterministic
print finishing: aspect-ratio validation, final Lanczos resize, sRGB tagging, optional
subtle film grain, and a compact visual proof.
"""

from __future__ import annotations

import argparse
import io
import math
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageCms, ImageEnhance, ImageOps

# Two x4 passes on a ~900 px source exceed Pillow's ~179 MP decompression-bomb guard;
# inputs here are our own local neural intermediates, so the guard only gets in the way.
Image.MAX_IMAGE_PIXELS = None


def positive_int(value: str) -> int:
    parsed = int(value)
    if parsed <= 0:
        raise argparse.ArgumentTypeError("must be a positive integer")
    return parsed


def grain(image: Image.Image, strength: float) -> Image.Image:
    """Add restrained mono film grain, weighted more strongly into shadows."""
    if strength <= 0:
        return image

    width, height = image.size
    # Half-resolution coarse noise retains an organic scanned-print character.
    coarse = Image.effect_noise((max(1, width // 2), max(1, height // 2)), 12)
    coarse = coarse.resize((width, height), Image.Resampling.LANCZOS)
    coarse = ImageEnhance.Contrast(coarse).enhance(1.12)
    texture = Image.merge("RGB", (coarse, coarse, coarse))
    textured = ImageChops.overlay(image, texture)

    # Grain belongs mainly in shadows; protect highlights and skin from over-texturing.
    luminance = image.convert("L")
    opacity = ImageOps.invert(luminance).point(
        lambda value: int(min(255, 28 + value * 0.72 * strength / 0.12))
    )
    return Image.composite(textured, image, opacity)


def srgb_profile_bytes() -> bytes:
    profile = ImageCms.ImageCmsProfile(ImageCms.createProfile("sRGB"))
    return profile.tobytes()


def run(args: argparse.Namespace) -> None:
    source = Path(args.input).expanduser().resolve()
    output = Path(args.output).expanduser().resolve()
    proof = Path(args.proof).expanduser().resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    proof.parent.mkdir(parents=True, exist_ok=True)

    target_ratio = args.width / args.height
    with Image.open(source) as opened:
        image = opened.convert("RGB")

    source_ratio = image.width / image.height
    ratio_error = abs(source_ratio - target_ratio) / target_ratio
    if ratio_error > 0.002:
        raise ValueError(
            f"Aspect ratio mismatch: neural image is {image.width}x{image.height} "
            f"({source_ratio:.6f}), target is {args.width}x{args.height} "
            f"({target_ratio:.6f}). Refusing to crop without an explicit composition step."
        )

    if image.size != (args.width, args.height):
        image = image.resize((args.width, args.height), Image.Resampling.LANCZOS)

    image = grain(image, args.grain)
    profile = srgb_profile_bytes()
    image.save(
        output,
        format="JPEG",
        quality=args.quality,
        subsampling=0,
        optimize=True,
        dpi=(args.ppi, args.ppi),
        icc_profile=profile,
    )

    # A 1200-pixel-tall proof is convenient for reviewing in normal image viewers.
    proof_height = min(1200, image.height)
    proof_width = max(1, round(proof_height * image.width / image.height))
    image.resize((proof_width, proof_height), Image.Resampling.LANCZOS).save(
        proof,
        format="JPEG",
        quality=92,
        subsampling=0,
        optimize=True,
        icc_profile=profile,
    )

    print(f"Saved: {output}")
    print(f"Dimensions: {args.width}x{args.height} px at {args.ppi} ppi")
    print(f"Saved proof: {proof}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True, help="AI-upscaled input image")
    parser.add_argument("--output", required=True, help="Final 300-ppi JPEG path")
    parser.add_argument("--proof", required=True, help="Smaller proof JPEG path")
    parser.add_argument("--width", required=True, type=positive_int, help="Target pixel width")
    parser.add_argument("--height", required=True, type=positive_int, help="Target pixel height")
    parser.add_argument("--ppi", required=True, type=positive_int, help="Print-resolution metadata")
    parser.add_argument("--quality", type=int, default=95, choices=range(70, 101))
    parser.add_argument("--grain", type=float, default=0.12, help="0 disables grain; 0.08-0.16 is subtle")
    args = parser.parse_args()
    if not 0 <= args.grain <= 0.25:
        parser.error("--grain must be between 0 and 0.25")
    return args


if __name__ == "__main__":
    try:
        run(parse_args())
    except Exception as error:  # Show a concise, actionable error in PowerShell.
        print(f"ERROR: {error}", file=sys.stderr)
        raise SystemExit(1)
