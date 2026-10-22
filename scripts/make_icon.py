"""
Build the app icon from the logo artwork and write it as an .icns file or a 1024px .png.

Usage: python scripts/make_icon.py <out.icns|out.png>
  - build/Aayu.icns — `make app` writes this into the bundle on every build.
  - assets/icon.png — committed; the README's icon.
    Re-run this after changing the artwork.

The Aayu logo is `assets/logo.png`: a white-to-lavender lotus on an indigo
tile, drawn on black. The tile is cut out and fitted to Apple's icon grid,
drawn with AppKit at every size macOS asks for, then packed with `iconutil`.
"""

import os
import subprocess
import sys
import tempfile

import AppKit

ART = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "logo.png")
ART_TILE = (49, 46, 1150)   # x, y, size of the tile in the artwork, in pixels from its top-left
TILE = (100, 100, 824)      # x, y, size — Apple's icon grid (824pt square, 100pt margin)
RADIUS = 185
# The artwork's corners are rounder than Apple's; draw it this far past the
# tile on every side so its black corners fall outside the mask.
BLEED = 13


def draw(art: AppKit.NSBitmapImageRep, px: int) -> AppKit.NSBitmapImageRep:
    rep = AppKit.NSBitmapImageRep.alloc().initWithBitmapDataPlanes_pixelsWide_pixelsHigh_bitsPerSample_samplesPerPixel_hasAlpha_isPlanar_colorSpaceName_bytesPerRow_bitsPerPixel_(
        None, px, px, 8, 4, True, False, AppKit.NSDeviceRGBColorSpace, 0, 0)
    ctx = AppKit.NSGraphicsContext.graphicsContextWithBitmapImageRep_(rep)
    AppKit.NSGraphicsContext.saveGraphicsState()
    AppKit.NSGraphicsContext.setCurrentContext_(ctx)
    ctx.setImageInterpolation_(AppKit.NSImageInterpolationHigh)
    xf = AppKit.NSAffineTransform.transform()
    xf.scaleBy_(px / 1024)
    xf.concat()

    x, y, size = TILE
    AppKit.NSBezierPath.bezierPathWithRoundedRect_xRadius_yRadius_(
        AppKit.NSMakeRect(x, y, size, size), RADIUS, RADIUS).addClip()
    ax, ay, asize = ART_TILE
    source = AppKit.NSMakeRect(ax, art.pixelsHigh() - ay - asize, asize, asize)   # AppKit counts y from the bottom
    art.drawInRect_fromRect_operation_fraction_respectFlipped_hints_(
        AppKit.NSMakeRect(x - BLEED, y - BLEED, size + 2 * BLEED, size + 2 * BLEED), source,
        AppKit.NSCompositingOperationCopy, 1.0, False, None)

    AppKit.NSGraphicsContext.restoreGraphicsState()
    return rep


def write_png(art: AppKit.NSBitmapImageRep, px: int, path: str) -> None:
    png = draw(art, px).representationUsingType_properties_(AppKit.NSBitmapImageFileTypePNG, None)
    png.writeToFile_atomically_(path, True)


def main(out: str) -> None:
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    art = AppKit.NSBitmapImageRep.imageRepWithContentsOfFile_(ART)
    art.setSize_(AppKit.NSMakeSize(art.pixelsWide(), art.pixelsHigh()))   # 1 point = 1 pixel, whatever its DPI
    if out.endswith(".png"):
        write_png(art, 1024, out)
        return
    with tempfile.TemporaryDirectory() as tmp:
        iconset = os.path.join(tmp, "Aayu.iconset")
        os.mkdir(iconset)
        for size in (16, 32, 128, 256, 512):
            for scale in (1, 2):
                name = f"icon_{size}x{size}{'@2x' if scale == 2 else ''}.png"
                write_png(art, size * scale, os.path.join(iconset, name))
        subprocess.run(["iconutil", "-c", "icns", iconset, "-o", out], check=True)


if __name__ == "__main__":
    main(sys.argv[1])
