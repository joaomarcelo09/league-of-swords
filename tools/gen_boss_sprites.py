#!/usr/bin/env python3
"""
tools/gen_boss_sprites.py

Procedurally draws the original sprite sheets for the Floor 1 boss, Gorvak the Ashen
Warden (enemy id thornback_warden): a huge top-heavy beast that is part boar and part
salamander. Phase 1 carries a stone war pick (right hand) and a round targe (left);
phase 2 drops the targe and grips a huge curved cleaver.

The sheets use data/sprites/layout_thornback_warden.json (96px frames, walk rows 8-11,
slash rows 12-15, hurt row 20) and are written to:
  assets/characters/thornback_warden/body.png              - the beast and its clothing
  assets/characters/thornback_warden/weapon.png            - phase 1: war pick + targe
  assets/characters/thornback_warden/weapon_phase2.png     - phase 2: cleaver, no targe

Both held items live on the weapon layer so the targe can vanish in phase 2 (see
WEAPON_SETS); the body is identical in both phases.
Art is original pixel art drawn by this script; no third-party assets. Python standard
library only - the PNG writer and Canvas come from the other generator tools.
"""

import argparse
import json
import math
import os
import sys

# Keep the tools/ folder free of __pycache__ when this script imports the helpers.
sys.dont_write_bytecode = True

from gen_placeholder_sprites import write_png
from gen_enemy_sprites import PixelCanvas, stroke_poly, stride_cycle, side_of


# --- palette --------------------------------------------------------------------------

OUTLINE = (34, 24, 20, 255)
SKIN_DARK = (132, 62, 30, 255)
SKIN_MID = (172, 88, 42, 255)
SKIN_LIGHT = (204, 118, 56, 255)

HEAD_DARK = (52, 50, 56, 255)
HEAD_MID = (78, 76, 84, 255)
HEAD_LIGHT = (104, 102, 110, 255)
SNOUT = (196, 162, 114, 255)
SNOUT_DARK = (158, 124, 80, 255)
TUSK = (238, 226, 196, 255)

FIN_EDGE = (66, 62, 66, 255)
FIN_ORANGE = (226, 112, 38, 255)
FIN_ORANGE_LIGHT = (244, 148, 60, 255)

OLIVE = (104, 110, 52, 255)
OLIVE_DARK = (72, 78, 36, 255)
WRAP = (70, 48, 34, 255)
WRAP_LIGHT = (98, 68, 46, 255)

BELT = (34, 82, 82, 255)
CREAM = (224, 208, 166, 255)
CRIMSON = (126, 28, 40, 255)
CRIMSON_DARK = (88, 18, 28, 255)
CRIMSON_LIGHT = (162, 44, 52, 255)
GOLD = (226, 178, 64, 255)
GOLD_DARK = (170, 126, 42, 255)

IRON = (112, 110, 106, 255)
IRON_LIGHT = (150, 148, 142, 255)
IRON_DARK = (74, 72, 70, 255)
WOOD = (126, 82, 44, 255)
WOOD_DARK = (94, 58, 34, 255)
STONE = (132, 130, 126, 255)
STONE_LIGHT = (166, 164, 158, 255)
STONE_DARK = (92, 90, 88, 255)
HAFT = (68, 44, 30, 255)
HAFT_LIGHT = (98, 64, 42, 255)
# Phase 2 cleaver: a bronze-grey blade with a near-black cutting edge, plain iron guard
# and a cream-wrapped grip.
CLEAVER_BLADE = (150, 138, 112, 255)
CLEAVER_BLADE_LIGHT = (196, 182, 148, 255)
CLEAVER_BLADE_DARK = (104, 94, 76, 255)
CLEAVER_EDGE = (48, 44, 42, 255)
CLEAVER_GUARD = (86, 82, 78, 255)
CLEAVER_GRIP = (228, 212, 170, 255)
CLEAVER_GRIP_DARK = (156, 132, 94, 255)
EYE = (246, 172, 62, 255)
EYE_DARK = (40, 24, 12, 255)
CLAW = (218, 208, 186, 255)

# Ground line inside a 96px frame; with sprite_offset [0, -41] the feet land on the
# entity (tile centre) position. Keep in sync with layout_thornback_warden.json.
GROUND_Y = 89


# --- small drawing helpers ------------------------------------------------------------


def _outlined_ellipse(canvas: PixelCanvas, cx: float, cy: float, rx: float, ry: float, fill: tuple) -> None:
    canvas.fill_ellipse(cx, cy, rx + 1, ry + 1, *OUTLINE)
    canvas.fill_ellipse(cx, cy, rx, ry, *fill)


def _thick_curve(canvas: PixelCanvas, points: list, color: tuple, thickness: int) -> None:
    for i in range(len(points) - 1):
        x1, y1 = points[i]
        x2, y2 = points[i + 1]
        canvas.draw_line(int(x1), int(y1), int(x2), int(y2), *color, thickness=thickness)


def _tapered_curve(canvas: PixelCanvas, points: list, color: tuple, width_start: float, width_end: float) -> None:
    """Thick curve that narrows from start to end, with a one-pixel dark outline."""
    steps = 5
    total = (len(points) - 1) * steps
    samples = []
    for i in range(total + 1):
        seg = min(i // steps, len(points) - 2)
        t = (i % steps) / float(steps) if i < total else 1.0
        x = points[seg][0] + (points[seg + 1][0] - points[seg][0]) * t
        y = points[seg][1] + (points[seg + 1][1] - points[seg][1]) * t
        width = width_start + (width_end - width_start) * (i / float(total))
        samples.append((x, y, width))
    for x, y, width in samples:
        canvas.fill_circle(int(round(x)), int(round(y)), int(round(width)) + 1, *OUTLINE)
    for x, y, width in samples:
        canvas.fill_circle(int(round(x)), int(round(y)), max(int(round(width)), 1), *color)


def _fill_outlined_poly(canvas: PixelCanvas, points: list, fill: tuple, outline: tuple = OUTLINE) -> None:
    canvas.fill_poly(points, *fill)
    stroke_poly(canvas, points, outline)


def _claw(canvas: PixelCanvas, x: float, y: float, side: int, length: int = 3) -> None:
    canvas.draw_line(int(x), int(y), int(x + side), int(y + length), *CLAW)


# --- pose -----------------------------------------------------------------------------


def _pose(anim: str, frame: int) -> dict:
    """Frame state shared by the body and the weapon layer so the pick stays in the hand."""
    pose = {
        "bob": 0,
        "lean": 0,
        "stride": 0,
        "pick_shift": (0, 0),
        "pick_angle": -100.0,
        "trail": False,
        "fallen": False,
    }
    if anim == "walk":
        s = stride_cycle(frame)
        pose["stride"] = int(round(s * 4))
        pose["bob"] = -1 if abs(s) > 0.6 else 0
        pose["pick_shift"] = (int(round(s * 2)), int(round(-s * 2)))
        pose["pick_angle"] = -100.0 + s * 5.0
    elif anim == "slash":
        # Wind up over the shoulder, sweep the pick across, then settle back.
        table = [
            ((-2, -2), -124.0, False),
            ((-5, -9), -154.0, False),
            ((4, -2), -22.0, True),
            ((9, 5), 34.0, True),
            ((6, 3), 58.0, False),
            ((1, 0), -96.0, False),
        ]
        shift, angle, trail = table[min(frame, len(table) - 1)]
        pose["pick_shift"] = shift
        pose["pick_angle"] = angle
        pose["trail"] = trail
        pose["bob"] = -1 if frame <= 1 else (1 if frame <= 3 else 0)
        pose["lean"] = -2 if frame <= 1 else (2 if frame <= 3 else 0)
        pose["stride"] = 2 if 2 <= frame <= 3 else 0
    elif anim == "hurt":
        pose["bob"] = -2 if frame in (1, 2) else (-1 if frame == 0 else 0)
        pose["lean"] = -2 if frame <= 2 else 0
        pose["stride"] = -2 if frame in (1, 2) else 0
        pose["fallen"] = frame >= 4
    return pose


def _hand_points(direction: str, pose: dict, cx: int, fy: int) -> tuple:
    """Screen positions of the pick hand (right) and targe hand (left)."""
    side = side_of(direction)
    bob = pose["bob"]
    shift_x, shift_y = pose["pick_shift"]
    if direction in ("left", "right"):
        pick = (cx + side * 9 + side * shift_x, fy + 65 + bob + shift_y)
        targe = (cx - side * 13, fy + 64 + bob)
    else:
        pick_side = -1 if direction == "down" else 1
        pick = (cx + pick_side * 17 + shift_x, fy + 66 + bob + shift_y)
        targe = (cx - pick_side * 17, fy + 66 + bob)
    return pick, targe


def _pick_angle(direction: str, pose: dict) -> float:
    angle = pose["pick_angle"]
    if direction in ("left", "up"):
        angle = 180.0 - angle
    return angle


# --- body: clothing and limbs ---------------------------------------------------------


def _draw_tail(canvas: PixelCanvas, cx: int, body_cx: int, hip_y: int, ground: int, direction: str) -> None:
    if direction == "down":
        points = [(body_cx + 6, hip_y - 1), (cx + 18, ground - 9), (cx + 27, ground - 11), (cx + 31, ground - 19)]
    elif direction == "up":
        points = [(cx - 2, hip_y - 1), (cx + 7, ground - 8), (cx + 17, ground - 5), (cx + 23, ground - 12)]
    elif direction == "right":
        points = [(cx - 4, hip_y - 1), (cx - 15, ground - 11), (cx - 24, ground - 13), (cx - 28, ground - 21)]
    else:
        points = [(cx + 4, hip_y - 1), (cx + 15, ground - 11), (cx + 24, ground - 13), (cx + 28, ground - 21)]
    _tapered_curve(canvas, points, SKIN_DARK, 5.0, 2.0)
    # Spade-shaped tip and a couple of dorsal ridges.
    tip_x, tip_y = points[-1]
    prev_x, prev_y = points[-2]
    dx, dy = tip_x - prev_x, tip_y - prev_y
    length = max(math.hypot(dx, dy), 1.0)
    nx, ny = -dy / length, dx / length
    spade = [
        (tip_x + dx * 0.55, tip_y + dy * 0.55),
        (tip_x + nx * 3.0, tip_y + ny * 3.0),
        (tip_x - nx * 3.0, tip_y - ny * 3.0),
    ]
    _fill_outlined_poly(canvas, spade, SKIN_DARK)
    for i in range(1, len(points) - 1):
        canvas.set_pixel(int(points[i][0]), int(points[i][1] - 3), *SKIN_LIGHT)


def _draw_leg(canvas: PixelCanvas, hip: tuple, knee: tuple, foot: tuple, ground: int, profile_side: int = 0) -> None:
    # Short, bent legs: a thick thigh and shin with a broad three-toed foot.
    canvas.draw_line(int(hip[0]), int(hip[1]), int(knee[0]), int(knee[1]), *OUTLINE, thickness=10)
    canvas.draw_line(int(knee[0]), int(knee[1]), int(foot[0]), int(foot[1]), *OUTLINE, thickness=9)
    canvas.draw_line(int(hip[0]), int(hip[1]), int(knee[0]), int(knee[1]), *SKIN_DARK, thickness=7)
    canvas.draw_line(int(knee[0]), int(knee[1]), int(foot[0]), int(foot[1]), *SKIN_MID, thickness=6)

    # Dark brown leg wrap around the lower shin, with a lighter lace line.
    for t in (0.55, 0.72):
        wx = knee[0] + (foot[0] - knee[0]) * t
        wy = knee[1] + (foot[1] - knee[1]) * t
        canvas.fill_circle(int(wx), int(wy), 4, *WRAP)
        canvas.set_pixel(int(wx), int(wy), *WRAP_LIGHT)
    canvas.draw_line(int(knee[0]), int(knee[1]), int(foot[0]), int(foot[1]), *WRAP, thickness=2)

    foot_y = ground - 2
    _outlined_ellipse(canvas, foot[0], foot_y, 5, 3, SKIN_DARK)
    if profile_side == 0:
        for toe in (-2, 0, 2):
            canvas.fill_poly(
                [(foot[0] + toe - 1, foot_y + 1), (foot[0] + toe + 1, foot_y + 1), (foot[0] + toe, ground)],
                *CLAW,
            )
    else:
        for toe in (-2, 0, 2):
            canvas.fill_poly(
                [
                    (foot[0] + profile_side * 2, foot_y + toe),
                    (foot[0] + profile_side * 2, foot_y + toe + 2),
                    (foot[0] + profile_side * 5, foot_y + toe + 1),
                ],
                *CLAW,
            )


def _draw_arm(canvas: PixelCanvas, shoulder: tuple, elbow: tuple, hand: tuple, fill: tuple, thickness: int = 7) -> None:
    canvas.draw_line(int(shoulder[0]), int(shoulder[1]), int(elbow[0]), int(elbow[1]), *OUTLINE, thickness=thickness + 2)
    canvas.draw_line(int(elbow[0]), int(elbow[1]), int(hand[0]), int(hand[1]), *OUTLINE, thickness=thickness)
    canvas.draw_line(int(shoulder[0]), int(shoulder[1]), int(elbow[0]), int(elbow[1]), *fill, thickness=thickness)
    canvas.draw_line(int(elbow[0]), int(elbow[1]), int(hand[0]), int(hand[1]), *SKIN_MID, thickness=thickness - 1)


def _draw_hand(canvas: PixelCanvas, hand: tuple) -> None:
    _outlined_ellipse(canvas, hand[0], hand[1], 4, 4, SKIN_MID)
    for claw in (-2, 0, 2):
        _claw(canvas, hand[0] + claw, hand[1] + 3, 0, 2)


def _draw_targe(canvas: PixelCanvas, hand: tuple) -> None:
    x, y = int(hand[0]), int(hand[1])
    canvas.fill_circle(x, y, 9, *OUTLINE)
    canvas.fill_circle(x, y, 8, *IRON_DARK)
    canvas.fill_circle(x, y, 7, *WOOD)
    canvas.fill_circle(x, y, 7, *WOOD)
    # Plank seams and iron rim bands.
    canvas.draw_line(x - 6, y - 3, x - 6, y + 4, *WOOD_DARK)
    canvas.draw_line(x + 2, y - 6, x + 2, y + 5, *WOOD_DARK)
    canvas.draw_line(x - 7, y - 2, x + 7, y - 2, *IRON, thickness=1)
    canvas.fill_circle(x, y, 3, *IRON_DARK)
    canvas.fill_circle(x, y, 2, *IRON)
    canvas.set_pixel(x - 1, y - 1, *IRON_LIGHT)
    canvas.set_pixel(x - 4, y - 5, *CREAM)


def _draw_belt_and_cloth(canvas: PixelCanvas, bx: int, hip_y: int, direction: str, side: int) -> None:
    width = 22 if direction != "up" else 18
    canvas.fill_rect(bx - width // 2 - 1, hip_y - 1, width + 2, 7, *OUTLINE)
    canvas.fill_rect(bx - width // 2, hip_y, width, 5, *BELT)
    canvas.fill_rect(bx - width // 2, hip_y + 3, width, 1, *CREAM)
    canvas.fill_rect(bx - 2, hip_y + 1, 4, 3, *GOLD_DARK)
    canvas.set_pixel(bx, hip_y + 2, *GOLD)

    if direction == "up":
        # Small crimson back flap, mostly hidden by the tail.
        flap = [(bx - 5, hip_y + 5), (bx + 5, hip_y + 5), (bx + 3, hip_y + 11), (bx - 3, hip_y + 11)]
        _fill_outlined_poly(canvas, flap, CRIMSON_DARK)
        return

    front_shift = side * 2 if direction in ("left", "right") else 0
    fx = bx + front_shift
    cloth = [
        (fx - 6, hip_y + 4),
        (fx + 6, hip_y + 4),
        (fx + 5, hip_y + 12),
        (fx, hip_y + 15),
        (fx - 5, hip_y + 12),
    ]
    _fill_outlined_poly(canvas, cloth, CRIMSON)
    canvas.draw_line(fx, hip_y + 6, fx, hip_y + 12, *CRIMSON_DARK)
    canvas.draw_line(fx - 4, hip_y + 6, fx - 3, hip_y + 11, *CRIMSON_LIGHT)


def _draw_emblem(canvas: PixelCanvas, bx: int, y: int) -> None:
    panel = [(bx - 6, y - 4), (bx + 6, y - 4), (bx + 6, y + 3), (bx, y + 7), (bx - 6, y + 3)]
    _fill_outlined_poly(canvas, panel, CRIMSON)
    for i in range(3):
        cy = y - 1 + i * 3
        stroke_poly(canvas, [(bx - 5, cy + 2), (bx, cy - 1), (bx + 5, cy + 2)], GOLD)
        canvas.set_pixel(bx, cy, *GOLD)


# --- body: head -----------------------------------------------------------------------


def _draw_fins(canvas: PixelCanvas, hx: int, hcy: int, direction: str, side: int) -> None:
    if direction in ("left", "right"):
        sides = [-side]
    else:
        sides = [-1, 1]
    for s in sides:
        bases = [(hx + s * 5, hcy - 8), (hx + s * 7, hcy - 2), (hx + s * 7, hcy + 4), (hx + s * 5, hcy + 9)]
        tips = [(hx + s * 20, hcy - 11), (hx + s * 23, hcy - 3), (hx + s * 18, hcy + 6)]
        for i in range(3):
            fin = [bases[i], tips[i], bases[i + 1]]
            _fill_outlined_poly(canvas, fin, FIN_EDGE)
            inner = [
                (bases[i][0] + (tips[i][0] - bases[i][0]) * 0.18, bases[i][1] + (tips[i][1] - bases[i][1]) * 0.18),
                (tips[i][0] - s * 2, tips[i][1] + 1),
                (bases[i + 1][0] + (tips[i][0] - bases[i + 1][0]) * 0.22, bases[i + 1][1] + (tips[i][1] - bases[i + 1][1]) * 0.22),
            ]
            canvas.fill_poly(inner, *FIN_ORANGE)
            canvas.set_pixel(int(tips[i][0]), int(tips[i][1] + 2), *FIN_ORANGE_LIGHT)


def _draw_head(canvas: PixelCanvas, hx: int, hcy: int, direction: str, side: int) -> None:
    _draw_fins(canvas, hx, hcy, direction, side)
    _outlined_ellipse(canvas, hx, hcy, 10, 9, HEAD_MID)
    canvas.fill_ellipse(hx - 3, hcy - 3, 5, 4, *HEAD_LIGHT)
    canvas.fill_ellipse(hx + 3, hcy + 3, 6, 4, *HEAD_DARK)

    if direction == "up":
        # Back of the skull: a ridge of bony scutes, no face.
        canvas.draw_line(hx, hcy - 7, hx, hcy + 7, *HEAD_DARK, thickness=2)
        canvas.draw_line(hx - 4, hcy - 5, hx - 4, hcy + 3, *HEAD_DARK)
        canvas.draw_line(hx + 4, hcy - 5, hx + 4, hcy + 3, *HEAD_DARK)
        for s in (-2, 2):
            canvas.fill_poly([(hx + s - 1, hcy - 9), (hx + s + 1, hcy - 9), (hx + s, hcy - 13)], *HEAD_MID)
            stroke_poly(canvas, [(hx + s - 1, hcy - 9), (hx + s + 1, hcy - 9), (hx + s, hcy - 13)], OUTLINE)
        return

    if direction == "down":
        snout = [(hx - 7, hcy + 4), (hx + 7, hcy + 4), (hx + 6, hcy + 10), (hx - 6, hcy + 10)]
        _fill_outlined_poly(canvas, snout, SNOUT)
        canvas.fill_ellipse(hx, hcy + 6, 5, 2, *SNOUT_DARK)
        canvas.set_pixel(hx - 3, hcy + 6, *OUTLINE)
        canvas.set_pixel(hx + 3, hcy + 6, *OUTLINE)
        canvas.draw_line(hx - 4, hcy + 9, hx + 4, hcy + 9, *SNOUT_DARK)
        for s in (-1, 1):
            canvas.draw_line(hx + s * 5, hcy + 9, hx + s * 9, hcy + 6, *TUSK, thickness=2)
            canvas.draw_line(hx + s * 9, hcy + 6, hx + s * 8, hcy + 2, *TUSK, thickness=1)
            canvas.set_pixel(hx + s * 8, hcy + 1, *TUSK)
        for s in (-1, 1):
            canvas.fill_rect(hx + s * 4 - 1, hcy - 2, 3, 3, *EYE_DARK)
            canvas.fill_rect(hx + s * 4 - 1, hcy - 2, 2, 2, *EYE)
            canvas.set_pixel(hx + s * 4, hcy - 1, *EYE_DARK)
        canvas.draw_line(hx - 7, hcy - 3, hx + 7, hcy - 3, *HEAD_DARK, thickness=2)
        return

    # Profile: snout pushed toward the facing side, one eye, one visible tusk.
    snout = [
        (hx + side * 5, hcy - 3),
        (hx + side * 14, hcy + 1),
        (hx + side * 13, hcy + 6),
        (hx + side * 4, hcy + 7),
    ]
    _fill_outlined_poly(canvas, snout, SNOUT)
    canvas.set_pixel(hx + side * 12, hcy + 2, *OUTLINE)
    canvas.draw_line(hx + side * 4, hcy + 6, hx + side * 12, hcy + 6, *SNOUT_DARK)
    canvas.draw_line(hx + side * 9, hcy + 7, hx + side * 12, hcy + 5, *TUSK, thickness=2)
    canvas.draw_line(hx + side * 12, hcy + 5, hx + side * 11, hcy + 1, *TUSK, thickness=1)
    canvas.fill_rect(hx + side * 4 - 1, hcy - 2, 3, 3, *EYE_DARK)
    canvas.fill_rect(hx + side * 4 - 1, hcy - 2, 2, 2, *EYE)
    canvas.set_pixel(hx + side * 4, hcy - 1, *EYE_DARK)
    canvas.draw_line(hx - side * 2, hcy - 4, hx + side * 7, hcy - 4, *HEAD_DARK, thickness=2)


# --- body: full frame -----------------------------------------------------------------


def _fallen_weapon_points(cx: int, ground: int, frame: int) -> tuple:
    """Pick hand, weapon angle and targe hand for the downed frames of the hurt row."""
    if frame == 4:
        # Sinking onto one knee, still holding pick and targe.
        return (cx + 17, ground - 3), -88.0, (cx + 27, ground - 4)
    # Collapsed: the pick lies flat beside the body and the targe has slipped away.
    return (cx + 20, ground - 3), -8.0, (cx - 30, ground - 5)


def draw_gorvak_frame(body: PixelCanvas, weapon: PixelCanvas, fx: int, fy: int, anim: str, direction: str, frame: int, weapon_drawer=None) -> None:
    if weapon_drawer is None:
        weapon_drawer = _draw_war_pick
    cx = fx + 48
    ground = fy + GROUND_Y
    side = side_of(direction)
    pose = _pose(anim, frame)

    if pose["fallen"]:
        _draw_fallen(body, cx, ground, frame)
        hand, angle, targe_hand = _fallen_weapon_points(cx, ground, frame)
        weapon_drawer(weapon, hand, angle, pose, anim, frame, direction, targe_hand)
        return

    bob = pose["bob"]
    lean = pose["lean"]
    stride = pose["stride"]
    profile = direction in ("left", "right")
    body_cx = cx + lean + (side if profile else 0)

    head_cy = fy + 30 + bob
    hip_y = fy + 73 + bob
    body_hip = hip_y
    pick_hand, targe_hand = _hand_points(direction, pose, cx, fy)
    angle = _pick_angle(direction, pose)

    _draw_tail(body, cx, body_cx, body_hip, ground, direction)

    # Far arm before the torso, near arm after it.
    if profile:
        far_hand = targe_hand
        _draw_arm(
            body,
            (cx - side * 12, fy + 48 + bob),
            (cx - side * 16, fy + 57 + bob),
            far_hand,
            SKIN_DARK,
            6,
        )
    else:
        for s in (-1, 1):
            _draw_arm(
                body,
                (cx + s * 14, fy + 47 + bob),
                (cx + s * 19, fy + 57 + bob),
                (cx + s * 18, fy + 66 + bob),
                SKIN_DARK if (direction == "down" and s == -1) or (direction == "up" and s == 1) else SKIN_MID,
                7,
            )

    # Short bent legs, each foot planted independently on the walk cycle.
    if profile:
        _draw_leg(
            body,
            (cx - side * 2, hip_y - 1),
            (cx - side * 7 - stride, ground - 10),
            (cx - side * 5 - stride, ground - 2),
            ground,
            profile_side=side,
        )
        _draw_leg(
            body,
            (cx + side * 3, hip_y - 1),
            (cx + side * 8 + stride, ground - 10),
            (cx + side * 7 + stride, ground - 2),
            ground,
            profile_side=side,
        )
    else:
        _draw_leg(
            body,
            (body_cx - 8, hip_y - 1),
            (body_cx - 13 + stride, ground - 10),
            (body_cx - 11 + stride, ground - 2),
            ground,
        )
        _draw_leg(
            body,
            (body_cx + 8, hip_y - 1),
            (body_cx + 13 - stride, ground - 10),
            (body_cx + 11 - stride, ground - 2),
            ground,
        )

    # Top-heavy torso: broad shoulders over a round belly.
    chest_rx = 14 if profile else 18
    belly_rx = 12 if profile else 15
    _outlined_ellipse(body, body_cx, fy + 62 + bob, belly_rx, 14, SKIN_MID)
    body.fill_ellipse(body_cx - 4, fy + 57 + bob, belly_rx - 6, 5, *SKIN_LIGHT)
    body.fill_ellipse(body_cx + 4, fy + 69 + bob, belly_rx - 6, 4, *SKIN_DARK)
    _outlined_ellipse(body, body_cx, fy + 47 + bob, chest_rx, 9, SKIN_MID)
    body.fill_ellipse(body_cx - 5, fy + 45 + bob, chest_rx - 7, 3, *SKIN_LIGHT)
    body.fill_ellipse(body_cx + side * 4, fy + 47 + bob, chest_rx - 8, 4, *SKIN_DARK)

    # Bristly boar ridge along the top of the back.
    for i in (-1, 1):
        for j in range(3):
            sx = body_cx + i * (6 + j * 3)
            _claw(body, sx, fy + 42 + bob - j, 0, 2)
            body.set_pixel(sx, fy + 40 + bob - j, *HEAD_DARK)

    _draw_belt_and_cloth(body, body_cx, hip_y, direction, side)
    if direction != "up":
        _draw_emblem(body, body_cx, fy + 50 + bob)

    # Olive neck wrap between torso and skull.
    wrap_y = head_cy + 8
    body.fill_rect(body_cx - 8, wrap_y, 16, 6, *OLIVE_DARK)
    body.fill_rect(body_cx - 7, wrap_y + 1, 14, 3, *OLIVE)
    body.fill_rect(body_cx - 7, wrap_y + 4, 14, 1, *OLIVE_DARK)
    body.fill_rect(body_cx - side * 6, wrap_y + 4, 4, 5, *OLIVE_DARK)
    body.fill_rect(body_cx - side * 6, wrap_y + 4, 3, 4, *OLIVE)

    _draw_head(body, body_cx + (side * 2 if profile else 0), head_cy, direction, side)

    # Near (weapon) arm and both hands.
    if profile:
        _draw_arm(
            body,
            (cx + side * 12, fy + 48 + bob),
            (cx + side * 15, fy + 57 + bob),
            pick_hand,
            SKIN_MID,
            7,
        )
    _draw_hand(body, pick_hand)
    _draw_hand(body, targe_hand)

    weapon_drawer(weapon, pick_hand, angle, pose, anim, frame, direction, targe_hand)


# --- body: hurt/death frames ----------------------------------------------------------


def _draw_fallen(canvas: PixelCanvas, cx: int, ground: int, frame: int) -> None:
    if frame == 4:
        _draw_kneeling(canvas, cx, ground)
        return

    # Collapsed on one side, used as the held death frame.
    _tapered_curve(canvas, [(cx + 10, ground - 6), (cx + 26, ground - 4), (cx + 34, ground - 9)], SKIN_DARK, 5.0, 2.0)
    _outlined_ellipse(canvas, cx, ground - 8, 24, 9, SKIN_MID)
    canvas.fill_ellipse(cx + 2, ground - 12, 16, 5, *SKIN_LIGHT)
    # Splayed legs.
    _draw_leg(canvas, (cx + 8, ground - 9), (cx + 18, ground - 6), (cx + 24, ground - 2), ground)
    _draw_leg(canvas, (cx + 6, ground - 7), (cx + 17, ground - 10), (cx + 27, ground - 6), ground)
    # Head resting on the floor, snout to the near side.
    hx = cx - 20
    _outlined_ellipse(canvas, hx, ground - 9, 10, 8, HEAD_MID)
    snout = [(hx - 6, ground - 6), (hx - 14, ground - 5), (hx - 12, ground - 1), (hx - 4, ground - 2)]
    _fill_outlined_poly(canvas, snout, SNOUT)
    canvas.draw_line(hx - 10, ground - 5, hx - 6, ground - 3, *TUSK, thickness=2)
    canvas.fill_rect(hx - 2, ground - 11, 2, 1, *EYE_DARK)
    # One arm under the body and one flung out.
    _draw_arm(canvas, (cx - 6, ground - 12), (cx - 14, ground - 8), (cx - 18, ground - 4), SKIN_DARK, 6)
    _draw_arm(canvas, (cx + 10, ground - 13), (cx + 20, ground - 10), (cx + 26, ground - 6), SKIN_DARK, 5)
    canvas.set_pixel(cx - 34, ground - 9, *CLAW)
    canvas.set_pixel(cx + 30, ground - 12, *CLAW)


def _draw_kneeling(canvas: PixelCanvas, cx: int, ground: int) -> None:
    hip_y = ground - 14
    head_cy = ground - 31
    _tapered_curve(canvas, [(cx + 8, hip_y), (cx + 20, ground - 8), (cx + 27, ground - 11)], SKIN_DARK, 5.0, 2.0)
    # Braced back leg and forward foot.
    _draw_leg(canvas, (cx - 6, hip_y), (cx - 13, ground - 5), (cx - 16, ground - 2), ground)
    _draw_leg(canvas, (cx + 5, hip_y), (cx + 9, ground - 8), (cx + 12, ground - 2), ground)
    _outlined_ellipse(canvas, cx, hip_y - 4, 14, 11, SKIN_MID)
    _outlined_ellipse(canvas, cx - 1, head_cy + 9, 12, 8, SKIN_MID)
    canvas.fill_ellipse(cx - 4, hip_y - 8, 8, 4, *SKIN_LIGHT)
    # Bowed head and drooping fins.
    _fill_outlined_poly(canvas, [(cx - 14, head_cy - 2), (cx - 19, head_cy - 8), (cx - 8, head_cy - 5)], FIN_EDGE)
    canvas.fill_poly([(cx - 13, head_cy - 2), (cx - 17, head_cy - 7), (cx - 9, head_cy - 4)], *FIN_ORANGE)
    _fill_outlined_poly(canvas, [(cx + 10, head_cy - 3), (cx + 16, head_cy - 8), (cx + 5, head_cy - 5)], FIN_EDGE)
    canvas.fill_poly([(cx + 9, head_cy - 3), (cx + 14, head_cy - 7), (cx + 6, head_cy - 4)], *FIN_ORANGE)
    _outlined_ellipse(canvas, cx - 1, head_cy, 10, 9, HEAD_MID)
    snout = [(cx - 7, head_cy + 4), (cx + 6, head_cy + 4), (cx + 5, head_cy + 10), (cx - 6, head_cy + 10)]
    _fill_outlined_poly(canvas, snout, SNOUT)
    canvas.draw_line(cx - 4, head_cy + 9, cx + 4, head_cy + 9, *SNOUT_DARK)
    canvas.draw_line(cx - 6, head_cy + 8, cx - 9, head_cy + 5, *TUSK, thickness=2)
    canvas.draw_line(cx + 6, head_cy + 8, cx + 9, head_cy + 5, *TUSK, thickness=2)
    canvas.fill_rect(cx - 5, head_cy - 1, 3, 1, *EYE)
    canvas.fill_rect(cx + 3, head_cy - 1, 3, 1, *EYE)
    # One hand braced on the floor, the other still gripping the planted pick.
    _draw_arm(canvas, (cx - 10, head_cy + 8), (cx - 16, ground - 11), (cx - 19, ground - 2), SKIN_MID, 6)
    _draw_hand(canvas, (cx - 19, ground - 2))
    _draw_arm(canvas, (cx + 10, head_cy + 8), (cx + 15, ground - 14), (cx + 17, ground - 3), SKIN_MID, 6)
    _draw_hand(canvas, (cx + 17, ground - 3))


# --- weapon layer ---------------------------------------------------------------------


def _draw_war_pick(canvas: PixelCanvas, hand: tuple, angle: float, pose: dict, anim: str, frame: int, direction: str, targe_hand: tuple) -> None:
    """Phase 1 weapon layer: the war pick and the round targe it is paired with."""
    if pose["trail"]:
        _draw_slash_trail(canvas, hand, angle)
    _draw_pick_at(canvas, hand, angle)
    _draw_targe(canvas, targe_hand)


def _draw_pick_at(canvas: PixelCanvas, hand: tuple, angle: float) -> None:
    rad = math.radians(angle)
    dx, dy = math.cos(rad), math.sin(rad)
    px, py = -dy, dx
    tip = (hand[0] + dx * 25.0, hand[1] + dy * 25.0)

    # Long dark haft, outlined, with grip wraps near the fist.
    canvas.draw_line(int(hand[0]), int(hand[1]), int(tip[0]), int(tip[1]), *OUTLINE, thickness=5)
    canvas.draw_line(int(hand[0]), int(hand[1]), int(tip[0]), int(tip[1]), *HAFT, thickness=3)
    canvas.draw_line(int(hand[0] + dx * 6), int(hand[1] + dy * 6), int(tip[0] - dx * 4), int(tip[1] - dy * 4), *HAFT_LIGHT, thickness=1)
    for t in (3.0, 7.0):
        gx = hand[0] + dx * t
        gy = hand[1] + dy * t
        canvas.draw_line(int(gx - px * 2), int(gy - py * 2), int(gx + px * 2), int(gy + py * 2), *HAFT_LIGHT)

    # Flat grey stone head, a bar across the haft with a hooked spike on one end.
    a = (tip[0] + px * 8.0, tip[1] + py * 8.0)
    b = (tip[0] - px * 8.0, tip[1] - py * 8.0)
    canvas.draw_line(int(a[0]), int(a[1]), int(b[0]), int(b[1]), *OUTLINE, thickness=9)
    canvas.draw_line(int(a[0]), int(a[1]), int(b[0]), int(b[1]), *STONE, thickness=7)
    canvas.draw_line(int(a[0] - px * 2), int(a[1] - py * 2), int(b[0] - px * 2), int(b[1] - py * 2), *STONE_LIGHT, thickness=1)
    canvas.draw_line(int(a[0] + px * 3), int(a[1] + py * 3), int(b[0] + px * 3), int(b[1] + py * 3), *STONE_DARK, thickness=1)
    hook = [
        a,
        (a[0] - dx * 2.0 + px * 3.0, a[1] - dy * 2.0 + py * 3.0),
        (a[0] - dx * 7.0 + px * 2.0, a[1] - dy * 7.0 + py * 2.0),
    ]
    _thick_curve(canvas, hook, OUTLINE, 5)
    _thick_curve(canvas, hook, STONE_DARK, 3)
    canvas.set_pixel(int(hook[-1][0]), int(hook[-1][1]), *STONE_LIGHT)
    # Dark binding where the head meets the haft.
    canvas.draw_line(int(tip[0] - px * 2), int(tip[1] - py * 2), int(tip[0] + px * 2), int(tip[1] + py * 2), *HAFT_LIGHT, thickness=2)


def _draw_slash_trail(canvas: PixelCanvas, hand: tuple, angle: float) -> None:
    for radius, alpha in ((25.0, 110), (30.0, 70)):
        points = []
        for i in range(7):
            a = math.radians(angle - 60.0 + i * 10.0)
            points.append((hand[0] + math.cos(a) * radius, hand[1] + math.sin(a) * radius))
        for i in range(len(points) - 1):
            canvas.draw_line(
                int(points[i][0]),
                int(points[i][1]),
                int(points[i + 1][0]),
                int(points[i + 1][1]),
                232,
                224,
                206,
                alpha,
            )


# --- phase 2: the cleaver -------------------------------------------------------------

# Blade length in frame pixels. Gorvak stands ~72px tall, so the cleaver is nearly as
# long as he is; a few pixels of the strike-frame tip fall outside the 96px cell.
CLEAVER_BLADE_LEN = 42.0
CLEAVER_BLADE_WIDTH = 15.0
# Resting angle per facing: the cleaver is held up and away from the body, clear of
# Gorvak's head, so the whole blade reads inside the 96px cell. Slash frames keep the
# shared swing angles.
CLEAVER_REST_ANGLE = {
    "right": -60.0,
    "left": -120.0,
    "down": -100.0,
    "up": -60.0,
}


def _cleaver_angle(anim: str, direction: str, angle: float) -> float:
    if anim == "slash":
        return angle
    return CLEAVER_REST_ANGLE.get(direction, angle)


def _draw_cleaver(canvas: PixelCanvas, hand: tuple, angle: float, pose: dict, anim: str, frame: int, direction: str, targe_hand: tuple) -> None:
    """Phase 2 weapon layer: the huge curved cleaver in the pick hand, targe dropped."""
    if pose["fallen"]:
        # On one knee it is still gripped; once collapsed it lies beside the body.
        drop_hand = (hand[0] + 4, hand[1]) if frame >= 5 else hand
        drop_angle = -66.0 if frame >= 5 else -88.0
        _draw_cleaver_at(canvas, drop_hand, drop_angle)
        return
    swing_angle = _cleaver_angle(anim, direction, angle)
    if pose["trail"]:
        _draw_cleaver_trail(canvas, hand, swing_angle)
    _draw_cleaver_at(canvas, hand, swing_angle)


def _draw_cleaver_at(canvas: PixelCanvas, hand: tuple, angle: float) -> None:
    rad = math.radians(angle)
    dx, dy = math.cos(rad), math.sin(rad)
    px, py = -dy, dx
    hx, hy = hand

    # Cream-wrapped grip running back through the fist, iron pommel at the butt.
    back = (hx - dx * 8.0, hy - dy * 8.0)
    canvas.draw_line(int(back[0]), int(back[1]), int(hx + dx * 3.0), int(hy + dy * 3.0), *OUTLINE, thickness=5)
    canvas.draw_line(int(back[0]), int(back[1]), int(hx + dx * 3.0), int(hy + dy * 3.0), *CLEAVER_GRIP, thickness=3)
    for t in (-6.0, -3.0, 0.0):
        wx = hx + dx * t
        wy = hy + dy * t
        canvas.draw_line(int(wx - px * 2.0), int(wy - py * 2.0), int(wx + px * 2.0), int(wy + py * 2.0), *CLEAVER_GRIP_DARK)
    canvas.fill_circle(int(back[0]), int(back[1]), 2, *OUTLINE)
    canvas.fill_circle(int(back[0]), int(back[1]), 1, *IRON)

    # Plain iron guard: a short crossbar where the blade meets the grip.
    guard = (hx + dx * 4.0, hy + dy * 4.0)
    canvas.draw_line(int(guard[0] - px * 6.0), int(guard[1] - py * 6.0), int(guard[0] + px * 6.0), int(guard[1] + py * 6.0), *OUTLINE, thickness=5)
    canvas.draw_line(int(guard[0] - px * 5.0), int(guard[1] - py * 5.0), int(guard[0] + px * 5.0), int(guard[1] + py * 5.0), *CLEAVER_GUARD, thickness=3)

    # Broad cleaver blade: a slightly bowed spine, a belly that swells toward the clipped
    # tip, and a sweeping cutting edge on the far side from the grip.
    base = (guard[0] + dx * 1.0, guard[1] + dy * 1.0)
    spine_heel = (base[0] + px * 2.0, base[1] + py * 2.0)
    spine_belly = (
        base[0] + dx * CLEAVER_BLADE_LEN * 0.55 + px * 4.0,
        base[1] + dy * CLEAVER_BLADE_LEN * 0.55 + py * 4.0,
    )
    tip_spine = (
        base[0] + dx * CLEAVER_BLADE_LEN * 0.96 + px * 3.0,
        base[1] + dy * CLEAVER_BLADE_LEN * 0.96 + py * 3.0,
    )
    tip_edge = (
        base[0] + dx * CLEAVER_BLADE_LEN * 1.0 - px * 13.0,
        base[1] + dy * CLEAVER_BLADE_LEN * 1.0 - py * 13.0,
    )
    edge_belly = (
        base[0] + dx * CLEAVER_BLADE_LEN * 0.64 - px * CLEAVER_BLADE_WIDTH,
        base[1] + dy * CLEAVER_BLADE_LEN * 0.64 - py * CLEAVER_BLADE_WIDTH,
    )
    edge_heel = (
        base[0] + dx * CLEAVER_BLADE_LEN * 0.1 - px * 8.0,
        base[1] + dy * CLEAVER_BLADE_LEN * 0.1 - py * 8.0,
    )
    blade = [spine_heel, spine_belly, tip_spine, tip_edge, edge_belly, edge_heel]
    _fill_outlined_poly(canvas, blade, CLEAVER_BLADE)

    # Bronze-grey spine highlight, a wide dark bevel and a near-black cutting edge.
    _thick_curve(canvas, [spine_heel, spine_belly, tip_spine], CLEAVER_BLADE_LIGHT, 2)
    _thick_curve(
        canvas,
        [
            (tip_edge[0] + px * 4.0, tip_edge[1] + py * 4.0),
            (edge_belly[0] + px * 5.0, edge_belly[1] + py * 5.0),
            (edge_heel[0] + px * 3.0, edge_heel[1] + py * 3.0),
        ],
        CLEAVER_BLADE_DARK,
        3,
    )
    _thick_curve(canvas, [tip_edge, edge_belly, edge_heel], CLEAVER_EDGE, 2)
    # Two rivets at the blade root.
    for s in (-1.0, 1.0):
        canvas.set_pixel(int(base[0] + dx * 4.0 + px * s * 2.0), int(base[1] + dy * 4.0 + py * s * 2.0), *IRON_LIGHT)


def _draw_cleaver_trail(canvas: PixelCanvas, hand: tuple, angle: float) -> None:
    for radius, alpha in ((28.0, 110), (34.0, 70)):
        points = []
        for i in range(7):
            a = math.radians(angle - 62.0 + i * 10.5)
            points.append((hand[0] + math.cos(a) * radius, hand[1] + math.sin(a) * radius))
        for i in range(len(points) - 1):
            canvas.draw_line(
                int(points[i][0]),
                int(points[i][1]),
                int(points[i + 1][0]),
                int(points[i + 1][1]),
                232,
                224,
                206,
                alpha,
            )


# --- sheet generation -----------------------------------------------------------------

WEAPON_SETS = {
    "war_pick": _draw_war_pick,
    "cleaver": _draw_cleaver,
}

DRAWERS = {
    "thornback_warden": draw_gorvak_frame,
}

SHEET_COLS = 13
SHEET_ROWS = 21


def _blit(dst: PixelCanvas, src: PixelCanvas, ox: int, oy: int) -> None:
    """Copies the non-transparent pixels of src onto dst at (ox, oy), clipping to dst."""
    for y in range(src.height):
        for x in range(src.width):
            i = (y * src.width + x) * 4
            if src.data[i + 3] > 0:
                dst.set_pixel(ox + x, oy + y, *src.data[i : i + 4])


def generate_sheets(layout: dict, drawer, weapon_drawer=None) -> tuple:
    if weapon_drawer is None:
        weapon_drawer = _draw_war_pick
    frame_w = int(layout.get("frame_width", 96))
    frame_h = int(layout.get("frame_height", 96))
    body = PixelCanvas(SHEET_COLS * frame_w, SHEET_ROWS * frame_h)
    weapon = PixelCanvas(SHEET_COLS * frame_w, SHEET_ROWS * frame_h)

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
                # Draw each frame into its own cell so wide swings never leak into a
                # neighbouring frame or row, then copy it into the stacked sheet.
                frame_body = PixelCanvas(frame_w, frame_h)
                frame_weapon = PixelCanvas(frame_w, frame_h)
                drawer(frame_body, frame_weapon, 0, 0, anim_name, direction, frame, weapon_drawer)
                _blit(body, frame_body, frame * frame_w, fy)
                _blit(weapon, frame_weapon, frame * frame_w, fy)
    return body, weapon


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate the thornback_warden (Gorvak) boss sprite sheets.")
    parser.add_argument("--enemies", default="thornback_warden", help="Enemy id to regenerate (default: thornback_warden).")
    parser.add_argument("--weapon-set", default="war_pick", choices=sorted(WEAPON_SETS.keys()), help="Held weapon layer to draw (default: war_pick).")
    parser.add_argument("--weapon-out", default="weapon.png", help="Weapon sheet filename inside the enemy folder (default: weapon.png).")
    args = parser.parse_args()
    only = {x.strip() for x in args.enemies.split(",") if x.strip()}

    script_dir = os.path.dirname(os.path.abspath(__file__))
    root_dir = os.path.dirname(script_dir)
    with open(os.path.join(root_dir, "data", "sprites", "layout_thornback_warden.json"), "r", encoding="utf-8") as f:
        layout = json.load(f)

    weapon_drawer = WEAPON_SETS[args.weapon_set]
    for enemy_id, drawer in DRAWERS.items():
        if only and enemy_id not in only:
            continue
        body, weapon = generate_sheets(layout, drawer, weapon_drawer)
        out_dir = os.path.join(root_dir, "assets", "characters", enemy_id)
        write_png(os.path.join(out_dir, "body.png"), body.width, body.height, body.data)
        write_png(os.path.join(out_dir, args.weapon_out), weapon.width, weapon.height, weapon.data)
        print(f"Generated {out_dir}/body.png and {args.weapon_out} ({body.width}x{body.height})")


if __name__ == "__main__":
    sys.exit(main())
