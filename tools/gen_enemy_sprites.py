#!/usr/bin/env python3
"""
tools/gen_enemy_sprites.py

Procedurally draws the original sprite sheets for the Floor 1 enemies:
ash_stalker (ash-grey humanoid predator), bog_slime (squat green-brown blob) and
cinder_bat (ember-orange bat).

The sheets are stacked exactly like the layout in data/sprites/layout.json (64px
frames, walk rows 8-11, slash rows 12-15, hurt row 20) and are written to
assets/characters/<enemy_id>/body.png. Art is original pixel art drawn by this
script; no third-party assets. Python standard library only - the PNG writer is
reused from tools/gen_placeholder_sprites.py.
"""

import argparse
import json
import math
import os
import sys

# Keep the tools/ folder free of __pycache__ when this script imports the PNG writer.
sys.dont_write_bytecode = True

from gen_placeholder_sprites import Canvas, write_png


# --- drawing helpers ------------------------------------------------------------------


class PixelCanvas(Canvas):
    """Canvas with antialias-free ellipse and polygon fills for pixel art."""

    def fill_ellipse(self, cx: float, cy: float, rx: float, ry: float, r: int, g: int, b: int, a: int = 255) -> None:
        if rx <= 0 or ry <= 0:
            return
        for py in range(int(round(cy - ry)), int(round(cy + ry)) + 1):
            rel = (py - cy) / ry
            span = rx * math.sqrt(max(0.0, 1.0 - rel * rel))
            for px in range(int(round(cx - span)), int(round(cx + span)) + 1):
                self.set_pixel(px, py, r, g, b, a)

    def fill_poly(self, points: list, r: int, g: int, b: int, a: int = 255) -> None:
        if len(points) < 3:
            return
        ys = [p[1] for p in points]
        for py in range(int(math.floor(min(ys))), int(math.ceil(max(ys))) + 1):
            crossings = []
            count = len(points)
            for i in range(count):
                x1, y1 = points[i]
                x2, y2 = points[(i + 1) % count]
                if y1 == y2:
                    continue
                if (y1 <= py < y2) or (y2 <= py < y1):
                    t = (py - y1) / (y2 - y1)
                    crossings.append(x1 + t * (x2 - x1))
            crossings.sort()
            for i in range(0, len(crossings) - 1, 2):
                for px in range(int(round(crossings[i])), int(round(crossings[i + 1])) + 1):
                    self.set_pixel(px, py, r, g, b, a)


def stroke_poly(canvas: PixelCanvas, points: list, color: tuple, thickness: int = 1) -> None:
    count = len(points)
    for i in range(count):
        x1, y1 = points[i]
        x2, y2 = points[(i + 1) % count]
        canvas.draw_line(int(x1), int(y1), int(x2), int(y2), *color, thickness=thickness)


def stride_cycle(frame: int) -> float:
    """One full walk cycle over the layout's 9 walk frames (0..1..0..-1..0)."""
    return math.sin(frame * math.pi / 4.0)


def side_of(direction: str) -> int:
    return -1 if direction == "left" else 1


# --- ash stalker ----------------------------------------------------------------------

ASH_OUTLINE = (24, 22, 28, 255)
ASH_DARK = (62, 60, 70, 255)
ASH_MID = (96, 94, 106, 255)
ASH_LIGHT = (138, 136, 150, 255)
ASH_PALE = (182, 180, 192, 255)
ASH_CLOTH = (44, 40, 48, 255)
ASH_CLOTH_LIGHT = (70, 64, 74, 255)
ASH_EYE = (255, 190, 88, 255)
ASH_EYE_DARK = (58, 30, 8, 255)


def draw_ash_stalker_frame(canvas: PixelCanvas, fx: int, fy: int, anim: str, direction: str, frame: int) -> None:
    cx = fx + 32
    ground = fy + 60
    side = side_of(direction)

    if anim == "hurt" and frame >= 4:
        _draw_ash_stalker_fallen(canvas, cx, ground, frame)
        return

    stride = 0
    arm_swing = 0
    bob = 0
    if anim == "walk":
        s = stride_cycle(frame)
        stride = int(round(s * 4))
        arm_swing = -stride
        bob = -1 if abs(stride) >= 3 else 0
    elif anim == "slash":
        bob = 1 if frame <= 1 else 0
        stride = 2 if 2 <= frame <= 3 else 0
    elif anim == "hurt":
        bob = -2 if frame in (1, 2) else (-1 if frame == 0 else 0)

    head_cy = fy + 16 + bob
    shoulder_y = head_cy + 7
    hip_y = head_cy + 22
    profile = direction in ("left", "right")

    # Coiled back arm first, then the body, so the striking arm stays in front.
    arm_back = cx - side * 7
    if profile:
        canvas.draw_line(arm_back, shoulder_y + 2, arm_back - side * 2, shoulder_y + 11, *ASH_DARK, thickness=2)
    else:
        canvas.draw_line(arm_back, shoulder_y + 1, arm_back - side * 2 - arm_swing, shoulder_y + 9, *ASH_DARK, thickness=3)
        canvas.draw_line(arm_back - side * 2 - arm_swing, shoulder_y + 9, arm_back - side * 1 - arm_swing, shoulder_y + 16, *ASH_DARK, thickness=2)

    # Legs: digitigrade, long shins. In profile both legs overlap on the stride axis.
    leg_x = 2 if profile else 4
    foot_l = (cx - leg_x + stride, ground - 2)
    foot_r = (cx + leg_x - stride, ground - 2)
    knee_l = (cx - leg_x + stride // 2, hip_y + 8)
    knee_r = (cx + leg_x - stride // 2, hip_y + 8)
    canvas.draw_line(cx - 3, hip_y, knee_l[0], knee_l[1], *ASH_DARK, thickness=3)
    canvas.draw_line(knee_l[0], knee_l[1], foot_l[0], foot_l[1], *ASH_MID, thickness=2)
    canvas.draw_line(cx + 3, hip_y, knee_r[0], knee_r[1], *ASH_DARK, thickness=3)
    canvas.draw_line(knee_r[0], knee_r[1], foot_r[0], foot_r[1], *ASH_MID, thickness=2)
    for foot in (foot_l, foot_r):
        for toe in (-1, 0, 1):
            canvas.set_pixel(foot[0] + toe, ground - 1, *ASH_PALE)

    # Hunched torso, tapered to the hips.
    torso = [
        (cx - 7, shoulder_y),
        (cx + 7, shoulder_y),
        (cx + 5, hip_y),
        (cx - 5, hip_y),
    ]
    canvas.fill_poly(torso, *ASH_MID)
    stroke_poly(canvas, torso, ASH_OUTLINE)
    back_edge = cx - side * 6
    canvas.draw_line(back_edge, shoulder_y + 1, cx - side * 5, hip_y - 1, *ASH_DARK, thickness=2)
    if direction != "up":
        for i in range(3):
            canvas.fill_rect(cx - 4, shoulder_y + 3 + i * 4, 8, 1, *ASH_DARK)
    else:
        for i in range(4):
            canvas.set_pixel(cx, shoulder_y + 3 + i * 4, *ASH_PALE)

    # Tattered waist wrap.
    for i in range(-6, 7):
        tail = 4 + (i * 5) % 3
        canvas.fill_rect(cx + i, hip_y - 2, 1, tail, *ASH_CLOTH)
    canvas.fill_rect(cx - 6, hip_y - 2, 12, 1, *ASH_CLOTH_LIGHT)

    # Neck and skull.
    canvas.fill_rect(cx - 2, head_cy + 5, 4, 3, *ASH_DARK)
    canvas.fill_ellipse(cx, head_cy, 6, 7, *ASH_OUTLINE)
    canvas.fill_ellipse(cx, head_cy, 5, 6, *ASH_DARK)
    if direction == "up":
        canvas.fill_ellipse(cx, head_cy + 1, 4, 4, *ASH_MID)
        for i in (-3, 0, 3):
            canvas.fill_rect(cx + i, head_cy - 6, 1, 2, *ASH_PALE)
        canvas.draw_line(cx, head_cy - 3, cx, head_cy + 4, *ASH_LIGHT)
    else:
        face_x = cx + side if direction != "down" else cx
        canvas.fill_ellipse(face_x, head_cy + 1, 4, 4, *ASH_MID)
        if profile:
            # Pointed snout toward the facing side.
            snout = [(face_x + side * 3, head_cy - 1), (face_x + side * 7, head_cy + 2), (face_x + side * 3, head_cy + 4)]
            canvas.fill_poly(snout, *ASH_DARK)
            stroke_poly(canvas, snout, ASH_OUTLINE)
        eyes = [-3, 2] if direction == "down" else [side * 3]
        for eye_x in eyes:
            canvas.fill_rect(face_x + eye_x, head_cy - 1, 2, 2, *ASH_EYE_DARK)
            canvas.set_pixel(face_x + eye_x, head_cy - 1, *ASH_EYE)
        if direction == "down":
            canvas.fill_rect(cx - 2, head_cy + 4, 5, 1, *ASH_EYE_DARK)
            canvas.set_pixel(cx - 4, head_cy - 2, *ASH_DARK)
            canvas.set_pixel(cx + 3, head_cy - 2, *ASH_DARK)
        else:
            canvas.fill_rect(face_x + side * 2, head_cy + 3, 3, 1, *ASH_EYE_DARK)
        # Jagged ears/ash shards at the back of the skull.
        ear_x = cx - side * 5
        ear = [(ear_x, head_cy - 3), (ear_x - side * 4, head_cy - 7), (ear_x - side * 1, head_cy + 2)]
        canvas.fill_poly(ear, *ASH_CLOTH_LIGHT)
        stroke_poly(canvas, ear, ASH_OUTLINE)

    # Shoulder shards.
    for s in (-1, 1):
        base_x = cx + s * 7
        shard = [(base_x, shoulder_y + 1), (base_x + s * 4, shoulder_y - 4), (base_x + s * 3, shoulder_y + 4)]
        canvas.fill_poly(shard, *ASH_CLOTH)
        stroke_poly(canvas, shard, ASH_OUTLINE)

    # Front (striking) arm.
    if anim == "slash" and frame <= 1:
        hand = (cx + side * 8, shoulder_y + 4)
    elif anim == "slash":
        hand = _ash_slash_hand(cx, head_cy, shoulder_y, hip_y, direction, frame)
    elif anim == "hurt":
        hand = (cx + side * 9, shoulder_y - 6)
    else:
        hand = (cx + side * (8 + arm_swing), shoulder_y + 16)
    elbow = (cx + side * 9, shoulder_y + (2 if anim == "hurt" else 9))
    canvas.draw_line(cx + side * 7, shoulder_y + 1, elbow[0], elbow[1], *ASH_DARK, thickness=3)
    canvas.draw_line(elbow[0], elbow[1], hand[0], hand[1], *ASH_MID, thickness=2)
    if anim == "slash" and frame >= 2:
        for claw in (-1, 0, 1):
            canvas.draw_line(hand[0] + claw, hand[1], hand[0] + claw * 2, hand[1] + 3, *ASH_PALE)
        _draw_ash_slash_trail(canvas, cx, head_cy, shoulder_y, hip_y, direction, frame)
    else:
        for claw in (-1, 0, 1):
            canvas.set_pixel(hand[0] + claw, hand[1] + 2, *ASH_PALE)

    # Drifting ash flecks (two per frame, deterministic).
    fleck_y = head_cy - 4 + (frame * 3) % 7
    canvas.set_pixel(cx - 12 - (frame % 2), fleck_y, ASH_PALE[0], ASH_PALE[1], ASH_PALE[2], 150)
    canvas.set_pixel(cx + 12, fleck_y + 5, ASH_PALE[0], ASH_PALE[1], ASH_PALE[2], 120)


def _ash_slash_hand(cx: int, head_cy: int, shoulder_y: int, hip_y: int, direction: str, frame: int) -> tuple:
    side = side_of(direction)
    reach = 14 if 2 <= frame <= 3 else 10
    if direction in ("left", "right"):
        return (cx + side * reach, shoulder_y + 7)
    if direction == "down":
        return (cx + 7, hip_y + 3)
    return (cx + 6, head_cy - 7)


def _draw_ash_slash_trail(canvas: PixelCanvas, cx: int, head_cy: int, shoulder_y: int, hip_y: int, direction: str, frame: int) -> None:
    if frame not in (1, 2, 3):
        return
    alpha = 150 if frame == 1 else 210
    color = (ASH_PALE[0], ASH_PALE[1], ASH_PALE[2], alpha)
    reach = 7 + frame
    if direction == "right":
        for i in range(3):
            y = shoulder_y + 2 + i * 4
            canvas.draw_line(cx + 9, y, cx + 9 + reach, y - 3, *color)
    elif direction == "left":
        for i in range(3):
            y = shoulder_y + 2 + i * 4
            canvas.draw_line(cx - 9, y, cx - 9 - reach, y - 3, *color)
    elif direction == "down":
        for i in range(3):
            x = cx - 7 + i * 6
            canvas.draw_line(x, hip_y + 3, x + 4, hip_y + 5 + reach // 3, *color)
    else:
        for i in range(3):
            x = cx - 7 + i * 6
            canvas.draw_line(x, head_cy - 4, x + 4, head_cy - 6 - reach // 3, *color)


def _draw_ash_stalker_fallen(canvas: PixelCanvas, cx: int, ground: int, frame: int) -> None:
    if frame == 4:
        # Sinking onto one knee, head bowed, one claw braced on the floor.
        hip_y = ground - 12
        head_cy = hip_y - 14
        canvas.fill_ellipse(cx, head_cy, 6, 6, *ASH_OUTLINE)
        canvas.fill_ellipse(cx, head_cy, 5, 5, *ASH_DARK)
        canvas.fill_rect(cx - 2, head_cy - 1, 4, 1, *ASH_EYE)
        canvas.fill_rect(cx - 2, head_cy + 4, 4, 2, *ASH_MID)
        torso = [(cx - 7, head_cy + 7), (cx + 7, head_cy + 7), (cx + 5, hip_y), (cx - 5, hip_y)]
        canvas.fill_poly(torso, *ASH_MID)
        stroke_poly(canvas, torso, ASH_OUTLINE)
        canvas.draw_line(cx - 6, head_cy + 8, cx - 10, ground - 3, *ASH_MID, thickness=2)
        canvas.draw_line(cx + 5, hip_y, cx + 8, ground - 2, *ASH_DARK, thickness=3)
        canvas.draw_line(cx + 8, ground - 2, cx + 1, ground - 2, *ASH_DARK, thickness=2)
        canvas.draw_line(cx - 4, hip_y, cx - 8, ground - 2, *ASH_DARK, thickness=3)
        canvas.set_pixel(cx - 11, ground - 3, *ASH_PALE)
        canvas.set_pixel(cx - 13, head_cy - 2, *ASH_PALE)
        return

    # Fallen flat, used as the held death frame.
    body_y = ground - 4
    canvas.fill_ellipse(cx, body_y, 12, 4, *ASH_OUTLINE)
    canvas.fill_ellipse(cx, body_y, 11, 3, *ASH_DARK)
    canvas.fill_ellipse(cx + 9, body_y - 3, 5, 4, *ASH_OUTLINE)
    canvas.fill_ellipse(cx + 9, body_y - 3, 4, 3, *ASH_MID)
    canvas.set_pixel(cx + 10, body_y - 4, *ASH_EYE_DARK)
    canvas.draw_line(cx - 4, body_y, cx - 12, body_y + 1, *ASH_DARK, thickness=2)
    canvas.draw_line(cx + 2, body_y - 1, cx + 3, body_y - 7, *ASH_DARK, thickness=2)
    canvas.set_pixel(cx - 9, body_y - 6, *ASH_PALE)
    canvas.set_pixel(cx + 14, body_y - 8, ASH_PALE[0], ASH_PALE[1], ASH_PALE[2], 140)


# --- bog slime ------------------------------------------------------------------------

SLIME_OUTLINE = (26, 34, 20, 255)
SLIME_DARK = (60, 76, 38, 255)
SLIME_MID = (92, 112, 54, 255)
SLIME_LIGHT = (126, 146, 74, 255)
SLIME_TOP = (156, 174, 96, 255)
SLIME_BROWN = (100, 82, 46, 255)
SLIME_MOUTH = (32, 38, 22, 255)
SLIME_EYE = (240, 214, 110, 255)
SLIME_EYE_DARK = (44, 40, 20, 255)
SLIME_SPIT = (204, 222, 142, 255)


def draw_bog_slime_frame(canvas: PixelCanvas, fx: int, fy: int, anim: str, direction: str, frame: int) -> None:
    cx = fx + 32
    ground = fy + 61
    side = side_of(direction)

    if anim == "hurt" and frame >= 4:
        _draw_bog_slime_puddle(canvas, cx, ground, frame)
        return

    lean = 0
    ry = 12
    rx = 15
    lift = 0
    mouth_open = 0
    splashing = 0
    if anim == "walk":
        s = stride_cycle(frame)
        ry = 12 + int(round(s * 3))
        rx = 15 - int(round(s * 3))
        lean = int(round(s * 2)) * side if direction in ("left", "right") else 0
        lift = -1 if s > 0.6 else 0
    elif anim == "slash":
        if frame <= 1:
            ry, rx = 10, 17
        elif frame <= 3:
            ry, rx = 15, 12
            lean = side * 5 if direction in ("left", "right") else 0
            mouth_open = 1
            splashing = 1
        else:
            ry, rx = 11, 16
    elif anim == "hurt":
        ry = 12 - frame
        rx = 16 + frame

    cy = ground - ry + 1 + lift
    bx = cx + lean

    # Spreading base skirt.
    canvas.fill_ellipse(bx, ground - 1, rx + 3, 3, *SLIME_OUTLINE)
    canvas.fill_ellipse(bx, ground - 2, rx + 2, 2, *SLIME_DARK)

    # Main blob with a darker rim and a soft top highlight.
    canvas.fill_ellipse(bx, cy, rx + 1, ry + 1, *SLIME_OUTLINE)
    canvas.fill_ellipse(bx, cy, rx, ry, *SLIME_DARK)
    canvas.fill_ellipse(bx, cy + 1, rx - 1, ry - 1, *SLIME_MID)
    canvas.fill_ellipse(bx - 2, cy - 2, rx - 5, ry - 4, *SLIME_LIGHT)
    canvas.fill_ellipse(bx - 5, cy - 5, 4, 2, *SLIME_TOP)

    # Muddy patches (kept off the face) and trapped bubbles.
    for ox, oy, pr in ((-10, 3, 3), (9, 5, 2), (6, -6, 2)):
        canvas.fill_ellipse(bx + ox, cy + oy, pr, max(pr - 1, 1), *SLIME_BROWN)
    canvas.fill_ellipse(bx + 8, cy - 4, 2, 2, *SLIME_TOP)
    canvas.fill_ellipse(bx - 2, cy + 2, 1, 1, *SLIME_TOP)

    eye_y = cy - 2
    if direction == "up":
        canvas.fill_ellipse(bx, cy - 4, 5, 2, *SLIME_BROWN)
        canvas.set_pixel(bx - 3, cy - 6, *SLIME_TOP)
    else:
        eye_xs = [-5, 5] if direction == "down" else [side * 5]
        for eye_x in eye_xs:
            if anim == "hurt":
                canvas.fill_rect(bx + eye_x - 1, eye_y + 1, 3, 1, *SLIME_EYE)
                canvas.fill_rect(bx + eye_x - 1, eye_y, 3, 1, *SLIME_EYE_DARK)
            else:
                canvas.fill_rect(bx + eye_x - 1, eye_y - 1, 3, 3, *SLIME_EYE_DARK)
                canvas.fill_rect(bx + eye_x - 1, eye_y - 1, 2, 2, *SLIME_EYE)
                canvas.set_pixel(bx + eye_x, eye_y, *SLIME_EYE_DARK)

    if direction != "up":
        mouth_x = bx if direction == "down" else bx + side * 5
        if mouth_open:
            canvas.fill_ellipse(mouth_x, cy + 4, 4, 2, *SLIME_MOUTH)
            canvas.set_pixel(mouth_x - 2, cy + 3, *SLIME_SPIT)
            canvas.set_pixel(mouth_x + 1, cy + 3, *SLIME_SPIT)
        else:
            canvas.fill_rect(mouth_x - 3, cy + 4, 6, 1, *SLIME_MOUTH)

    if splashing:
        for ox, oy in ((side * 13, cy - 9), (-side * 9, cy - 11), (side * 7, ground - 6)):
            canvas.fill_circle(bx + ox, oy, 1, *SLIME_SPIT)
    if anim == "hurt":
        for i in range(3):
            canvas.set_pixel(bx - 13 - frame + i * 3, cy - 6 - frame * 2, *SLIME_LIGHT)
    if anim == "walk" and frame % 3 == 0:
        canvas.set_pixel(bx + rx + 2, ground - 5, *SLIME_LIGHT)


def _draw_bog_slime_puddle(canvas: PixelCanvas, cx: int, ground: int, frame: int) -> None:
    spread = 19 if frame == 4 else 22
    canvas.fill_ellipse(cx, ground - 2, spread + 1, 4, *SLIME_OUTLINE)
    canvas.fill_ellipse(cx, ground - 3, spread, 3, *SLIME_DARK)
    canvas.fill_ellipse(cx, ground - 3, spread - 3, 2, *SLIME_MID)
    canvas.fill_rect(cx - 5, ground - 4, 2, 1, *SLIME_EYE)
    canvas.fill_rect(cx + 4, ground - 4, 2, 1, *SLIME_EYE)
    canvas.fill_ellipse(cx + 8, ground - 3, 3, 1, *SLIME_BROWN)
    canvas.set_pixel(cx - 15, ground - 6, *SLIME_SPIT)
    canvas.set_pixel(cx + 14, ground - 7, *SLIME_SPIT)
    if frame == 4:
        canvas.fill_ellipse(cx - 2, ground - 8, 6, 2, *SLIME_DARK)
        canvas.fill_ellipse(cx - 2, ground - 9, 4, 1, *SLIME_MID)


# --- cinder bat -----------------------------------------------------------------------

BAT_OUTLINE = (44, 18, 14, 255)
BAT_DARK = (116, 42, 26, 255)
BAT_MID = (186, 74, 36, 255)
BAT_LIGHT = (232, 124, 48, 255)
BAT_EMBER = (255, 190, 86, 255)
BAT_MEMBRANE = (150, 50, 30, 255)
BAT_MEMBRANE_DARK = (100, 32, 22, 255)
BAT_EYE = (255, 226, 120, 255)
BAT_EYE_DARK = (46, 18, 10, 255)
BAT_FANG = (252, 244, 226, 255)


def draw_cinder_bat_frame(canvas: PixelCanvas, fx: int, fy: int, anim: str, direction: str, frame: int) -> None:
    cx = fx + 32
    ground = fy + 59
    side = side_of(direction)

    if anim == "hurt" and frame >= 4:
        _draw_cinder_bat_grounded(canvas, cx, ground, frame)
        return

    body_cy = fy + 33
    spread = 20
    wing_dy = 0
    body_shift_y = 0
    sweep = False
    if anim == "walk":
        flap = stride_cycle(frame)
        wing_dy = int(round(-flap * 7))
        body_shift_y = int(round(-flap * 2))
    elif anim == "slash":
        if frame <= 1:
            wing_dy = -8
            body_shift_y = -4
        elif frame <= 3:
            spread = 15
            sweep = True
            body_shift_y = 5
        else:
            wing_dy = 4
    elif anim == "hurt":
        spread = 11 - frame
        wing_dy = 4
        body_shift_y = frame * 3

    body_cy += body_shift_y

    if direction in ("left", "right"):
        _draw_bat_wing(canvas, cx, body_cy, side, spread - 2, wing_dy + 2, sweep, far=True)
        _draw_bat_body(canvas, cx, body_cy, direction, anim, frame)
        _draw_bat_wing(canvas, cx, body_cy, -side, spread, wing_dy, sweep, far=False)
    else:
        _draw_bat_wing(canvas, cx, body_cy, -1, spread, wing_dy, sweep, far=False)
        _draw_bat_wing(canvas, cx, body_cy, 1, spread, wing_dy, sweep, far=False)
        _draw_bat_body(canvas, cx, body_cy, direction, anim, frame)

    _draw_bat_attack_claws(canvas, cx, body_cy, direction, anim, frame)
    _draw_bat_embers(canvas, cx, body_cy, frame, 3 if anim != "hurt" else 5)


def _draw_bat_wing(canvas: PixelCanvas, cx: int, cy: int, s: int, spread: int, tip_dy: int, sweep: bool, far: bool) -> None:
    membrane = BAT_MEMBRANE_DARK if far else BAT_MEMBRANE
    bone = BAT_MID if far else BAT_LIGHT
    if sweep:
        tip = (cx + s * (spread + 1), cy - 2)
        tip2 = (cx + s * (spread - 5), cy + 6)
    else:
        tip = (cx + s * spread, cy - 8 + tip_dy)
        tip2 = (cx + s * (spread - 3), cy + 2 + tip_dy // 2)
    points = [
        (cx + s * 4, cy - 4),
        (cx + s * 7, cy - 7),
        tip,
        tip2,
        (cx + s * 3, cy + 3),
    ]
    canvas.fill_poly(points, *membrane)
    stroke_poly(canvas, points, BAT_OUTLINE)
    canvas.draw_line(cx + s * 6, cy - 5, tip[0], tip[1], *bone)
    canvas.draw_line(cx + s * 6, cy - 5, tip2[0], tip2[1], *bone)


def _draw_bat_body(canvas: PixelCanvas, cx: int, cy: int, direction: str, anim: str, frame: int) -> None:
    side = side_of(direction)
    # Feet.
    canvas.draw_line(cx - 2, cy + 6, cx - 3, cy + 9, *BAT_OUTLINE)
    canvas.draw_line(cx + 2, cy + 6, cx + 3, cy + 9, *BAT_OUTLINE)

    canvas.fill_ellipse(cx, cy, 5, 6, *BAT_OUTLINE)
    canvas.fill_ellipse(cx, cy, 4, 5, *BAT_MID)
    canvas.fill_ellipse(cx, cy + 1, 3, 3, *BAT_LIGHT)
    if direction == "up":
        canvas.draw_line(cx, cy - 3, cx, cy + 3, *BAT_DARK, thickness=2)

    # Head with pointed ears.
    head_cy = cy - 7
    for s in (-1, 1):
        ear = [(cx + s * 2, head_cy - 2), (cx + s * 4, head_cy - 10), (cx + s * 5, head_cy - 1)]
        canvas.fill_poly(ear, *BAT_MID)
        stroke_poly(canvas, ear, BAT_OUTLINE)
    canvas.fill_ellipse(cx, head_cy, 4, 4, *BAT_OUTLINE)
    canvas.fill_ellipse(cx, head_cy, 3, 3, *BAT_MID)
    canvas.fill_ellipse(cx, head_cy + 1, 2, 2, *BAT_LIGHT)

    if direction == "up":
        canvas.draw_line(cx, head_cy - 2, cx, head_cy + 2, *BAT_DARK)
        canvas.set_pixel(cx, cy + 4, *BAT_DARK)
        return

    eye_xs = [-2, 1] if direction == "down" else [side * 2]
    for eye_x in eye_xs:
        canvas.fill_rect(cx + eye_x, head_cy - 1, 1, 2, *BAT_EYE)
        canvas.set_pixel(cx + eye_x, head_cy, *BAT_EYE_DARK)
    if direction == "down":
        canvas.set_pixel(cx - 2, head_cy + 3, *BAT_FANG)
        canvas.set_pixel(cx + 1, head_cy + 3, *BAT_FANG)
    else:
        canvas.set_pixel(cx + side * 3, head_cy + 2, *BAT_FANG)
    if anim == "slash" and frame <= 3:
        canvas.set_pixel(cx - 3, head_cy + 4, *BAT_EMBER)
        canvas.set_pixel(cx + 3, head_cy + 4, *BAT_EMBER)


def _draw_bat_attack_claws(canvas: PixelCanvas, cx: int, cy: int, direction: str, anim: str, frame: int) -> None:
    if anim != "slash" or not (2 <= frame <= 3):
        return
    side = side_of(direction)
    if direction == "down":
        for i in (-2, 0, 2):
            canvas.draw_line(cx + i, cy + 7, cx + i, cy + 9, *BAT_FANG)
    elif direction == "up":
        for i in (-2, 0, 2):
            canvas.draw_line(cx + i, cy - 15, cx + i, cy - 17, *BAT_FANG)
    else:
        for i in (-2, 0, 2):
            canvas.draw_line(cx + side * 7, cy - 2 + i, cx + side * 9, cy - 2 + i, *BAT_FANG)
    # Swoosh streaks behind the dive.
    trail = BAT_EMBER[0], BAT_EMBER[1], BAT_EMBER[2], 170
    if direction == "down":
        canvas.draw_line(cx - 8, cy - 14, cx - 11, cy - 18, *trail)
        canvas.draw_line(cx + 7, cy - 13, cx + 10, cy - 17, *trail)
    elif direction == "up":
        canvas.draw_line(cx - 8, cy + 8, cx - 10, cy + 12, *trail)
        canvas.draw_line(cx + 7, cy + 8, cx + 9, cy + 12, *trail)
    else:
        canvas.draw_line(cx - side * 12, cy - 5, cx - side * 17, cy - 7, *trail)
        canvas.draw_line(cx - side * 12, cy + 3, cx - side * 16, cy + 5, *trail)


def _draw_bat_embers(canvas: PixelCanvas, cx: int, cy: int, frame: int, count: int) -> None:
    drift = frame % 3
    for i in range(count):
        ox = (i * 5) % 7 - 3 + drift - 1
        oy = 10 + i * 3
        color = BAT_EMBER if i == 0 else BAT_LIGHT
        alpha = 220 - i * 45
        canvas.set_pixel(cx + ox, cy + oy, color[0], color[1], color[2], alpha)


def _draw_cinder_bat_grounded(canvas: PixelCanvas, cx: int, ground: int, frame: int) -> None:
    if frame == 4:
        # Wings folding as the body hits the floor.
        body_y = ground - 7
        _draw_bat_wing(canvas, cx, body_y, -1, 11, 3, False, far=False)
        _draw_bat_wing(canvas, cx, body_y, 1, 11, 3, False, far=False)
        canvas.fill_ellipse(cx, body_y, 6, 4, *BAT_OUTLINE)
        canvas.fill_ellipse(cx, body_y, 5, 3, *BAT_MID)
        canvas.fill_ellipse(cx - 3, body_y - 3, 4, 3, *BAT_OUTLINE)
        canvas.fill_ellipse(cx - 3, body_y - 3, 3, 2, *BAT_MID)
        canvas.set_pixel(cx - 4, body_y - 3, *BAT_EYE)
        _draw_bat_embers(canvas, cx, body_y, frame, 3)
        return

    # Crumpled on the dungeon floor, used as the held death frame.
    canvas.fill_ellipse(cx, ground - 3, 11, 4, *BAT_OUTLINE)
    canvas.fill_ellipse(cx, ground - 3, 10, 3, *BAT_MEMBRANE_DARK)
    canvas.fill_ellipse(cx, ground - 4, 4, 3, *BAT_MID)
    canvas.draw_line(cx - 9, ground - 4, cx - 16, ground - 2, *BAT_OUTLINE)
    canvas.draw_line(cx + 9, ground - 4, cx + 16, ground - 2, *BAT_OUTLINE)
    canvas.fill_ellipse(cx - 8, ground - 5, 4, 3, *BAT_OUTLINE)
    canvas.fill_ellipse(cx - 8, ground - 5, 3, 2, *BAT_MID)
    canvas.set_pixel(cx - 9, ground - 5, *BAT_EYE_DARK)
    for ox, oy in ((-16, -7), (14, -10), (2, -11), (-4, -15)):
        canvas.set_pixel(cx + ox, ground + oy, *BAT_EMBER)


# --- sheet generation -----------------------------------------------------------------

DRAWERS = {
    "ash_stalker": draw_ash_stalker_frame,
    "bog_slime": draw_bog_slime_frame,
    "cinder_bat": draw_cinder_bat_frame,
}

## Same sheet shape as the placeholder art: 13 frame columns and 21 rows (up to the hurt
## row). The idle rows (21-24) stay outside the sheet on purpose, so CharacterAppearance
## fills them from walk frame 0 (layout "idle.fallback").
SHEET_COLS = 13
SHEET_ROWS = 21


def generate_sheet(layout: dict, drawer) -> PixelCanvas:
    frame_w = int(layout.get("frame_width", 64))
    frame_h = int(layout.get("frame_height", 64))
    canvas = PixelCanvas(SHEET_COLS * frame_w, SHEET_ROWS * frame_h)

    for anim_name, anim_data in layout.get("animations", {}).items():
        if anim_data.get("source_anim"):
            continue  # alias (death -> hurt) reuses the source rows
        frame_count = int(anim_data.get("frame_count", 1))
        row_to_dirs = {}
        for direction, row_idx in anim_data.get("rows", {}).items():
            row_to_dirs.setdefault(int(row_idx), []).append(direction)
        for row_idx, dirs in row_to_dirs.items():
            direction = "down" if "down" in dirs else dirs[0]
            fy = row_idx * frame_h
            for frame in range(frame_count):
                drawer(canvas, frame * frame_w, fy, anim_name, direction, frame)
    return canvas


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate the Floor 1 enemy sprite sheets.")
    parser.add_argument(
        "--enemies",
        default="",
        help="Comma-separated enemy ids to regenerate (default: every enemy with a drawer).",
    )
    args = parser.parse_args()
    only = {x.strip() for x in args.enemies.split(",") if x.strip()}

    script_dir = os.path.dirname(os.path.abspath(__file__))
    root_dir = os.path.dirname(script_dir)
    with open(os.path.join(root_dir, "data", "sprites", "layout.json"), "r", encoding="utf-8") as f:
        layout = json.load(f)

    for enemy_id, drawer in DRAWERS.items():
        if only and enemy_id not in only:
            continue
        canvas = generate_sheet(layout, drawer)
        out_path = os.path.join(root_dir, "assets", "characters", enemy_id, "body.png")
        write_png(out_path, canvas.width, canvas.height, canvas.data)
        print(f"Generated {out_path} ({canvas.width}x{canvas.height})")


if __name__ == "__main__":
    sys.exit(main())
