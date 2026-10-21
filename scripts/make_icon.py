"""
Draw the app icon and write it as an .icns file or a 1024px .png.

Usage: python scripts/make_icon.py <out.icns|out.png>
  - build/Aayu.icns — `make app` writes this into the bundle on every build.
  - assets/icon.png — committed; the Dock icon for `make run` and the README.
    Re-run this after changing the design.

The Aayu logo, redrawn as clean vectors from the brushed-metal artwork in
`assets/image copy.png`: a lavender crescent "boat" whose left rim sweeps up
into a tall pointed mast, and a violet sail beside it, on an indigo tile. Each
edge is one cubic Bézier fitted to that artwork (within ~2 px at 1024 px).
Drawn with AppKit at every size macOS asks for, then packed with `iconutil`.
"""

import os
import subprocess
import sys
import tempfile

import AppKit

# Palette, sampled from the logo: indigo tile, lavender hull, violet sail.
C = {"tile_top": "#344BBE", "tile_bottom": "#20267F", "glow": "#4D66DC", "shadow": "#0B1040",
     "hull_light": "#F4F0FF", "hull": "#C3B8EE", "sail_light": "#DCCBFF", "sail": "#9479E0"}

TILE = (100, 100, 824)   # x, y, size — Apple's icon grid (824pt square, 100pt margin)


def color(hex_: str, alpha: float = 1.0) -> AppKit.NSColor:
    r, g, b = (int(hex_[i:i + 2], 16) / 255 for i in (1, 3, 5))
    return AppKit.NSColor.colorWithSRGBRed_green_blue_alpha_(r, g, b, alpha)


def P(u: float, v: float) -> AppKit.NSPoint:
    """A point on the tile from (u, v) in 0–1, measured from its top-left corner."""
    x, y, size = TILE
    return AppKit.NSMakePoint(x + u * size, y + (1 - v) * size)


def curve(start, *segments) -> AppKit.NSBezierPath:
    """A closed path: `start`, then (control 1, control 2, end) cubic segments, in tile units."""
    path = AppKit.NSBezierPath.bezierPath()
    path.moveToPoint_(P(*start))
    for c1, c2, end in segments:
        path.curveToPoint_controlPoint1_controlPoint2_(P(*end), P(*c1), P(*c2))
    path.closePath()
    return path


def gradient(top: str, bottom: str, alpha: float = 1.0):
    return AppKit.NSGradient.alloc().initWithStartingColor_endingColor_(color(top, alpha), color(bottom, alpha))


def draw(px: int) -> AppKit.NSBitmapImageRep:
    rep = AppKit.NSBitmapImageRep.alloc().initWithBitmapDataPlanes_pixelsWide_pixelsHigh_bitsPerSample_samplesPerPixel_hasAlpha_isPlanar_colorSpaceName_bytesPerRow_bitsPerPixel_(
        None, px, px, 8, 4, True, False, AppKit.NSDeviceRGBColorSpace, 0, 0)
    ctx = AppKit.NSGraphicsContext.graphicsContextWithBitmapImageRep_(rep)
    AppKit.NSGraphicsContext.saveGraphicsState()
    AppKit.NSGraphicsContext.setCurrentContext_(ctx)
    xf = AppKit.NSAffineTransform.transform()
    xf.scaleBy_(px / 1024)
    xf.concat()

    # Tile: deep indigo, a little lighter behind the boat, with a hairline rim.
    x, y, size = TILE
    tile = AppKit.NSBezierPath.bezierPathWithRoundedRect_xRadius_yRadius_(
        AppKit.NSMakeRect(x, y, size, size), 185, 185)
    gradient(C["tile_top"], C["tile_bottom"]).drawInBezierPath_angle_(tile, -90)
    AppKit.NSGradient.alloc().initWithStartingColor_endingColor_(
        color(C["glow"], 0.45), color(C["glow"], 0)).drawInBezierPath_relativeCenterPosition_(
        tile, AppKit.NSMakePoint(0, 0.15))
    rim = AppKit.NSBezierPath.bezierPathWithRoundedRect_xRadius_yRadius_(
        AppKit.NSMakeRect(x + 1.5, y + 1.5, size - 3, size - 3), 183.5, 183.5)
    rim.setLineWidth_(3)
    color("#FFFFFF", 0.12).setStroke()
    rim.stroke()

    # Hull: one outline — the bowl from its pointed left tip, round the bottom
    # to the right tip, back along the right rim, up the mast to its point, and
    # down the mast's left edge as it sweeps into the left rim.
    hull = curve((0.2330, 0.5667),
                 ((0.2471, 0.7052), (0.3220, 0.7970), (0.4709, 0.8004)),   # outer edge, down to the keel
                 ((0.6158, 0.8008), (0.7101, 0.7354), (0.7464, 0.5947)),   # and up to the right tip
                 ((0.6789, 0.6181), (0.6297, 0.6446), (0.5267, 0.6299)),   # right rim, back to the mast
                 ((0.5796, 0.5238), (0.6059, 0.3577), (0.5661, 0.1978)),   # mast, right edge, to the point
                 ((0.5711, 0.3450), (0.5327, 0.6155), (0.4114, 0.6232)),   # mast, left edge, into the bowl
                 ((0.3434, 0.6258), (0.2945, 0.6043), (0.2330, 0.5667)))   # left rim, back to the tip

    # Sail: a tall curved wedge off the mast's point, with a scooped foot.
    sail = curve((0.5680, 0.2015),
                 ((0.7573, 0.2923), (0.7884, 0.4517), (0.7573, 0.5607)),   # leading edge, bellied out
                 ((0.6820, 0.5006), (0.5990, 0.5643), (0.5546, 0.5947)),   # foot, scooped up
                 ((0.6211, 0.4797), (0.6356, 0.3586), (0.5680, 0.2015)))   # back up beside the mast

    # A soft shadow under both, so the boat sits on the tile.
    AppKit.NSGraphicsContext.saveGraphicsState()
    shadow = AppKit.NSShadow.alloc().init()
    shadow.setShadowColor_(color(C["shadow"], 0.35))
    shadow.setShadowBlurRadius_(28)
    shadow.setShadowOffset_(AppKit.NSMakeSize(0, -12))
    shadow.set()
    color(C["hull"]).setFill()
    hull.fill()
    sail.fill()
    AppKit.NSGraphicsContext.restoreGraphicsState()

    gradient(C["hull_light"], C["hull"]).drawInBezierPath_angle_(hull, -40)
    gradient(C["sail_light"], C["sail"]).drawInBezierPath_angle_(sail, -70)

    AppKit.NSGraphicsContext.restoreGraphicsState()
    return rep


def write_png(px: int, path: str) -> None:
    png = draw(px).representationUsingType_properties_(AppKit.NSBitmapImageFileTypePNG, None)
    png.writeToFile_atomically_(path, True)


def main(out: str) -> None:
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    if out.endswith(".png"):
        write_png(1024, out)
        return
    with tempfile.TemporaryDirectory() as tmp:
        iconset = os.path.join(tmp, "Aayu.iconset")
        os.mkdir(iconset)
        for size in (16, 32, 128, 256, 512):
            for scale in (1, 2):
                name = f"icon_{size}x{size}{'@2x' if scale == 2 else ''}.png"
                write_png(size * scale, os.path.join(iconset, name))
        subprocess.run(["iconutil", "-c", "icns", iconset, "-o", out], check=True)


if __name__ == "__main__":
    main(sys.argv[1])
