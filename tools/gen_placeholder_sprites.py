#!/usr/bin/env python3
"""
tools/gen_placeholder_sprites.py

Procedurally generates original placeholder sprite sheets for the layered sprite system.
Compatible with the layout defined in data/sprites/layout_lpc.json.
Uses Python standard library only (struct, zlib, json, math) - NO third-party packages.
"""

import argparse
import json
import math
import os
import random
import struct
import zlib


def write_png(filename: str, width: int, height: int, rgba_bytes: bytearray) -> None:
    """Writes an RGBA PNG file using only struct and zlib."""
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
        scanlines.append(0)  # Filter type 0 (None)
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

    def set_pixel(self, x: int, y: int, r: int, g: int, b: int, a: int = 255) -> None:
        if 0 <= x < self.width and 0 <= y < self.height:
            idx = (y * self.width + x) * 4
            self.data[idx] = r
            self.data[idx + 1] = g
            self.data[idx + 2] = b
            self.data[idx + 3] = a

    def fill_rect(self, x: int, y: int, w: int, h: int, r: int, g: int, b: int, a: int = 255) -> None:
        for py in range(max(0, y), min(self.height, y + h)):
            for px in range(max(0, x), min(self.width, x + w)):
                self.set_pixel(px, py, r, g, b, a)

    def fill_circle(self, cx: int, cy: int, radius: int, r: int, g: int, b: int, a: int = 255) -> None:
        r2 = radius * radius
        for py in range(cy - radius, cy + radius + 1):
            for px in range(cx - radius, cx + radius + 1):
                if (px - cx) ** 2 + (py - cy) ** 2 <= r2:
                    self.set_pixel(px, py, r, g, b, a)

    def draw_line(self, x0: int, y0: int, x1: int, y1: int, r: int, g: int, b: int, a: int = 255, thickness: int = 1) -> None:
        dx = abs(x1 - x0)
        dy = abs(y1 - y0)
        sx = 1 if x0 < x1 else -1
        sy = 1 if y0 < y1 else -1
        err = dx - dy
        x, y = x0, y0
        while True:
            if thickness <= 1:
                self.set_pixel(x, y, r, g, b, a)
            else:
                self.fill_circle(x, y, thickness // 2, r, g, b, a)
            if x == x1 and y == y1:
                break
            e2 = 2 * err
            if e2 > -dy:
                err -= dy
                x += sx
            if e2 < dx:
                err += dx
                y += sy


def draw_body_frame(canvas: Canvas, fx: int, fy: int, anim: str, direction: str, frame: int) -> None:
    skin = (235, 185, 145, 255)
    eye_col = (40, 30, 25, 255)

    bob = 0
    leg_offset = 0
    arm_offset = 0
    if anim == "walk":
        if frame in (2, 6):
            bob = -1
        leg_offset = int(math.sin(frame * math.pi / 4.0) * 4)
        arm_offset = -leg_offset
    elif anim == "slash":
        if frame in (2, 3):
            bob = 1
    elif anim == "hurt":
        bob = min(frame * 2, 8)

    cx = fx + 32
    cy = fy + 18 + bob

    # Head
    canvas.fill_circle(cx, cy, 6, *skin)

    # Eyes / face indicators depending on direction
    if direction == "down":
        canvas.set_pixel(cx - 2, cy, *eye_col)
        canvas.set_pixel(cx + 2, cy, *eye_col)
    elif direction == "left":
        canvas.set_pixel(cx - 4, cy, *eye_col)
    elif direction == "right":
        canvas.set_pixel(cx + 4, cy, *eye_col)

    # Neck
    canvas.fill_rect(cx - 2, cy + 6, 4, 3, *skin)

    # Torso base
    torso_top = cy + 8
    canvas.fill_rect(cx - 5, torso_top, 10, 15, *skin)

    # Arms
    if anim == "slash" and frame in (2, 3):
        # Extended slash arm
        if direction in ("down", "right"):
            canvas.draw_line(cx + 4, torso_top + 2, cx + 14, torso_top + 4, *skin, thickness=3)
            canvas.draw_line(cx - 4, torso_top + 2, cx - 6, torso_top + 10, *skin, thickness=3)
        else:
            canvas.draw_line(cx - 4, torso_top + 2, cx - 14, torso_top + 4, *skin, thickness=3)
            canvas.draw_line(cx + 4, torso_top + 2, cx + 6, torso_top + 10, *skin, thickness=3)
    else:
        # Left arm
        canvas.draw_line(cx - 5, torso_top + 2, cx - 7, torso_top + 12 + arm_offset, *skin, thickness=2)
        # Right arm
        canvas.draw_line(cx + 5, torso_top + 2, cx + 7, torso_top + 12 - arm_offset, *skin, thickness=2)

    # Legs
    legs_top = torso_top + 15
    canvas.draw_line(cx - 3, legs_top, cx - 4, legs_top + 14 + leg_offset, *skin, thickness=2)
    canvas.draw_line(cx + 3, legs_top, cx + 4, legs_top + 14 - leg_offset, *skin, thickness=2)


def draw_hair_frame(canvas: Canvas, fx: int, fy: int, anim: str, direction: str, frame: int) -> None:
    hair_col = (115, 60, 30, 255)
    highlight = (145, 80, 45, 255)

    bob = 0
    if anim == "walk" and frame in (2, 6):
        bob = -1
    elif anim == "slash" and frame in (2, 3):
        bob = 1
    elif anim == "hurt":
        bob = min(frame * 2, 8)

    cx = fx + 32
    cy = fy + 18 + bob

    # Cap / top of hair
    canvas.fill_circle(cx, cy - 2, 7, *hair_col)
    canvas.fill_rect(cx - 5, cy - 8, 10, 3, *highlight)

    # Direction specific hair styling
    if direction == "up":
        # Back of head: hair extends lower
        canvas.fill_rect(cx - 6, cy - 2, 12, 8, *hair_col)
    elif direction == "left":
        canvas.fill_rect(cx - 1, cy - 4, 8, 7, *hair_col)
        canvas.fill_rect(cx - 7, cy - 5, 4, 5, *highlight)
    elif direction == "right":
        canvas.fill_rect(cx - 7, cy - 4, 8, 7, *hair_col)
        canvas.fill_rect(cx + 3, cy - 5, 4, 5, *highlight)
    elif direction == "down":
        # Bangs across forehead
        canvas.fill_rect(cx - 6, cy - 6, 12, 4, *hair_col)
        canvas.fill_rect(cx - 5, cy - 3, 3, 2, *hair_col)
        canvas.fill_rect(cx + 2, cy - 3, 3, 2, *hair_col)


def draw_clothes_frame(canvas: Canvas, fx: int, fy: int, anim: str, direction: str, frame: int) -> None:
    tunic_col = (45, 95, 175, 255)
    tunic_trim = (30, 70, 130, 255)
    pants_col = (40, 50, 70, 255)
    belt_col = (85, 45, 20, 255)

    bob = 0
    leg_offset = 0
    if anim == "walk":
        if frame in (2, 6):
            bob = -1
        leg_offset = int(math.sin(frame * math.pi / 4.0) * 4)
    elif anim == "slash" and frame in (2, 3):
        bob = 1
    elif anim == "hurt":
        bob = min(frame * 2, 8)

    cx = fx + 32
    cy = fy + 18 + bob
    torso_top = cy + 8

    # Tunic
    canvas.fill_rect(cx - 6, torso_top, 12, 13, *tunic_col)
    canvas.fill_rect(cx - 6, torso_top + 12, 12, 2, *tunic_trim)
    # Belt
    canvas.fill_rect(cx - 6, torso_top + 8, 12, 2, *belt_col)

    # Sleeves
    canvas.fill_rect(cx - 8, torso_top + 1, 3, 4, *tunic_col)
    canvas.fill_rect(cx + 5, torso_top + 1, 3, 4, *tunic_col)

    # Pants on legs
    legs_top = torso_top + 14
    canvas.draw_line(cx - 3, legs_top, cx - 4, legs_top + 10 + leg_offset, *pants_col, thickness=3)
    canvas.draw_line(cx + 3, legs_top, cx + 4, legs_top + 10 - leg_offset, *pants_col, thickness=3)


def draw_armor_frame(canvas: Canvas, fx: int, fy: int, anim: str, direction: str, frame: int) -> None:
    plate_col = (175, 190, 205, 255)
    dark_trim = (110, 125, 140, 255)
    highlight = (215, 225, 235, 255)

    bob = 0
    leg_offset = 0
    if anim == "walk":
        if frame in (2, 6):
            bob = -1
        leg_offset = int(math.sin(frame * math.pi / 4.0) * 4)
    elif anim == "slash" and frame in (2, 3):
        bob = 1
    elif anim == "hurt":
        bob = min(frame * 2, 8)

    cx = fx + 32
    cy = fy + 18 + bob
    torso_top = cy + 8

    # Breastplate
    canvas.fill_rect(cx - 5, torso_top + 1, 10, 8, *plate_col)
    canvas.fill_rect(cx - 4, torso_top + 2, 4, 4, *highlight)
    canvas.fill_rect(cx - 5, torso_top + 8, 10, 1, *dark_trim)

    # Pauldrons (shoulder guards)
    canvas.fill_rect(cx - 8, torso_top, 4, 4, *plate_col)
    canvas.fill_rect(cx + 4, torso_top, 4, 4, *plate_col)

    # Knee/greaves guards
    legs_top = torso_top + 14
    canvas.fill_rect(cx - 5, legs_top + 5 + leg_offset, 3, 4, *plate_col)
    canvas.fill_rect(cx + 2, legs_top + 5 - leg_offset, 3, 4, *plate_col)


def draw_weapon_frame(canvas: Canvas, fx: int, fy: int, anim: str, direction: str, frame: int) -> None:
    blade_col = (220, 230, 245, 255)
    blade_hi = (255, 255, 255, 255)
    guard_col = (230, 175, 40, 255)
    hilt_col = (130, 30, 30, 255)

    bob = 0
    if anim == "walk" and frame in (2, 6):
        bob = -1
    elif anim == "slash" and frame in (2, 3):
        bob = 1
    elif anim == "hurt":
        bob = min(frame * 2, 8)

    cx = fx + 32
    cy = fy + 18 + bob
    torso_top = cy + 8

    if anim == "slash":
        # Slashing motion frames 0..5
        # Windup -> strike -> follow-through
        angles = {
            0: -0.8,
            1: -1.2,
            2: -0.2,
            3: 0.8,
            4: 1.2,
            5: 0.9,
        }
        angle = angles.get(frame, 0.0)
        hand_x = cx + 8 if direction in ("down", "right") else cx - 8
        hand_y = torso_top + 5

        # Blade tip based on angle
        blade_len = 16
        tip_x = int(hand_x + math.cos(angle) * blade_len)
        tip_y = int(hand_y + math.sin(angle) * blade_len)

        # Draw blade and hilt
        canvas.draw_line(hand_x, hand_y, tip_x, tip_y, *blade_col, thickness=2)
        canvas.draw_line(hand_x, hand_y, tip_x, tip_y, *blade_hi, thickness=1)
        canvas.fill_circle(hand_x, hand_y, 2, *guard_col)
    else:
        # Standard idle / walk / hurt weapon held or sheathed
        if direction == "up":
            # Sword vertical behind character
            sx = cx + 6
            sy = torso_top - 4
            canvas.draw_line(sx, sy, sx, sy + 18, *blade_col, thickness=2)
            canvas.fill_rect(sx - 2, sy + 12, 5, 2, *guard_col)
            canvas.fill_rect(sx - 1, sy + 14, 3, 3, *hilt_col)
        elif direction == "left":
            sx = cx - 8
            sy = torso_top + 2
            canvas.draw_line(sx, sy, sx - 2, sy + 16, *blade_col, thickness=2)
            canvas.fill_rect(sx - 3, sy + 4, 4, 2, *guard_col)
            canvas.fill_rect(sx - 2, sy + 2, 2, 2, *hilt_col)
        elif direction == "right":
            sx = cx + 8
            sy = torso_top + 2
            canvas.draw_line(sx, sy, sx + 2, sy + 16, *blade_col, thickness=2)
            canvas.fill_rect(sx - 1, sy + 4, 4, 2, *guard_col)
            canvas.fill_rect(sx, sy + 2, 2, 2, *hilt_col)
        else:  # down
            sx = cx + 9
            sy = torso_top + 2
            canvas.draw_line(sx, sy, sx, sy + 18, *blade_col, thickness=2)
            canvas.draw_line(sx, sy, sx, sy + 18, *blade_hi, thickness=1)
            canvas.fill_rect(sx - 3, sy + 6, 7, 2, *guard_col)
            canvas.fill_rect(sx - 1, sy + 4, 3, 2, *hilt_col)


DRAW_HANDLERS = {
    "body": draw_body_frame,
    "hair": draw_hair_frame,
    "clothes": draw_clothes_frame,
    "armor": draw_armor_frame,
    "weapon": draw_weapon_frame,
}


# ---------------------------------------------------------------------------
# Tile atlas (assets/tiles/placeholder_tiles.png), JGT-80.
# Layout is referenced by data/tilesets/floor1.json; keep coords in sync.
# Row 0 cols 0-3 (wall, floor, grass, fallback) are the original tiles and are
# copied unchanged from the existing atlas when it exists.
# ---------------------------------------------------------------------------

TILE_PX = 32
ATLAS_COLS = 8
ATLAS_ROWS = 3


def read_png_rgba(filename: str):
    """Minimal 8-bit RGBA, non-interlaced PNG reader (stdlib only). Returns (w, h, bytearray) or None."""
    with open(filename, "rb") as f:
        data = f.read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        return None
    pos = 8
    width = height = 0
    idat = b""
    while pos < len(data):
        length = struct.unpack(">I", data[pos : pos + 4])[0]
        ctype = data[pos + 4 : pos + 8]
        body = data[pos + 8 : pos + 8 + length]
        pos += 12 + length
        if ctype == b"IHDR":
            width, height, depth, color, _c, _f, interlace = struct.unpack(">IIBBBBB", body)
            if depth != 8 or color != 6 or interlace != 0:
                return None
        elif ctype == b"IDAT":
            idat += body
    raw = zlib.decompress(idat)
    stride = width * 4
    out = bytearray(width * height * 4)
    prev = bytearray(stride)
    src = 0
    for y in range(height):
        ftype = raw[src]
        src += 1
        line = bytearray(raw[src : src + stride])
        src += stride
        for i in range(stride):
            a = line[i - 4] if i >= 4 else 0
            b = prev[i]
            c = prev[i - 4] if i >= 4 else 0
            if ftype == 1:
                line[i] = (line[i] + a) & 0xFF
            elif ftype == 2:
                line[i] = (line[i] + b) & 0xFF
            elif ftype == 3:
                line[i] = (line[i] + ((a + b) >> 1)) & 0xFF
            elif ftype == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pred = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pred) & 0xFF
        out[y * stride : (y + 1) * stride] = line
        prev = line
    return width, height, out


def _shade(col, k: int):
    return tuple(max(0, min(255, c + k)) for c in col[:3]) + (col[3] if len(col) > 3 else 255,)


def draw_base_wall(cv: Canvas, ox: int, oy: int, rng: random.Random) -> None:
    base = (70, 72, 80, 255)
    mortar = (40, 41, 46, 255)
    cv.fill_rect(ox, oy, TILE_PX, TILE_PX, *mortar)
    for row in range(4):
        y = oy + row * 8
        shift = 0 if row % 2 == 0 else 8
        for col in range(-1, 3):
            x = ox + col * 16 + shift
            x0 = max(ox, x + 1)
            x1 = min(ox + TILE_PX, x + 16)
            if x1 > x0:
                cv.fill_rect(x0, y + 1, x1 - x0, 6, *_shade(base, rng.randint(-8, 8)))


def draw_base_floor(cv: Canvas, ox: int, oy: int, rng: random.Random) -> None:
    base = (150, 152, 158, 255)
    cv.fill_rect(ox, oy, TILE_PX, TILE_PX, *base)
    for _ in range(40):
        cv.set_pixel(ox + rng.randrange(TILE_PX), oy + rng.randrange(TILE_PX), *_shade(base, rng.randint(-20, 12)))


def draw_base_grass(cv: Canvas, ox: int, oy: int, rng: random.Random) -> None:
    base = (60, 140, 60, 255)
    cv.fill_rect(ox, oy, TILE_PX, TILE_PX, *base)
    for _ in range(50):
        cv.set_pixel(ox + rng.randrange(TILE_PX), oy + rng.randrange(TILE_PX), *_shade(base, rng.randint(-25, 25)))


def draw_fallback(cv: Canvas, ox: int, oy: int, rng: random.Random) -> None:
    for y in range(4):
        for x in range(4):
            col = (255, 0, 255, 255) if (x + y) % 2 == 0 else (20, 20, 20, 255)
            cv.fill_rect(ox + x * 8, oy + y * 8, 8, 8, *col)


def copy_tile(cv: Canvas, src: tuple, ox: int, oy: int) -> None:
    """Copies an already drawn atlas tile so variants share the original look."""
    sx, sy = src[0] * TILE_PX, src[1] * TILE_PX
    for y in range(TILE_PX):
        s = ((sy + y) * cv.width + sx) * 4
        d = ((oy + y) * cv.width + ox) * 4
        cv.data[d : d + TILE_PX * 4] = cv.data[s : s + TILE_PX * 4]


def draw_wall_cracked(cv: Canvas, ox: int, oy: int, rng: random.Random) -> None:
    copy_tile(cv, (0, 0), ox, oy)
    crack = (25, 25, 30, 255)
    x, y = ox + 10, oy + 2
    for _ in range(9):
        nx = max(ox + 1, min(ox + 30, x + rng.randint(-2, 3)))
        ny = min(oy + 30, y + rng.randint(2, 4))
        cv.draw_line(x, y, nx, ny, *crack)
        x, y = nx, ny


def draw_wall_mossy(cv: Canvas, ox: int, oy: int, rng: random.Random) -> None:
    copy_tile(cv, (0, 0), ox, oy)
    for _ in range(9):
        cx = ox + rng.randrange(TILE_PX)
        cy = oy + 18 + rng.randrange(14)
        cv.fill_circle(cx, cy, rng.randint(1, 3), *_shade((60, 105, 55, 255), rng.randint(-15, 15)))


def draw_floor_cracked(cv: Canvas, ox: int, oy: int, rng: random.Random) -> None:
    copy_tile(cv, (1, 0), ox, oy)
    crack = (100, 100, 108, 255)
    cv.draw_line(ox + 4, oy + 20, ox + 14, oy + 16, *crack)
    cv.draw_line(ox + 14, oy + 16, ox + 20, oy + 22, *crack)
    cv.draw_line(ox + 14, oy + 16, ox + 17, oy + 8, *crack)
    cv.draw_line(ox + 20, oy + 22, ox + 28, oy + 21, *crack)


def draw_floor_stained(cv: Canvas, ox: int, oy: int, rng: random.Random) -> None:
    copy_tile(cv, (1, 0), ox, oy)
    # Damp stain on one slab
    cv.fill_circle(ox + 23, oy + 8, 4, 135, 133, 130, 255)
    cv.fill_circle(ox + 21, oy + 9, 2, 125, 122, 120, 255)


def draw_grass_dark(cv: Canvas, ox: int, oy: int, rng: random.Random) -> None:
    copy_tile(cv, (2, 0), ox, oy)
    for _ in range(14):
        cx = ox + rng.randrange(TILE_PX)
        cy = oy + rng.randrange(TILE_PX)
        cv.fill_circle(cx, cy, rng.randint(1, 2), 48, 118, 50, 255)


def draw_grass_flowers(cv: Canvas, ox: int, oy: int, rng: random.Random) -> None:
    copy_tile(cv, (2, 0), ox, oy)
    petals = [(235, 220, 90, 255), (240, 240, 240, 255), (200, 120, 200, 255)]
    for _ in range(5):
        cx = ox + 3 + rng.randrange(TILE_PX - 6)
        cy = oy + 3 + rng.randrange(TILE_PX - 6)
        col = rng.choice(petals)
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            cv.set_pixel(cx + dx, cy + dy, *col)
        cv.set_pixel(cx, cy, 220, 150, 40, 255)


def _cobbles(cv: Canvas, ox: int, oy: int, rng: random.Random, base) -> None:
    grout = (95, 88, 78, 255)
    cv.fill_rect(ox, oy, TILE_PX, TILE_PX, *grout)
    for row in range(4):
        shift = 0 if row % 2 == 0 else 5
        for col in range(-1, 4):
            x = ox + col * 10 + shift
            y = oy + row * 8
            x0 = max(ox, x + 1)
            x1 = min(ox + TILE_PX, x + 10)
            if x1 > x0:
                cv.fill_rect(x0, y + 1, x1 - x0, 6, *_shade(base, rng.randint(-12, 12)))


def draw_town_cobble(cv: Canvas, ox: int, oy: int, rng: random.Random) -> None:
    _cobbles(cv, ox, oy, rng, (176, 160, 136, 255))


def draw_town_cobble_b(cv: Canvas, ox: int, oy: int, rng: random.Random) -> None:
    _cobbles(cv, ox, oy, rng, (166, 152, 132, 255))
    cv.fill_circle(ox + 9, oy + 22, 2, 80, 130, 70, 255)  # weed in the grout


def draw_town_cobble_c(cv: Canvas, ox: int, oy: int, rng: random.Random) -> None:
    _cobbles(cv, ox, oy, rng, (184, 168, 142, 255))


# --- Decor (transparent background, drawn on the decor layer) ---

def draw_decor_grass_tuft(cv: Canvas, ox: int, oy: int, rng: random.Random) -> None:
    blade = (40, 105, 40, 255)
    light = (95, 175, 80, 255)
    for cx in (9, 20):
        base_y = oy + 26 if cx == 9 else oy + 18
        for k in range(-3, 4):
            col = light if k % 2 == 0 else blade
            cv.draw_line(ox + cx, base_y, ox + cx + k * 2, base_y - 8 - abs(3 - abs(k)) * 2, *col)


def draw_decor_house(cv: Canvas, ox: int, oy: int, rng: random.Random) -> None:
    # Roof shingles seen from above (tiles repeat across the building footprint)
    roof = (150, 62, 48, 255)
    dark = (105, 40, 32, 255)
    cv.fill_rect(ox, oy, TILE_PX, TILE_PX, *roof)
    for row in range(4):
        y = oy + row * 8
        cv.fill_rect(ox, y + 7, TILE_PX, 1, *dark)
        shift = 0 if row % 2 == 0 else 4
        for x in range(ox + shift, ox + TILE_PX, 8):
            cv.fill_rect(x, y, 1, 7, *dark)
            cv.fill_rect(x + 1, y, 6, 2, *_shade(roof, 18))


def draw_decor_fountain(cv: Canvas, ox: int, oy: int, rng: random.Random) -> None:
    rim = (170, 170, 178, 255)
    rim_dark = (110, 110, 120, 255)
    water = (60, 120, 200, 255)
    cv.fill_circle(ox + 16, oy + 16, 15, *rim_dark)
    cv.fill_circle(ox + 16, oy + 16, 14, *rim)
    cv.fill_circle(ox + 16, oy + 16, 11, *water)
    cv.fill_circle(ox + 16, oy + 16, 3, *rim)
    for ang in range(0, 360, 45):
        r = math.radians(ang)
        cv.set_pixel(ox + 16 + int(round(math.cos(r) * 7)), oy + 16 + int(round(math.sin(r) * 7)), 190, 225, 255, 255)


def draw_decor_torch(cv: Canvas, ox: int, oy: int, rng: random.Random) -> None:
    # Iron bracket with a flame, meant to sit on a wall tile
    cv.fill_rect(ox + 13, oy + 14, 6, 3, 50, 45, 40, 255)
    cv.fill_rect(ox + 15, oy + 14, 2, 12, 95, 65, 35, 255)
    cv.fill_circle(ox + 16, oy + 10, 5, 230, 110, 30, 255)
    cv.fill_circle(ox + 16, oy + 11, 3, 250, 200, 70, 255)
    cv.set_pixel(ox + 16, oy + 4, 230, 110, 30, 255)
    cv.set_pixel(ox + 16, oy + 5, 240, 150, 40, 255)
    # Warm glow halo
    for ang in range(0, 360, 30):
        r = math.radians(ang)
        cv.set_pixel(ox + 16 + int(math.cos(r) * 8), oy + 10 + int(math.sin(r) * 8), 255, 190, 90, 90)


def draw_decor_bones(cv: Canvas, ox: int, oy: int, rng: random.Random) -> None:
    bone = (228, 222, 200, 255)
    shadow = (150, 145, 130, 255)
    cv.draw_line(ox + 6, oy + 24, ox + 20, oy + 18, *bone, thickness=2)
    cv.fill_circle(ox + 6, oy + 24, 2, *bone)
    cv.fill_circle(ox + 20, oy + 18, 2, *bone)
    cv.draw_line(ox + 10, oy + 14, ox + 18, oy + 27, *bone, thickness=2)
    # Skull
    cv.fill_circle(ox + 24, oy + 10, 4, *bone)
    cv.set_pixel(ox + 23, oy + 10, *shadow)
    cv.set_pixel(ox + 25, oy + 10, *shadow)
    cv.fill_rect(ox + 22, oy + 13, 5, 2, *bone)


def draw_decor_crate(cv: Canvas, ox: int, oy: int, rng: random.Random) -> None:
    wood = (150, 105, 60, 255)
    dark = (90, 60, 32, 255)
    cv.fill_rect(ox + 4, oy + 4, 24, 24, *dark)
    cv.fill_rect(ox + 6, oy + 6, 20, 20, *wood)
    cv.draw_line(ox + 6, oy + 6, ox + 25, oy + 25, *dark, thickness=2)
    cv.draw_line(ox + 25, oy + 6, ox + 6, oy + 25, *dark, thickness=2)
    cv.fill_rect(ox + 6, oy + 6, 20, 1, *_shade(wood, 30))


def draw_decor_barrel(cv: Canvas, ox: int, oy: int, rng: random.Random) -> None:
    cv.fill_circle(ox + 16, oy + 16, 11, 85, 55, 30, 255)
    cv.fill_circle(ox + 16, oy + 16, 9, 140, 95, 55, 255)
    cv.fill_circle(ox + 16, oy + 16, 6, 120, 80, 45, 255)
    for ang in range(0, 360, 20):
        r = math.radians(ang)
        cv.set_pixel(ox + 16 + int(round(math.cos(r) * 10)), oy + 16 + int(round(math.sin(r) * 10)), 60, 60, 66, 255)


def draw_decor_rubble(cv: Canvas, ox: int, oy: int, rng: random.Random) -> None:
    for _ in range(7):
        cx = ox + 5 + rng.randrange(22)
        cy = oy + 5 + rng.randrange(22)
        rad = rng.randint(2, 4)
        cv.fill_circle(cx + 1, cy + 1, rad, 35, 35, 40, 255)
        cv.fill_circle(cx, cy, rad, *_shade((105, 100, 95, 255), rng.randint(-15, 15)))
        cv.set_pixel(cx - 1, cy - 1, 150, 145, 140, 255)


# (col, row) -> draw function. Row 0 cols 0-3 are the original tiles.
TILE_DRAWERS = {
    (0, 0): draw_base_wall,
    (1, 0): draw_base_floor,
    (2, 0): draw_base_grass,
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
    (0, 2): draw_decor_grass_tuft,
    (1, 2): draw_decor_house,
    (2, 2): draw_decor_fountain,
    (3, 2): draw_decor_torch,
    (4, 2): draw_decor_bones,
    (5, 2): draw_decor_crate,
    (6, 2): draw_decor_barrel,
    (7, 2): draw_decor_rubble,
}
ORIGINAL_TILES = [(0, 0), (1, 0), (2, 0), (3, 0)]


def generate_tiles(root_dir: str) -> None:
    out_path = os.path.join(root_dir, "assets", "tiles", "placeholder_tiles.png")
    width = ATLAS_COLS * TILE_PX
    height = ATLAS_ROWS * TILE_PX
    canvas = Canvas(width, height)

    existing = read_png_rgba(out_path) if os.path.exists(out_path) else None

    for (col, row), drawer in TILE_DRAWERS.items():
        ox, oy = col * TILE_PX, row * TILE_PX
        if (col, row) in ORIGINAL_TILES and existing is not None:
            ew, eh, epx = existing
            if (col + 1) * TILE_PX <= ew and (row + 1) * TILE_PX <= eh:
                for y in range(TILE_PX):
                    s = ((oy + y) * ew + ox) * 4
                    d = ((oy + y) * width + ox) * 4
                    canvas.data[d : d + TILE_PX * 4] = epx[s : s + TILE_PX * 4]
                continue
        # Fixed seed per tile: same output every run
        drawer(canvas, ox, oy, random.Random(1000 + row * 100 + col))

    write_png(out_path, width, height, canvas.data)
    print(f"Generated {out_path} ({width}x{height})")


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate original placeholder art.")
    parser.add_argument(
        "--only",
        choices=["all", "characters", "tiles"],
        default="all",
        help="Which outputs to regenerate (default: all).",
    )
    args = parser.parse_args()

    script_dir = os.path.dirname(os.path.abspath(__file__))
    root_dir = os.path.dirname(script_dir)

    if args.only in ("all", "tiles"):
        generate_tiles(root_dir)
    if args.only == "tiles":
        return

    layout_path = os.path.join(root_dir, "data", "sprites", "layout_lpc.json")

    with open(layout_path, "r", encoding="utf-8") as f:
        layout = json.load(f)

    frame_w = layout.get("frame_width", 64)
    frame_h = layout.get("frame_height", 64)

    # Determine sheet dimensions
    max_row = 0
    for anim_data in layout.get("animations", {}).values():
        for row in anim_data.get("rows", {}).values():
            if row > max_row:
                max_row = row

    sheet_cols = 13
    sheet_rows = max(max_row + 1, 21)
    sheet_w = sheet_cols * frame_w
    sheet_h = sheet_rows * frame_h

    out_dir = os.path.join(root_dir, "assets", "characters", "placeholder")
    os.makedirs(out_dir, exist_ok=True)

    layers = layout.get("layer_draw_order", ["body", "hair", "clothes", "armor", "weapon"])

    for layer in layers:
        handler = DRAW_HANDLERS.get(layer)
        if not handler:
            print(f"Skipping unknown layer: {layer}")
            continue

        canvas = Canvas(sheet_w, sheet_h)

        for anim_name, anim_data in layout.get("animations", {}).items():
            frame_count = anim_data.get("frame_count", 1)
            rows = anim_data.get("rows", {})
            # Group directions sharing a row so each row is drawn only once
            row_to_dirs = {}
            for direction, row_idx in rows.items():
                row_to_dirs.setdefault(row_idx, []).append(direction)

            for row_idx, dirs in row_to_dirs.items():
                # Prefer front-facing ("down") if multiple directions share the row
                direction = "down" if "down" in dirs else dirs[0]
                fy = row_idx * frame_h
                for f_idx in range(frame_count):
                    fx = f_idx * frame_w
                    handler(canvas, fx, fy, anim_name, direction, f_idx)

        out_path = os.path.join(out_dir, f"{layer}.png")
        write_png(out_path, sheet_w, sheet_h, canvas.data)
        print(f"Generated {out_path} ({sheet_w}x{sheet_h})")


if __name__ == "__main__":
    main()
