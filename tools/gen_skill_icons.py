#!/usr/bin/env python3
"""
tools/gen_skill_icons.py

Procedurally draws the original 32x32 HUD skill icons for every `icon` id used by
data/skills.json (assets/ui/icons/<icon_id>.png).

The art is neutral (light greys plus a dark outline) because HUD draws it tinted by
the colour of the icon's data/icons.json entry. Shapes are original: a crescent
slash, a fiery lance, a mending gust with a leaf, and a shadow-step footprint.
Python standard library only; output is deterministic (no random values).
"""

import argparse
import json
import math
import os
import sys

# Keep the tools/ folder free of __pycache__ when importing the PNG writer.
sys.dont_write_bytecode = True

from gen_placeholder_sprites import Canvas, write_png

ICON_PX = 32

OUTLINE = (26, 28, 38, 255)
SHADOW = (92, 105, 126, 255)
MID = (170, 184, 206, 255)
LIGHT = (226, 234, 248, 255)
WHITE = (255, 255, 255, 255)


class IconCanvas(Canvas):
    """Canvas with antialias-free ellipse, polygon and erase helpers for pixel art."""

    def fill_ellipse(self, cx: float, cy: float, rx: float, ry: float, color: tuple) -> None:
        if rx <= 0 or ry <= 0:
            return
        for py in range(int(round(cy - ry)), int(round(cy + ry)) + 1):
            rel = (py - cy) / ry
            span = rx * math.sqrt(max(0.0, 1.0 - rel * rel))
            for px in range(int(round(cx - span)), int(round(cx + span)) + 1):
                self.set_pixel(px, py, *color)

    def erase_ellipse(self, cx: float, cy: float, rx: float, ry: float) -> None:
        self.fill_ellipse(cx, cy, rx, ry, (0, 0, 0, 0))

    def fill_poly(self, points: list, color: tuple) -> None:
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
                    self.set_pixel(px, py, *color)


def arc_points(cx: float, cy: float, rx: float, ry: float, start_deg: float, end_deg: float, steps: int = 24) -> list:
    points = []
    for i in range(steps + 1):
        angle = math.radians(start_deg + (end_deg - start_deg) * float(i) / float(steps))
        points.append((cx + math.cos(angle) * rx, cy + math.sin(angle) * ry))
    return points


def stroke_poly(canvas: IconCanvas, points: list, color: tuple, thickness: int = 1) -> None:
    count = len(points)
    for i in range(count):
        x1, y1 = points[i]
        x2, y2 = points[(i + 1) % count]
        canvas.draw_line(int(round(x1)), int(round(y1)), int(round(x2)), int(round(y2)), *color, thickness=thickness)


def stroke_arc(canvas: IconCanvas, cx: float, cy: float, rx: float, ry: float, start_deg: float, end_deg: float, color: tuple, thickness: int = 1, steps: int = 24) -> None:
    stroke_poly(canvas, arc_points(cx, cy, rx, ry, start_deg, end_deg, steps), color, thickness)


# --- crescent sweep -------------------------------------------------------------------


def draw_crescent_sweep(canvas: IconCanvas) -> None:
    # A tapered crescent blade (outer arc minus an offset inner arc), opening right.
    outer = arc_points(16.0, 17.0, 12.0, 12.0, 110.0, 300.0, 26)
    inner = arc_points(20.5, 17.0, 10.0, 10.0, 300.0, 110.0, 22)
    crescent = outer + inner
    canvas.fill_poly(crescent, MID)
    stroke_poly(canvas, crescent, OUTLINE)
    # Bright cutting edge along the inner curve.
    stroke_arc(canvas, 20.5, 17.0, 10.0, 10.0, 300.0, 110.0, LIGHT, thickness=1, steps=22)
    # Sweep trails trailing off to the right of the blade.
    for start, end in (
        ((23, 8), (29, 5)),
        ((24, 14), (30, 13)),
        ((23, 21), (29, 23)),
    ):
        canvas.draw_line(start[0], start[1], end[0], end[1], *LIGHT)
    # Two small chips flicked off the cut.
    canvas.set_pixel(25, 3, *WHITE)
    canvas.set_pixel(28, 27, *WHITE)


# --- ember lance ----------------------------------------------------------------------


def draw_ember_lance(canvas: IconCanvas) -> None:
    # Trailing streaks under the lance.
    for start, end in (
        ((4, 29), (11, 23)),
        ((3, 23), (9, 18)),
        ((6, 30), (12, 27)),
    ):
        canvas.draw_line(start[0], start[1], end[0], end[1], *SHADOW)

    # Shaft from the lower-left grip to the upper-right head.
    canvas.draw_line(7, 27, 18, 16, *OUTLINE, thickness=3)
    canvas.draw_line(7, 27, 18, 16, *MID, thickness=1)

    # Spearhead: an elongated triangular point on the shaft's axis.
    head = [(26, 6), (19, 16), (14, 13)]
    canvas.fill_poly(head, MID)
    stroke_poly(canvas, head, OUTLINE)
    canvas.draw_line(24, 8, 19, 14, *LIGHT)

    # Flame tongues licking off the point.
    flame = [(26, 7), (28, 3), (27, 8), (31, 6), (28, 11), (24, 9)]
    canvas.fill_poly(flame, LIGHT)
    stroke_poly(canvas, flame, OUTLINE)
    canvas.set_pixel(23, 5, *WHITE)
    canvas.set_pixel(21, 21, *WHITE)


# --- mending gale ---------------------------------------------------------------------


def draw_mending_gale(canvas: IconCanvas) -> None:
    # Three curling gust arcs wrapping the leaf.
    for cx, cy, rx, ry, start, end, color, thick in (
        (16.0, 15.0, 13.0, 10.0, 200.0, 340.0, SHADOW, 3),
        (16.0, 15.0, 13.0, 10.0, 200.0, 340.0, LIGHT, 1),
        (18.0, 20.0, 10.0, 7.0, 20.0, 160.0, SHADOW, 3),
        (18.0, 20.0, 10.0, 7.0, 20.0, 160.0, MID, 1),
        (13.0, 10.0, 8.0, 6.0, 210.0, 330.0, SHADOW, 3),
        (13.0, 10.0, 8.0, 6.0, 210.0, 330.0, LIGHT, 1),
    ):
        stroke_arc(canvas, cx, cy, rx, ry, start, end, color, thickness=thick)

    # A leaf at the heart of the wind, with a bright midrib.
    leaf = [(16, 25), (11, 20), (12, 14), (17, 10), (22, 15), (20, 21)]
    canvas.fill_poly(leaf, MID)
    stroke_poly(canvas, leaf, OUTLINE)
    canvas.draw_line(16, 23, 16, 13, *LIGHT)
    canvas.draw_line(16, 18, 13, 16, *LIGHT)
    canvas.draw_line(16, 16, 19, 14, *LIGHT)


# --- shadow step ----------------------------------------------------------------------


def draw_shadow_step(canvas: IconCanvas) -> None:
    # Speed lines trailing behind the step.
    for start, end in (
        ((3, 27), (10, 24)),
        ((2, 21), (8, 19)),
        ((5, 30), (12, 29)),
    ):
        canvas.draw_line(start[0], start[1], end[0], end[1], *SHADOW)
        canvas.draw_line(start[0], start[1] - 1, end[0], end[1] - 1, *LIGHT)

    # Two boot prints running up-right, heel first.
    prints = (
        [(8, 25), (13, 26), (18, 21), (17, 17), (14, 18), (11, 21)],
        [(16, 16), (21, 17), (26, 12), (25, 8), (22, 9), (19, 12)],
    )
    for footprint in prints:
        canvas.fill_poly(footprint, MID)
        stroke_poly(canvas, footprint, OUTLINE)
        # Sole highlight.
        canvas.draw_line(footprint[0][0] + 2, footprint[0][1] - 1, footprint[2][0] - 1, footprint[2][1] - 1, *LIGHT)

    # A faint shadow wisp behind the first print.
    canvas.fill_ellipse(6.0, 18.0, 2.0, 1.0, (92, 105, 126, 120))
    canvas.fill_ellipse(9.0, 13.0, 1.0, 1.0, (92, 105, 126, 90))


DRAWERS = {
    "icon_crescent_sweep": draw_crescent_sweep,
    "icon_ember_lance": draw_ember_lance,
    "icon_mending_gale": draw_mending_gale,
    "icon_shadow_step": draw_shadow_step,
}


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate the HUD skill icons.")
    parser.add_argument(
        "--icons",
        default="",
        help="Comma-separated icon ids to regenerate (default: every id used by data/skills.json).",
    )
    args = parser.parse_args()
    only = {x.strip() for x in args.icons.split(",") if x.strip()}

    script_dir = os.path.dirname(os.path.abspath(__file__))
    root_dir = os.path.dirname(script_dir)
    with open(os.path.join(root_dir, "data", "skills.json"), "r", encoding="utf-8") as f:
        skills = json.load(f)

    icon_ids = sorted({str(skill.get("icon", "")).strip() for skill in skills.values()})
    icon_ids = [icon_id for icon_id in icon_ids if icon_id]
    if not icon_ids:
        print("No skill icon ids found in data/skills.json", file=sys.stderr)
        return 1

    missing = [icon_id for icon_id in icon_ids if icon_id not in DRAWERS]
    if missing:
        print("No drawer for skill icon(s): %s" % ", ".join(missing), file=sys.stderr)
        return 1

    for icon_id in icon_ids:
        if only and icon_id not in only:
            continue
        canvas = IconCanvas(ICON_PX, ICON_PX)
        DRAWERS[icon_id](canvas)
        out_path = os.path.join(root_dir, "assets", "ui", "icons", icon_id + ".png")
        write_png(out_path, canvas.width, canvas.height, canvas.data)
        print(f"Generated {out_path} ({canvas.width}x{canvas.height})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
