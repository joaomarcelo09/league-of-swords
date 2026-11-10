#!/usr/bin/env python3
"""
tools/gen_placeholder_sprites.py

Procedurally generates original placeholder sprite sheets for the layered sprite system.
Compatible with the layout defined in data/sprites/layout_lpc.json.
Uses Python standard library only (struct, zlib, json, math) - NO third-party packages.
"""

import json
import math
import os
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


def main() -> None:
    script_dir = os.path.dirname(os.path.abspath(__file__))
    root_dir = os.path.dirname(script_dir)
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
