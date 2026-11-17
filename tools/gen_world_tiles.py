#!/usr/bin/env python3
"""
tools/gen_world_tiles.py

Generates the original city/plains tile atlas used by data/tilesets/floor1.json
(assets/tiles/world_tiles.png, 8x7 cells of 32 px = 256x224).

The atlas layout is part of the data contract: keep the coordinates in floor1.json
in sync when moving cells. Ground tiles are fully opaque, decor cells have a
transparent background so they can be drawn on the ZoneView decor layer. Rows 4-6
hold the multi-tile house parts (JGT-123); existing cells never move.

Uses the Python standard library only (struct, zlib, argparse, math, os, random).
Output is deterministic: every tile is drawn with its own seeded random.Random.
"""

from __future__ import annotations

import argparse
import math
import os
import random
import struct
import zlib
from functools import partial

TILE_PX = 32
ATLAS_COLS = 8
ATLAS_ROWS = 7
DEFAULT_SEED = 20261116
DEFAULT_OUT = os.path.join("assets", "tiles", "world_tiles.png")

Color = tuple


def rgba(r: int, g: int, b: int, a: int = 255) -> Color:
    return (r, g, b, a)


def shade(col: Color, delta: int, alpha: int | None = None) -> Color:
    """Brightens (delta > 0) or darkens (delta < 0) an RGBA colour, alpha optional."""
    return (
        max(0, min(255, col[0] + delta)),
        max(0, min(255, col[1] + delta)),
        max(0, min(255, col[2] + delta)),
        col[3] if alpha is None else max(0, min(255, alpha)),
    )


def write_png(filename: str, width: int, height: int, rgba_bytes: bytearray) -> None:
    """Writes an RGBA PNG using only struct and zlib."""

    def chunk(chunk_type: bytes, data: bytes) -> bytes:
        return (
            struct.pack(">I", len(data))
            + chunk_type
            + data
            + struct.pack(">I", zlib.crc32(chunk_type + data) & 0xFFFFFFFF)
        )

    magic = b"\x89PNG\r\n\x1a\n"
    ihdr = chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))

    scanlines = bytearray()
    row_bytes = width * 4
    for y in range(height):
        scanlines.append(0)  # filter type 0 (None)
        start = y * row_bytes
        scanlines.extend(rgba_bytes[start : start + row_bytes])

    idat = chunk(b"IDAT", zlib.compress(bytes(scanlines), 9))
    iend = chunk(b"IEND", b"")

    os.makedirs(os.path.dirname(os.path.abspath(filename)), exist_ok=True)
    with open(filename, "wb") as f:
        f.write(magic + ihdr + idat + iend)


class Canvas:
    def __init__(self, width: int, height: int):
        self.width = width
        self.height = height
        self.data = bytearray(width * height * 4)
        # Per-tile clip rect, so a drawer can never paint into a neighbouring cell.
        self.clip = (0, 0, width, height)

    def _inside(self, x: int, y: int) -> bool:
        left, top, right, bottom = self.clip
        return left <= x < right and top <= y < bottom

    def set(self, x: int, y: int, col: Color) -> None:
        if self._inside(x, y):
            idx = (y * self.width + x) * 4
            self.data[idx : idx + 4] = bytes(col)

    def blend(self, x: int, y: int, col: Color) -> None:
        """Source-over alpha blend (used for soft glow/shadow pixels)."""
        if not self._inside(x, y):
            return
        sa = col[3] / 255.0
        if sa <= 0.0:
            return
        idx = (y * self.width + x) * 4
        da = self.data[idx + 3] / 255.0
        oa = sa + da * (1.0 - sa)
        if oa <= 0.0:
            self.data[idx : idx + 4] = b"\x00\x00\x00\x00"
            return
        for channel in range(3):
            dst = self.data[idx + channel]
            self.data[idx + channel] = int(
                round((col[channel] * sa + dst * da * (1.0 - sa)) / oa)
            )
        self.data[idx + 3] = int(round(oa * 255.0))

    def rect(self, x: int, y: int, w: int, h: int, col: Color) -> None:
        for py in range(max(0, y), min(self.height, y + h)):
            for px in range(max(0, x), min(self.width, x + w)):
                self.set(px, py, col)

    def circle(self, cx: int, cy: int, radius: int, col: Color, blended: bool = False) -> None:
        r2 = radius * radius
        for py in range(cy - radius, cy + radius + 1):
            for px in range(cx - radius, cx + radius + 1):
                if (px - cx) ** 2 + (py - cy) ** 2 <= r2:
                    if blended:
                        self.blend(px, py, col)
                    else:
                        self.set(px, py, col)

    def ellipse(
        self, cx: int, cy: int, rx: int, ry: int, col: Color, blended: bool = False
    ) -> None:
        rx = max(1, rx)
        ry = max(1, ry)
        rx2, ry2 = rx * rx, ry * ry
        for py in range(cy - ry, cy + ry + 1):
            for px in range(cx - rx, cx + rx + 1):
                if (px - cx) ** 2 * ry2 + (py - cy) ** 2 * rx2 <= rx2 * ry2:
                    if blended:
                        self.blend(px, py, col)
                    else:
                        self.set(px, py, col)

    def line(
        self, x0: int, y0: int, x1: int, y1: int, col: Color, thickness: int = 1
    ) -> None:
        dx = abs(x1 - x0)
        dy = abs(y1 - y0)
        sx = 1 if x0 < x1 else -1
        sy = 1 if y0 < y1 else -1
        err = dx - dy
        x, y = x0, y0
        while True:
            if thickness <= 1:
                self.set(x, y, col)
            else:
                self.circle(x, y, thickness // 2, col)
            if x == x1 and y == y1:
                break
            e2 = 2 * err
            if e2 > -dy:
                err -= dy
                x += sx
            if e2 < dx:
                err += dx
                y += sy


# ---------------------------------------------------------------------------
# Ground tiles (opaque)
# ---------------------------------------------------------------------------

WALL_MORTAR = rgba(40, 40, 48)
WALL_BRICK = rgba(96, 96, 108)
FLOOR_GROUT = rgba(84, 84, 92)
FLOOR_SLAB = rgba(126, 126, 134)
GRASS_BASE = rgba(72, 136, 58)
COBBLE_GROUT = rgba(104, 94, 80)
DIRT_BASE = rgba(138, 106, 72)


def draw_wall(cv: Canvas, ox: int, oy: int, rng: random.Random) -> None:
    """Staggered stone bricks with lit top edges and shaded bottom edges."""
    cv.rect(ox, oy, TILE_PX, TILE_PX, WALL_MORTAR)
    for row in range(4):
        y = oy + row * 8
        shift = 0 if row % 2 == 0 else 8
        for col in range(-1, 3):
            x = ox + col * 16 + shift
            x0 = max(ox, x + 1)
            x1 = min(ox + TILE_PX, x + 16)
            if x1 - x0 < 3:
                continue
            brick = shade(WALL_BRICK, rng.randint(-9, 9))
            cv.rect(x0, y + 1, x1 - x0, 6, brick)
            cv.rect(x0, y + 1, x1 - x0, 1, shade(brick, 24))
            cv.rect(x0, y + 6, x1 - x0, 1, shade(brick, -26))
            for _ in range(4):
                cv.set(
                    rng.randrange(x0, x1),
                    y + 2 + rng.randrange(4),
                    shade(brick, rng.choice([-20, -14, 14, 20])),
                )


def draw_wall_cracked(cv: Canvas, ox: int, oy: int, rng: random.Random) -> None:
    draw_wall(cv, ox, oy, rng)
    crack = rgba(18, 18, 22)
    points = [(21, 1), (18, 7), (22, 12), (19, 18), (23, 24), (20, 31)]
    for (x0, y0), (x1, y1) in zip(points, points[1:]):
        cv.line(ox + x0, oy + y0, ox + x1, oy + y1, crack)
        cv.line(ox + x0 + 1, oy + y0, ox + x1 + 1, oy + y1, rgba(148, 148, 160))
    cv.line(ox + 22, oy + 12, ox + 13, oy + 19, crack)
    cv.line(ox + 23, oy + 24, ox + 29, oy + 21, crack)
    # Chipped hole at the main junction
    cv.circle(ox + 22, oy + 12, 2, crack)
    cv.set(ox + 21, oy + 11, rgba(166, 166, 178))


def draw_wall_mossy(cv: Canvas, ox: int, oy: int, rng: random.Random) -> None:
    draw_wall(cv, ox, oy, rng)
    moss_dark = rgba(48, 92, 46)
    moss_light = rgba(78, 128, 58)
    for _ in range(11):
        cx = ox + rng.randrange(2, 30)
        cy = oy + rng.randrange(16, 31)
        radius = rng.randint(1, 3)
        cv.circle(cx, cy, radius, moss_dark)
        cv.circle(cx - 1, cy - 1, max(1, radius - 1), moss_light)
    # Drips running up the mortar lines
    for x, top in ((9, 11), (24, 14), (17, 18)):
        for y in range(top, 30):
            if rng.random() < 0.65:
                cv.set(ox + x, oy + y, moss_dark if y % 2 == 0 else moss_light)
    for _ in range(6):
        cv.set(
            ox + rng.randrange(1, 31),
            oy + rng.randrange(1, 31),
            shade(moss_light, rng.randint(-16, 16)),
        )


def draw_floor(cv: Canvas, ox: int, oy: int, rng: random.Random) -> None:
    """Dungeon flagstones: 2x2 slabs, lit top edges and a hairline crack."""
    cv.rect(ox, oy, TILE_PX, TILE_PX, FLOOR_GROUT)
    for sy in (0, 16):
        for sx in (0, 16):
            slab = shade(FLOOR_SLAB, rng.randint(-6, 6))
            cv.rect(ox + sx + 1, oy + sy + 1, 14, 14, slab)
            cv.rect(ox + sx + 1, oy + sy + 1, 14, 1, shade(slab, 14))
            cv.rect(ox + sx + 1, oy + sy + 14, 14, 1, shade(slab, -20))
            cv.rect(ox + sx + 14, oy + sy + 1, 1, 14, shade(slab, -10))
            for _ in range(11):
                cv.set(
                    ox + sx + 2 + rng.randrange(12),
                    oy + sy + 2 + rng.randrange(12),
                    shade(slab, rng.choice([-18, -10, 10, 16])),
                )
    cv.line(ox + 10, oy + 3, ox + 13, oy + 9, rgba(104, 104, 112))
    cv.line(ox + 13, oy + 9, ox + 12, oy + 13, rgba(104, 104, 112))


def draw_floor_cracked(cv: Canvas, ox: int, oy: int, rng: random.Random) -> None:
    draw_floor(cv, ox, oy, rng)
    dark = rgba(62, 62, 70)
    light = rgba(158, 158, 166)
    path = [(6, 2), (11, 7), (9, 13), (16, 17), (14, 24), (21, 28), (27, 30)]
    for (x0, y0), (x1, y1) in zip(path, path[1:]):
        cv.line(ox + x0, oy + y0, ox + x1, oy + y1, dark)
        cv.line(ox + x0 + 1, oy + y0, ox + x1 + 1, oy + y1, light)
    cv.line(ox + 16, oy + 17, ox + 24, oy + 14, dark)
    cv.line(ox + 14, oy + 24, ox + 6, oy + 22, dark)
    # Broken-out corner
    cv.circle(ox + 9, oy + 13, 2, dark)
    cv.set(ox + 8, oy + 12, light)


def draw_floor_stained(cv: Canvas, ox: int, oy: int, rng: random.Random) -> None:
    draw_floor(cv, ox, oy, rng)
    cv.ellipse(ox + 21, oy + 12, 7, 5, rgba(98, 104, 92))
    cv.ellipse(ox + 20, oy + 13, 5, 3, rgba(84, 92, 82))
    cv.ellipse(ox + 18, oy + 11, 2, 1, rgba(146, 150, 142))
    cv.set(ox + 25, oy + 8, rgba(70, 78, 70))
    cv.set(ox + 27, oy + 15, rgba(70, 78, 70))


def _grass_field(
    cv: Canvas,
    ox: int,
    oy: int,
    rng: random.Random,
    base: Color,
    blades: int,
    flowers: int = 0,
) -> None:
    cv.rect(ox, oy, TILE_PX, TILE_PX, base)
    for _ in range(90):
        cv.set(
            ox + rng.randrange(TILE_PX),
            oy + rng.randrange(TILE_PX),
            shade(base, rng.randint(-14, 14)),
        )
    for _ in range(5):
        cv.ellipse(
            ox + 4 + rng.randrange(24),
            oy + 4 + rng.randrange(24),
            rng.randint(2, 4),
            rng.randint(1, 2),
            shade(base, -12),
        )
    for _ in range(blades):
        x = ox + 2 + rng.randrange(28)
        y = oy + 6 + rng.randrange(24)
        length = rng.randint(2, 4)
        lean = rng.choice([-1, 0, 0, 1])
        blade = shade(base, rng.choice([-28, -20, 16, 24, 32]))
        cv.line(x, y, x + lean, y - length, blade)
        cv.set(x + lean, y - length, shade(base, 42))
    for _ in range(flowers):
        fx = ox + 4 + rng.randrange(24)
        fy = oy + 5 + rng.randrange(22)
        cv.line(fx, fy + 3, fx, fy, rgba(42, 94, 42))
        petal = rng.choice(
            [rgba(242, 238, 228), rgba(246, 222, 96), rgba(226, 150, 196)]
        )
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            cv.set(fx + dx, fy + dy, petal)
        cv.set(fx, fy, rgba(232, 170, 52))


def draw_grass(cv: Canvas, ox: int, oy: int, rng: random.Random) -> None:
    _grass_field(cv, ox, oy, rng, GRASS_BASE, 42)


def draw_grass_dark(cv: Canvas, ox: int, oy: int, rng: random.Random) -> None:
    base = rgba(54, 110, 48)
    _grass_field(cv, ox, oy, rng, base, 52)
    for _ in range(3):
        px = ox + 4 + rng.randrange(24)
        py = oy + 4 + rng.randrange(24)
        cv.ellipse(px, py, 2, 1, rgba(112, 110, 104))
        cv.set(px - 1, py - 1, rgba(148, 146, 138))
    for _ in range(4):
        cv.set(
            ox + rng.randrange(TILE_PX),
            oy + rng.randrange(TILE_PX),
            rgba(96, 76, 48),
        )


def draw_grass_flowers(cv: Canvas, ox: int, oy: int, rng: random.Random) -> None:
    _grass_field(cv, ox, oy, rng, GRASS_BASE, 38, flowers=7)


def draw_fallback(cv: Canvas, ox: int, oy: int, rng: random.Random) -> None:
    for y in range(4):
        for x in range(4):
            col = rgba(255, 0, 255) if (x + y) % 2 == 0 else rgba(20, 20, 20)
            cv.rect(ox + x * 8, oy + y * 8, 8, 8, col)


def _cobble(cv: Canvas, x: int, y: int, w: int, h: int, col: Color, rng: random.Random) -> None:
    """One packed cobblestone with a lit top-left and a shaded bottom-right."""
    cv.rect(x + 1, y, w - 2, h, col)
    cv.rect(x, y + 1, w, h - 2, col)
    cv.rect(x + 1, y, w - 2, 1, shade(col, 22))
    cv.rect(x, y + 1, 1, h - 2, shade(col, 16))
    cv.rect(x + 1, y + h - 1, w - 2, 1, shade(col, -28))
    cv.rect(x + w - 1, y + 1, 1, h - 2, shade(col, -20))
    for _ in range(2):
        cv.set(
            x + 2 + rng.randrange(max(1, w - 4)),
            y + 2 + rng.randrange(max(1, h - 4)),
            shade(col, rng.choice([-16, 12])),
        )


def _cobble_field(
    cv: Canvas, ox: int, oy: int, rng: random.Random, base: Color, weed: bool, puddle: bool
) -> None:
    cv.rect(ox, oy, TILE_PX, TILE_PX, COBBLE_GROUT)
    row_height = 8
    for row in range(4):
        y = oy + row * row_height
        x = ox
        while x < ox + TILE_PX - 3:
            remaining = ox + TILE_PX - x
            width = rng.choice([6, 7, 8, 9, 10, 11])
            if remaining - width <= 1:
                width = remaining - 1
                if width < 4:
                    break
                _cobble(cv, x, y, width, row_height - 1, shade(base, rng.randint(-10, 10)), rng)
                break
            _cobble(cv, x, y, width, row_height - 1, shade(base, rng.randint(-10, 10)), rng)
            x += width + 1
    if weed:
        wx, wy = ox + rng.randrange(4, 28), oy + rng.randrange(4, 28)
        for dx, dy in ((0, 0), (-1, -2), (1, -3), (2, -1), (-2, -1), (0, -4)):
            cv.set(wx + dx, wy + dy, rgba(70, 132, 58))
        cv.set(wx, wy - 4, rgba(104, 168, 76))
    if puddle:
        px, py = ox + 19, oy + 21
        cv.ellipse(px, py, 5, 3, rgba(76, 104, 128))
        cv.ellipse(px - 1, py - 1, 3, 1, rgba(128, 166, 194))
        cv.set(px - 2, py - 1, rgba(176, 204, 224))


def draw_town_cobble(cv: Canvas, ox: int, oy: int, rng: random.Random) -> None:
    _cobble_field(cv, ox, oy, rng, rgba(176, 160, 134), weed=False, puddle=False)


def draw_town_cobble_b(cv: Canvas, ox: int, oy: int, rng: random.Random) -> None:
    _cobble_field(cv, ox, oy, rng, rgba(164, 160, 150), weed=True, puddle=False)


def draw_town_cobble_c(cv: Canvas, ox: int, oy: int, rng: random.Random) -> None:
    _cobble_field(cv, ox, oy, rng, rgba(184, 166, 138), weed=False, puddle=True)


def draw_dirt_path(cv: Canvas, ox: int, oy: int, rng: random.Random) -> None:
    """Packed earth path: mottled brown, pebbles and faint wheel ruts."""
    cv.rect(ox, oy, TILE_PX, TILE_PX, DIRT_BASE)
    for _ in range(140):
        cv.set(
            ox + rng.randrange(TILE_PX),
            oy + rng.randrange(TILE_PX),
            shade(DIRT_BASE, rng.randint(-16, 16)),
        )
    for _ in range(7):
        cv.ellipse(
            ox + 3 + rng.randrange(26),
            oy + 3 + rng.randrange(26),
            rng.randint(2, 5),
            rng.randint(1, 3),
            shade(DIRT_BASE, rng.choice([-14, -10, 10, 14])),
        )
    for _ in range(13):
        px = ox + 2 + rng.randrange(28)
        py = oy + 2 + rng.randrange(28)
        stone = shade(rgba(150, 144, 132), rng.randint(-14, 14))
        cv.set(px, py, stone)
        if rng.random() < 0.6:
            cv.set(px + 1, py, shade(stone, -10))
        cv.set(px, py + 1, shade(stone, -24))
    for y in (11, 22):
        for x in range(ox + 4, ox + 28, 3):
            cv.set(x, oy + y + rng.choice([0, 0, 1]), shade(DIRT_BASE, -18))


# ---------------------------------------------------------------------------
# Decor (transparent background; drawn on the ZoneView decor layer)
# ---------------------------------------------------------------------------


def draw_decor_grass_tuft(cv: Canvas, ox: int, oy: int, rng: random.Random) -> None:
    dark = rgba(44, 104, 44)
    mid = rgba(70, 142, 62)
    light = rgba(108, 178, 80)
    for base_x, base_y in ((11, 30), (21, 29)):
        for i in range(-4, 5):
            start_x = ox + base_x + i
            end_x = ox + base_x + i * 2
            end_y = oy + base_y - 8 - (4 - abs(i)) * 2
            cv.line(start_x, oy + base_y, end_x, end_y, dark if i % 2 else mid)
            cv.set(end_x, end_y, light)
            cv.set(end_x, end_y + 2, mid)
    for i in range(5):
        cv.set(ox + 14 + i, oy + 23 - i, mid)
        cv.set(ox + 16 - i, oy + 25 - i, dark)


def draw_decor_house(cv: Canvas, ox: int, oy: int, rng: random.Random) -> None:
    """A complete little house: roof, chimney, plaster wall, door and lit window."""
    roof_dark = rgba(104, 44, 36)
    roof_mid = rgba(150, 66, 52)
    roof_light = rgba(186, 92, 70)
    plaster = rgba(226, 208, 170)
    plaster_shadow = rgba(198, 178, 142)
    timber = rgba(100, 66, 38)
    timber_dark = rgba(72, 46, 26)

    # Chimney (drawn first so the roof covers its base)
    cv.rect(ox + 21, oy + 2, 5, 7, rgba(150, 84, 64))
    cv.rect(ox + 21, oy + 2, 1, 7, rgba(178, 108, 82))
    cv.rect(ox + 20, oy + 1, 7, 2, rgba(90, 88, 90))
    cv.set(ox + 22, oy + 4, rgba(110, 60, 44))
    cv.set(ox + 24, oy + 6, rgba(110, 60, 44))

    # Roof: widening trapezoid with shingle rows
    roof_rows = [
        (5, 11, 20),
        (6, 10, 21),
        (7, 9, 22),
        (8, 8, 23),
        (9, 7, 24),
        (10, 6, 25),
        (11, 5, 26),
        (12, 4, 27),
        (13, 3, 28),
        (14, 2, 29),
    ]
    for i, (y, x0, x1) in enumerate(roof_rows):
        col = roof_mid if i % 2 == 0 else shade(roof_mid, -6)
        cv.rect(ox + x0, oy + y, x1 - x0 + 1, 1, col)
        cv.set(ox + x0, oy + y, roof_light)
        cv.set(ox + x1, oy + y, roof_dark)
        if i in (3, 6, 9):
            for x in range(x0 + 1, x1, 4):
                cv.set(ox + x, oy + y, roof_dark)
    cv.rect(ox + 11, oy + 5, 10, 1, roof_light)
    cv.rect(ox + 2, oy + 14, 28, 1, roof_dark)
    cv.rect(ox + 3, oy + 15, 26, 1, rgba(72, 38, 28))

    # Wall with timber frame
    cv.rect(ox + 5, oy + 16, 23, 15, plaster)
    cv.rect(ox + 5, oy + 28, 23, 3, plaster_shadow)
    cv.rect(ox + 5, oy + 16, 2, 15, timber)
    cv.rect(ox + 26, oy + 16, 2, 15, timber)
    cv.rect(ox + 5, oy + 16, 23, 2, timber)
    cv.rect(ox + 5, oy + 29, 23, 2, timber_dark)
    cv.set(ox + 7, oy + 20, shade(plaster, -10))
    cv.set(ox + 25, oy + 22, shade(plaster, -10))
    cv.set(ox + 9, oy + 27, shade(plaster, -10))

    # Window with warm light and cross frame
    cv.rect(ox + 7, oy + 18, 7, 7, timber_dark)
    cv.rect(ox + 8, oy + 19, 5, 5, rgba(250, 214, 120))
    cv.set(ox + 9, oy + 20, rgba(255, 244, 190))
    cv.rect(ox + 10, oy + 19, 1, 5, timber_dark)
    cv.rect(ox + 8, oy + 21, 5, 1, timber_dark)
    cv.rect(ox + 7, oy + 25, 7, 1, timber)

    # Door with frame, planks, knob and a stone step
    cv.rect(ox + 13, oy + 20, 8, 11, timber_dark)
    cv.rect(ox + 14, oy + 21, 6, 10, rgba(112, 70, 38))
    cv.rect(ox + 16, oy + 22, 1, 8, rgba(88, 54, 30))
    cv.rect(ox + 18, oy + 22, 1, 8, rgba(88, 54, 30))
    cv.set(ox + 19, oy + 25, rgba(226, 186, 80))
    cv.rect(ox + 12, oy + 30, 11, 1, rgba(146, 140, 128))


# ---------------------------------------------------------------------------
# House parts (JGT-123): 32 px cells assembled into 5x4 / 4x3 houses.
# Two palettes: "a" warm red roof with cream plaster, "b" slate roof with sage
# plaster. Every cell keeps its four corner pixels transparent (atlas contract).
# ---------------------------------------------------------------------------

HOUSE_PALETTES = {
    "a": {
        "roof_dark": rgba(92, 38, 32),
        "roof_mid": rgba(142, 62, 48),
        "roof_light": rgba(184, 92, 70),
        "ridge": rgba(206, 120, 84),
        "wall": rgba(228, 210, 172),
        "wall_shadow": rgba(198, 178, 142),
        "timber": rgba(106, 70, 40),
        "timber_dark": rgba(72, 46, 26),
    },
    "b": {
        "roof_dark": rgba(38, 50, 72),
        "roof_mid": rgba(62, 82, 112),
        "roof_light": rgba(98, 124, 158),
        "ridge": rgba(128, 150, 182),
        "wall": rgba(212, 212, 196),
        "wall_shadow": rgba(180, 180, 164),
        "timber": rgba(94, 76, 54),
        "timber_dark": rgba(62, 48, 34),
    },
}

HOUSE_GLASS = rgba(250, 216, 128)
HOUSE_GLASS_LIGHT = rgba(255, 240, 186)
HOUSE_GLOW = rgba(238, 180, 94)


def _house_clear_corners(cv: Canvas, ox: int, oy: int) -> None:
    """Decor cells must keep their four corner pixels transparent."""
    for cx, cy in ((0, 0), (TILE_PX - 1, 0), (0, TILE_PX - 1), (TILE_PX - 1, TILE_PX - 1)):
        cv.set(ox + cx, oy + cy, rgba(0, 0, 0, 0))


def _house_bargeboard(cv: Canvas, ox: int, oy: int, pal: dict, edge: str, top: int, height: int) -> None:
    """Timber board along the left/right end of a roof row."""
    if edge == "l":
        cv.rect(ox, oy + top, 3, height, pal["timber"])
        cv.rect(ox, oy + top, 1, height, shade(pal["timber"], 26))
        cv.rect(ox + 3, oy + top, 1, height, pal["timber_dark"])
    elif edge == "r":
        cv.rect(ox + 29, oy + top, 3, height, pal["timber"])
        cv.rect(ox + 29, oy + top, 1, height, shade(pal["timber"], 18))
        cv.rect(ox + 31, oy + top, 1, height, pal["timber_dark"])


def _house_wall_base(cv: Canvas, ox: int, oy: int, pal: dict, rng: random.Random) -> None:
    """Plaster wall with a timber frame; used by the wall, window and door cells."""
    wall = pal["wall"]
    cv.rect(ox, oy, TILE_PX, TILE_PX, wall)
    cv.rect(ox, oy + 28, TILE_PX, 4, pal["wall_shadow"])
    for _ in range(6):
        cv.set(
            ox + 3 + rng.randrange(26),
            oy + 6 + rng.randrange(19),
            shade(wall, rng.choice([-10, -6, 8, 12])),
        )
    cv.rect(ox, oy, 2, TILE_PX, pal["timber"])
    cv.rect(ox, oy, 1, TILE_PX, shade(pal["timber"], 22))
    cv.rect(ox + 30, oy, 2, TILE_PX, pal["timber_dark"])
    cv.rect(ox, oy, TILE_PX, 2, pal["timber"])
    cv.rect(ox, oy + 2, TILE_PX, 1, pal["timber_dark"])
    cv.rect(ox, oy + 29, TILE_PX, 3, pal["timber_dark"])
    cv.rect(ox, oy + 29, TILE_PX, 1, shade(pal["timber"], -8))


def draw_house_ridge(cv: Canvas, ox: int, oy: int, rng: random.Random, palette: dict, edge: str) -> None:
    """Top roof row: ridge cap, staggered shingles and a bargeboard at the ends."""
    pal = palette
    roof = pal["roof_mid"]
    cv.rect(ox, oy + 8, TILE_PX, 24, roof)
    cv.rect(ox, oy + 8, TILE_PX, 3, pal["ridge"])
    cv.rect(ox, oy + 8, TILE_PX, 1, shade(pal["ridge"], 30))
    cv.rect(ox, oy + 11, TILE_PX, 1, shade(pal["ridge"], -28))
    for row in range(4):
        y = oy + 13 + row * 4
        col = roof if row % 2 == 0 else shade(roof, -8)
        cv.rect(ox, y, TILE_PX, 4, col)
        cv.rect(ox, y, TILE_PX, 1, shade(col, 10))
        offset = 4 if row % 2 else 0
        for x in range(offset, TILE_PX, 8):
            cv.rect(ox + x, y + 1, 1, 3, pal["roof_dark"])
    cv.rect(ox, oy + 29, TILE_PX, 1, pal["roof_dark"])
    _house_bargeboard(cv, ox, oy, pal, edge, 8, 24)
    _house_clear_corners(cv, ox, oy)


def draw_house_roof(cv: Canvas, ox: int, oy: int, rng: random.Random, palette: dict, edge: str) -> None:
    """Lower roof row: shingles running into the eave board and its wall shadow."""
    pal = palette
    roof = pal["roof_mid"]
    cv.rect(ox, oy, TILE_PX, 22, roof)
    for row in range(6):
        y = oy + row * 4
        col = roof if row % 2 == 0 else shade(roof, -8)
        cv.rect(ox, y, TILE_PX, 4, col)
        cv.rect(ox, y, TILE_PX, 1, shade(col, 10))
        offset = 4 if row % 2 else 0
        for x in range(offset, TILE_PX, 8):
            cv.rect(ox + x, y + 1, 1, 3, pal["roof_dark"])
    cv.rect(ox, oy + 20, TILE_PX, 3, pal["roof_light"])
    cv.rect(ox, oy + 20, TILE_PX, 1, shade(pal["roof_light"], 26))
    cv.rect(ox, oy + 23, TILE_PX, 2, pal["roof_dark"])
    cv.rect(ox, oy + 25, TILE_PX, 7, rgba(52, 38, 30, 120))
    _house_bargeboard(cv, ox, oy, pal, edge, 0, 25)
    _house_clear_corners(cv, ox, oy)


def draw_house_wall(cv: Canvas, ox: int, oy: int, rng: random.Random, palette: dict) -> None:
    _house_wall_base(cv, ox, oy, palette, rng)
    _house_clear_corners(cv, ox, oy)


def draw_house_window(cv: Canvas, ox: int, oy: int, rng: random.Random, palette: dict) -> None:
    """Lit window with a cross frame and a flower box under the sill."""
    pal = palette
    _house_wall_base(cv, ox, oy, pal, rng)
    frame = pal["timber_dark"]
    cv.rect(ox + 8, oy + 7, 17, 17, frame)
    cv.rect(ox + 9, oy + 8, 15, 15, HOUSE_GLASS)
    cv.rect(ox + 9, oy + 8, 15, 5, HOUSE_GLASS_LIGHT)
    cv.rect(ox + 15, oy + 8, 2, 15, frame)
    cv.rect(ox + 9, oy + 15, 15, 2, frame)
    cv.rect(ox + 7, oy + 23, 19, 2, pal["timber"])
    cv.rect(ox + 7, oy + 25, 19, 1, pal["timber_dark"])
    cv.rect(ox + 8, oy + 25, 17, 2, rgba(112, 70, 40))
    for i in range(5):
        fx = ox + 10 + i * 3
        cv.set(fx, oy + 24, rgba(84, 144, 66))
        cv.set(fx, oy + 23, rng.choice([rgba(230, 92, 92), rgba(244, 204, 88), rgba(232, 150, 196)]))
    _house_clear_corners(cv, ox, oy)


def draw_house_door(cv: Canvas, ox: int, oy: int, rng: random.Random, palette: dict) -> None:
    """Open doorway with a warm-lit interior and a stone threshold (walkable)."""
    pal = palette
    _house_wall_base(cv, ox, oy, pal, rng)
    frame = pal["timber_dark"]
    cv.rect(ox + 9, oy + 6, 14, 25, frame)
    cv.rect(ox + 10, oy + 7, 12, 24, HOUSE_GLOW)
    cv.rect(ox + 10, oy + 7, 12, 5, HOUSE_GLASS_LIGHT)
    # Door leaf swung to the left, planks and knob.
    cv.rect(ox + 10, oy + 7, 3, 24, rgba(120, 76, 40))
    cv.rect(ox + 12, oy + 7, 1, 24, rgba(88, 54, 30))
    cv.rect(ox + 15, oy + 7, 1, 24, rgba(88, 54, 30))
    cv.set(ox + 18, oy + 18, rgba(232, 190, 82))
    cv.rect(ox + 7, oy + 29, 19, 3, rgba(148, 142, 130))
    cv.rect(ox + 7, oy + 29, 19, 1, rgba(180, 174, 160))
    _house_clear_corners(cv, ox, oy)


def draw_decor_fountain(cv: Canvas, ox: int, oy: int, rng: random.Random) -> None:
    cx, cy = ox + 16, oy + 16
    cv.ellipse(cx + 1, cy + 2, 14, 13, rgba(60, 60, 68, 90), blended=True)
    cv.circle(cx, cy, 13, rgba(96, 96, 104))
    cv.circle(cx, cy, 12, rgba(150, 150, 158))
    cv.circle(cx - 1, cy - 1, 11, rgba(178, 178, 186))
    cv.circle(cx, cy, 10, rgba(48, 96, 168))
    cv.circle(cx, cy, 7, rgba(62, 118, 192))
    cv.circle(cx, cy, 6, rgba(48, 96, 168))
    cv.circle(cx, cy, 4, rgba(72, 130, 202))
    cv.circle(cx, cy, 3, rgba(166, 166, 174))
    cv.circle(cx - 1, cy - 1, 2, rgba(206, 206, 212))
    cv.circle(cx, cy, 1, rgba(210, 236, 255))
    for ang in range(0, 360, 45):
        rad = math.radians(ang)
        px = cx + int(round(math.cos(rad) * 6))
        py = cy + int(round(math.sin(rad) * 6))
        cv.set(px, py, rgba(180, 220, 250))
    for _ in range(6):
        cv.set(
            cx + rng.randint(-8, 8),
            cy + rng.randint(-8, 8),
            rgba(120, 176, 226),
        )
    cv.set(cx - 5, cy + 3, rgba(34, 74, 136))
    cv.set(cx + 4, cy - 4, rgba(34, 74, 136))


def draw_decor_torch(cv: Canvas, ox: int, oy: int, rng: random.Random) -> None:
    # Warm halo
    cv.circle(ox + 16, oy + 10, 8, rgba(255, 172, 72, 52), blended=True)
    # Iron bracket and rivets
    cv.rect(ox + 11, oy + 24, 11, 4, rgba(52, 50, 52))
    cv.rect(ox + 11, oy + 24, 11, 1, rgba(92, 90, 92))
    cv.set(ox + 12, oy + 25, rgba(160, 158, 152))
    cv.set(ox + 20, oy + 25, rgba(160, 158, 152))
    # Wooden handle with iron bands
    cv.rect(ox + 15, oy + 13, 3, 15, rgba(112, 74, 40))
    cv.rect(ox + 15, oy + 13, 1, 15, rgba(148, 102, 56))
    cv.rect(ox + 17, oy + 13, 1, 15, rgba(84, 54, 30))
    cv.rect(ox + 14, oy + 17, 5, 2, rgba(58, 54, 52))
    cv.rect(ox + 14, oy + 23, 5, 2, rgba(58, 54, 52))
    # Flame: outer, middle, core and a flickering tip
    cv.circle(ox + 16, oy + 10, 5, rgba(216, 84, 32, 235))
    cv.circle(ox + 16, oy + 10, 4, rgba(240, 132, 42))
    cv.circle(ox + 16, oy + 11, 3, rgba(252, 200, 84))
    cv.circle(ox + 16, oy + 12, 1, rgba(255, 244, 190))
    cv.set(ox + 16, oy + 5, rgba(232, 112, 36))
    cv.set(ox + 16, oy + 4, rgba(240, 150, 50, 210))
    cv.set(ox + 13, oy + 9, rgba(232, 112, 36))
    cv.set(ox + 19, oy + 8, rgba(232, 112, 36))
    for px, py in ((12, 6), (20, 7), (17, 2)):
        cv.set(ox + px, oy + py, rgba(250, 190, 90, 200))


def draw_decor_bones(cv: Canvas, ox: int, oy: int, rng: random.Random) -> None:
    bone = rgba(230, 224, 202)
    bone_shadow = rgba(158, 152, 136)
    dark = rgba(58, 52, 46)
    cv.ellipse(ox + 16, oy + 25, 12, 4, rgba(52, 48, 42, 70), blended=True)

    for x0, y0, x1, y1 in ((7, 24, 23, 14), (8, 14, 22, 25)):
        cv.line(ox + x0, oy + y0, ox + x1, oy + y1, bone_shadow, thickness=4)
        cv.line(ox + x0, oy + y0, ox + x1, oy + y1, bone, thickness=2)
        for px, py in ((x0, y0), (x1, y1)):
            cv.circle(ox + px, oy + py, 2, bone_shadow, blended=False)
            cv.circle(ox + px, oy + py, 1, bone)

    # Skull
    cv.circle(ox + 23, oy + 8, 5, bone_shadow)
    cv.circle(ox + 23, oy + 8, 4, bone)
    cv.rect(ox + 21, oy + 11, 5, 3, bone_shadow)
    cv.rect(ox + 21, oy + 11, 5, 2, bone)
    cv.circle(ox + 21, oy + 7, 1, dark)
    cv.circle(ox + 25, oy + 7, 1, dark)
    cv.set(ox + 23, oy + 9, dark)
    for x in (21, 23, 25):
        cv.set(ox + x, oy + 12, bone_shadow)
    cv.set(ox + 20, oy + 4, rgba(255, 250, 236))


def draw_decor_crate(cv: Canvas, ox: int, oy: int, rng: random.Random) -> None:
    wood = rgba(146, 100, 54)
    wood_light = rgba(178, 128, 72)
    frame = rgba(94, 60, 30)
    nail = rgba(196, 192, 180)
    cv.ellipse(ox + 16, oy + 27, 12, 4, rgba(52, 48, 42, 70), blended=True)

    # Top face (seen slightly from above)
    for i, y in enumerate(range(4, 9)):
        half = 7 + i
        cv.rect(ox + 16 - half, oy + y, half * 2 + 1, 1, shade(wood_light, 6 - i * 3))
    for x in (12, 17, 22):
        cv.set(ox + x, oy + 5, frame)
        cv.set(ox + x, oy + 6, frame)

    # Front face
    cv.rect(ox + 6, oy + 8, 21, 21, wood)
    for x in range(8, 27, 6):
        cv.rect(ox + x, oy + 9, 1, 19, shade(wood, -14))
    cv.rect(ox + 6, oy + 8, 21, 2, frame)
    cv.rect(ox + 6, oy + 27, 21, 2, frame)
    cv.rect(ox + 6, oy + 8, 2, 21, frame)
    cv.rect(ox + 25, oy + 8, 2, 21, frame)
    cv.line(ox + 8, oy + 26, ox + 24, oy + 10, shade(wood, -18), thickness=3)
    cv.line(ox + 8, oy + 26, ox + 24, oy + 10, shade(wood_light, 12))
    for px, py in ((8, 10), (24, 10), (8, 26), (24, 26)):
        cv.set(ox + px, oy + py, nail)
    for _ in range(7):
        cv.set(
            ox + 9 + rng.randrange(15),
            oy + 11 + rng.randrange(15),
            shade(wood, rng.choice([-10, 8])),
        )


def draw_decor_barrel(cv: Canvas, ox: int, oy: int, rng: random.Random) -> None:
    body = rgba(140, 94, 52)
    body_light = rgba(172, 122, 72)
    body_dark = rgba(100, 64, 36)
    iron = rgba(58, 54, 52)
    iron_light = rgba(96, 92, 88)
    cv.ellipse(ox + 17, oy + 28, 10, 3, rgba(52, 48, 42, 80), blended=True)

    for y in range(8, 29):
        t = (y - 18) / 10.0
        half = max(7, int(round(10 * math.sqrt(max(0.0, 1.0 - t * t)))))
        cv.rect(ox + 16 - half, oy + y, half * 2 + 1, 1, body)
        cv.rect(ox + 16 - half, oy + y, max(1, half // 2), 1, body_light)
        cv.rect(ox + 14 + half // 2, oy + y, half - half // 2 + 1, 1, body_dark)
    for x in (12, 16, 20):
        cv.line(ox + x, oy + 9, ox + x, oy + 27, shade(body_dark, -4))
    for y in (13, 23):
        half = max(7, int(round(10 * math.sqrt(max(0.0, 1.0 - ((y - 18) / 10.0) ** 2)))))
        cv.rect(ox + 16 - half, oy + y, half * 2 + 1, 2, iron)
        cv.rect(ox + 16 - half, oy + y, half * 2 + 1, 1, iron_light)
    # Lid
    cv.ellipse(ox + 16, oy + 8, 8, 3, rgba(66, 44, 24))
    cv.ellipse(ox + 16, oy + 8, 7, 2, rgba(164, 116, 66))
    cv.ellipse(ox + 16, oy + 8, 4, 1, rgba(140, 96, 52))
    cv.set(ox + 16, oy + 8, rgba(80, 50, 28))
    cv.set(ox + 13, oy + 7, rgba(196, 148, 92))


def draw_decor_rubble(cv: Canvas, ox: int, oy: int, rng: random.Random) -> None:
    cv.ellipse(ox + 16, oy + 26, 12, 4, rgba(52, 48, 42, 70), blended=True)
    chunks = [
        (10, 24, 4, rgba(110, 106, 100)),
        (16, 26, 5, rgba(124, 120, 112)),
        (23, 24, 3, rgba(96, 92, 88)),
        (13, 19, 3, rgba(132, 128, 120)),
        (20, 18, 4, rgba(116, 112, 104)),
        (7, 20, 2, rgba(90, 86, 82)),
        (25, 20, 2, rgba(136, 132, 124)),
        (17, 14, 3, rgba(120, 116, 108)),
    ]
    for cx, cy, radius, col in chunks:
        cv.circle(ox + cx, oy + cy, radius + 1, rgba(56, 54, 52))
        cv.circle(ox + cx, oy + cy, radius, shade(col, rng.randint(-6, 6)))
        cv.circle(ox + cx - 1, oy + cy - 1, max(1, radius - 2), shade(col, 22))
        cv.set(ox + cx + radius - 1, oy + cy + radius - 1, shade(col, -26))
    cv.line(ox + 15, oy + 24, ox + 18, oy + 21, rgba(66, 62, 60))
    cv.set(ox + 21, oy + 16, rgba(88, 84, 80))
    for px, py in ((5, 27), (28, 27), (14, 10), (26, 15)):
        cv.set(ox + px, oy + py, rgba(138, 132, 122, 180))


def draw_decor_tree(cv: Canvas, ox: int, oy: int, rng: random.Random) -> None:
    """Round canopy with a shaded trunk; reads as a tree from the top-down camera."""
    trunk = rgba(96, 64, 38)
    trunk_light = rgba(132, 92, 54)
    trunk_dark = rgba(68, 44, 26)
    leaf_dark = rgba(30, 76, 42)
    leaf_mid = rgba(44, 104, 48)
    leaf = rgba(58, 128, 58)
    leaf_light = rgba(82, 156, 68)
    leaf_hi = rgba(112, 182, 84)

    cv.ellipse(ox + 17, oy + 25, 11, 4, rgba(28, 52, 30, 90), blended=True)
    # Trunk and roots
    cv.rect(ox + 14, oy + 17, 5, 12, trunk)
    cv.rect(ox + 14, oy + 17, 1, 12, trunk_light)
    cv.rect(ox + 18, oy + 17, 1, 12, trunk_dark)
    cv.set(ox + 13, oy + 28, trunk_dark)
    cv.set(ox + 19, oy + 28, trunk_dark)
    cv.set(ox + 12, oy + 29, trunk)
    cv.set(ox + 20, oy + 29, trunk)
    # Canopy layers with leaf clumps breaking the silhouette
    cv.circle(ox + 16, oy + 13, 12, leaf_dark)
    for ang in range(0, 360, 60):
        rad = math.radians(ang)
        cv.circle(
            ox + 16 + int(round(math.cos(rad) * 9)),
            oy + 13 + int(round(math.sin(rad) * 9)),
            3,
            leaf_dark,
        )
    cv.circle(ox + 16, oy + 13, 10, leaf_mid)
    cv.circle(ox + 15, oy + 12, 8, leaf)
    cv.circle(ox + 13, oy + 10, 5, leaf_light)
    for _ in range(14):
        ang = rng.uniform(0, math.tau)
        radius = rng.uniform(2, 9)
        px = ox + 16 + int(round(math.cos(ang) * radius))
        py = oy + 13 + int(round(math.sin(ang) * radius))
        cv.set(px, py, rng.choice([leaf_light, leaf_hi, leaf_mid]))
    for _ in range(6):
        ang = rng.uniform(0, math.tau)
        radius = rng.uniform(10, 12)
        px = ox + 16 + int(round(math.cos(ang) * radius))
        py = oy + 13 + int(round(math.sin(ang) * radius))
        cv.set(px, py, leaf_dark)
    cv.set(ox + 11, oy + 8, leaf_hi)
    cv.set(ox + 12, oy + 7, leaf_hi)
    cv.set(ox + 10, oy + 10, leaf_hi)


def draw_decor_rock(cv: Canvas, ox: int, oy: int, rng: random.Random) -> None:
    """Mossy boulder with a lit top-left facet and a small companion stone."""
    cv.ellipse(ox + 16, oy + 27, 11, 3, rgba(52, 50, 46, 90), blended=True)
    cv.circle(ox + 15, oy + 19, 12, rgba(58, 58, 64))
    cv.circle(ox + 15, oy + 19, 11, rgba(112, 110, 106))
    cv.circle(ox + 13, oy + 17, 8, rgba(134, 132, 126))
    cv.circle(ox + 10, oy + 14, 4, rgba(156, 154, 146))
    for _ in range(10):
        cv.set(
            ox + 7 + rng.randrange(16),
            oy + 10 + rng.randrange(16),
            shade(rgba(120, 118, 112), rng.randint(-18, 20)),
        )
    cv.line(ox + 19, oy + 12, ox + 17, oy + 20, rgba(78, 76, 74))
    cv.line(ox + 17, oy + 20, ox + 20, oy + 25, rgba(78, 76, 74))
    cv.circle(ox + 20, oy + 12, 2, rgba(66, 108, 54))
    cv.set(ox + 21, oy + 11, rgba(88, 134, 62))
    # Companion stone
    cv.circle(ox + 26, oy + 25, 3, rgba(70, 68, 64))
    cv.circle(ox + 26, oy + 25, 2, rgba(126, 122, 116))
    cv.set(ox + 25, oy + 24, rgba(156, 152, 144))


def draw_gate_floor(cv: Canvas, ox: int, oy: int, rng: random.Random) -> None:
    """Boss gate threshold: dark flagstones with a worn rust-red runner."""
    cv.rect(ox, oy, TILE_PX, TILE_PX, rgba(44, 38, 40))
    for sy in (0, 16):
        for sx in (0, 16):
            slab = shade(rgba(78, 66, 66), rng.randint(-5, 5))
            cv.rect(ox + sx + 1, oy + sy + 1, 14, 14, slab)
            cv.rect(ox + sx + 1, oy + sy + 1, 14, 1, shade(slab, 12))
            cv.rect(ox + sx + 1, oy + sy + 14, 14, 1, shade(slab, -16))
    # Worn runner stripe down the middle of the passage.
    cv.rect(ox + 10, oy, 12, TILE_PX, rgba(112, 40, 38))
    cv.rect(ox + 10, oy, 1, TILE_PX, rgba(150, 62, 52))
    cv.rect(ox + 21, oy, 1, TILE_PX, rgba(74, 24, 26))
    for _ in range(14):
        cv.set(ox + 11 + rng.randrange(10), oy + rng.randrange(TILE_PX), rgba(90, 30, 30))


def draw_gate_post(cv: Canvas, ox: int, oy: int, rng: random.Random) -> None:
    """Gate frame pillar: massive dark stone with bronze bands."""
    cv.rect(ox, oy, TILE_PX, TILE_PX, rgba(30, 28, 34))
    cv.rect(ox + 3, oy, 26, TILE_PX, rgba(70, 68, 80))
    cv.rect(ox + 3, oy, 3, TILE_PX, rgba(96, 94, 108))
    cv.rect(ox + 26, oy, 3, TILE_PX, rgba(46, 44, 54))
    for by in range(0, TILE_PX, 8):
        cv.rect(ox + 3, oy + by + 7, 26, 1, rgba(40, 38, 46))
        for _ in range(6):
            cv.set(ox + 7 + rng.randrange(18), oy + by + rng.randrange(7), shade(rgba(70, 68, 80), rng.randint(-14, 10)))
    for by in (4, 24):
        cv.rect(ox + 1, oy + by, 30, 4, rgba(150, 110, 52))
        cv.rect(ox + 1, oy + by, 30, 1, rgba(206, 164, 86))
        cv.rect(ox + 1, oy + by + 3, 30, 1, rgba(96, 66, 30))


# (col, row) -> drawer. The layout is mirrored in data/tilesets/floor1.json.
TILE_DRAWERS = {
    (0, 0): draw_wall,
    (1, 0): draw_floor,
    (2, 0): draw_grass,
    (3, 0): draw_fallback,
    (4, 0): draw_wall_cracked,
    (5, 0): draw_wall_mossy,
    (6, 0): draw_floor_cracked,
    (7, 0): draw_floor_stained,
    (0, 1): draw_grass_dark,
    (1, 1): draw_grass_flowers,
    (2, 1): draw_town_cobble,
    (3, 1): draw_town_cobble_b,
    (4, 1): draw_town_cobble_c,
    (5, 1): draw_dirt_path,
    (6, 1): draw_decor_tree,
    (7, 1): draw_decor_rock,
    (0, 2): draw_decor_grass_tuft,
    (1, 2): draw_decor_house,
    (2, 2): draw_decor_fountain,
    (3, 2): draw_decor_torch,
    (4, 2): draw_decor_bones,
    (5, 2): draw_decor_crate,
    (6, 2): draw_decor_barrel,
    (7, 2): draw_decor_rubble,
    (0, 3): draw_gate_floor,
    (1, 3): draw_gate_post,
    # House parts (JGT-123), layout mirrored in data/tilesets/floor1.json.
    (0, 4): partial(draw_house_ridge, palette=HOUSE_PALETTES["a"], edge="l"),
    (1, 4): partial(draw_house_ridge, palette=HOUSE_PALETTES["a"], edge="m"),
    (2, 4): partial(draw_house_ridge, palette=HOUSE_PALETTES["a"], edge="r"),
    (3, 4): partial(draw_house_roof, palette=HOUSE_PALETTES["a"], edge="l"),
    (4, 4): partial(draw_house_roof, palette=HOUSE_PALETTES["a"], edge="m"),
    (5, 4): partial(draw_house_roof, palette=HOUSE_PALETTES["a"], edge="r"),
    (6, 4): partial(draw_house_wall, palette=HOUSE_PALETTES["a"]),
    (7, 4): partial(draw_house_window, palette=HOUSE_PALETTES["a"]),
    (0, 5): partial(draw_house_door, palette=HOUSE_PALETTES["a"]),
    (1, 5): partial(draw_house_ridge, palette=HOUSE_PALETTES["b"], edge="l"),
    (2, 5): partial(draw_house_ridge, palette=HOUSE_PALETTES["b"], edge="m"),
    (3, 5): partial(draw_house_ridge, palette=HOUSE_PALETTES["b"], edge="r"),
    (4, 5): partial(draw_house_roof, palette=HOUSE_PALETTES["b"], edge="l"),
    (5, 5): partial(draw_house_roof, palette=HOUSE_PALETTES["b"], edge="m"),
    (6, 5): partial(draw_house_roof, palette=HOUSE_PALETTES["b"], edge="r"),
    (7, 5): partial(draw_house_wall, palette=HOUSE_PALETTES["b"]),
    (0, 6): partial(draw_house_window, palette=HOUSE_PALETTES["b"]),
    (1, 6): partial(draw_house_door, palette=HOUSE_PALETTES["b"]),
}


def generate(out_path: str, seed: int = DEFAULT_SEED) -> None:
    canvas = Canvas(ATLAS_COLS * TILE_PX, ATLAS_ROWS * TILE_PX)
    for (col, row), drawer in TILE_DRAWERS.items():
        ox, oy = col * TILE_PX, row * TILE_PX
        canvas.clip = (ox, oy, ox + TILE_PX, oy + TILE_PX)
        rng = random.Random(seed + row * ATLAS_COLS + col)
        drawer(canvas, ox, oy, rng)
    canvas.clip = (0, 0, canvas.width, canvas.height)
    write_png(out_path, canvas.width, canvas.height, canvas.data)
    print(f"Generated {os.path.abspath(out_path)} ({canvas.width}x{canvas.height})")


def main() -> None:
    script_dir = os.path.dirname(os.path.abspath(__file__))
    repo_root = os.path.dirname(script_dir)
    parser = argparse.ArgumentParser(description="Generate the original world tile atlas.")
    parser.add_argument(
        "--out",
        default=os.path.join(repo_root, DEFAULT_OUT),
        help=f"Output PNG path (default: <repo>/{DEFAULT_OUT}).",
    )
    parser.add_argument(
        "--seed",
        type=int,
        default=DEFAULT_SEED,
        help=f"Seed for the deterministic tile noise (default: {DEFAULT_SEED}).",
    )
    args = parser.parse_args()
    generate(args.out, args.seed)


if __name__ == "__main__":
    main()
