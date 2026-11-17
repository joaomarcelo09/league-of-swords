#!/usr/bin/env python3
"""
tools/gen_floor1_layout.py

Generates the Floor 1 chunk grid: data/zones/floor1/world.json plus one zone
pair (<stem>.map + <stem>.json) per chunk.

Layout (see .team/plans/floor1-layout-sketch.md):
  - 9x4 chunks of 32x32 tiles = 288x128 tiles.
  - Outer boundary of the whole map is wall, with slightly rounded corners.
  - City (safe zone, town_floor) = ellipse centred at x=96 / 48% y,
    79x65 tiles, spanning the central chunks.
  - Everything else is open plains (grass) with enemy spawns, including the
    three plains chunk columns east of the city (x6..x8).
Chunks are joined seamlessly: neighbouring chunks share open edges, so the
player walks between them while the chunk loader streams them in; no gate
transitions are needed. The only transition is the boss gate in the south wall.

Uses the Python standard library only. Output is deterministic (seeded).
Run from the repo root: python3 tools/gen_floor1_layout.py
"""

from __future__ import annotations

import argparse
import json
import math
import os
import random
import re

CHUNK = 32
GRID_W = 9
GRID_H = 4
WIDTH = GRID_W * CHUNK  # 288
HEIGHT = GRID_H * CHUNK  # 128

# City ellipse (tile units, measured on tile centres).
# Pinned to the city's original absolute position: the east plains columns
# (JGT-132) grow the map but must not move the fountain, houses, merchant,
# torches or the floor1_x2_y1 start chunk. Do not derive this from WIDTH.
CITY_CX = 96.0
CITY_CY = HEIGHT * 0.48  # 61.44
CITY_RX = 79 / 2.0
CITY_RY = 65 / 2.0

# Rounded corners of the outer wall (radius in tiles).
CORNER_RADIUS = 6

SEED = 20261116
DEFAULT_OUT_DIR = os.path.join("data", "zones", "floor1")

# Plaza, merchant and entry, as world tiles.
FOUNTAIN = (95, 60)  # top-left of a 2x2 fountain
ENTRY = (93, 58)
MERCHANT_TILE = (90, 60)
MERCHANT = {"id": "floor1_city_merchant", "kind": "merchant", "name": "Merchant Tavi"}
BARREL = (89, 58)
CRATE = (89, 62)
PLAZA_TORCHES = [(92, 56), (99, 56), (92, 65), (99, 65)]
RIM_TORCH_COUNT = 12

# Houses (JGT-123): multi-tile footprints (5x4 and 4x3) assembled from roof,
# wall, window and door parts. Offsets are top-left tiles from the city centre;
# doors always face south onto open town floor.
HOUSE_SIZES = [(5, 4), (4, 3)]
HOUSE_ROWS = [
    (-24, [-20, -12, -4, 4, 11]),
    (-16, [-27, -19, -11, -3, 5, 13, 20]),
    (10, [-27, -19, -11, -3, 5, 13, 20]),
    (18, [-20, -12, -4, 4, 11]),
]

# Legend chars per house part. Variant "a" is warm red roof / cream wall,
# variant "b" cool slate roof / sage wall.
HOUSE_PART_CHARS = {
    "a": {
        "ridge_l": "1", "ridge_m": "2", "ridge_r": "3",
        "roof_l": "4", "roof_m": "5", "roof_r": "6",
        "wall": "7", "window": "8", "door": "9",
    },
    "b": {
        "ridge_l": "a", "ridge_m": "b", "ridge_r": "c",
        "roof_l": "d", "roof_m": "e", "roof_r": "f",
        "wall": "g", "window": "h", "door": "i",
    },
}

# Boss gate: an opening in the south outer wall at ~87% x, the only floor exit.
GATE_X0 = 162  # first open gate tile (global x)
GATE_W = 10
GATE_Y = HEIGHT - 1
GATE_DOOR_ZONE = "floor1"  # dungeon zone (placeholder boss room)
GATE_DOOR_TILE = [20, 7]
GATE_RETURN_TILE = [20, 7]  # tile in the dungeon zone that leads back out
GATE_RETURN_DY = 2  # return lands this many tiles north of the gate row

ENEMIES = ["ash_stalker", "bog_slime", "cinder_bat"]
SPAWNS_PER_FULL_CHUNK = 3
RESPAWN_S = 30
SPAWN_MIN_CITY_NORM = 1.3  # keep spawns clear of the city edge
SPAWN_MIN_SPACING = 6

LEGEND = {
    "#": {"type": "wall", "walkable": False},
    ".": {"type": "grass", "walkable": True},
    ",": {"type": "grass", "walkable": True, "decor": "grass_tuft"},
    "T": {"type": "town_floor", "walkable": True, "safe": True},
    "H": {"type": "town_floor", "walkable": False, "safe": True, "decor": "house"},
    "F": {"type": "town_floor", "walkable": False, "safe": True, "decor": "fountain"},
    "t": {"type": "town_floor", "walkable": False, "safe": True, "decor": "torch"},
    "B": {"type": "town_floor", "walkable": False, "safe": True, "decor": "barrel"},
    "K": {"type": "town_floor", "walkable": False, "safe": True, "decor": "crate"},
    "G": {"type": "gate", "walkable": True},
    "P": {"type": "gate_post", "walkable": False},
}
# House parts are decor cells on town floor; only the door cell is walkable.
for _variant, _parts in HOUSE_PART_CHARS.items():
    for _part, _char in _parts.items():
        LEGEND[_char] = {
            "type": "town_floor",
            "walkable": _part == "door",
            "safe": True,
            "decor": "house_%s_%s" % (_variant, _part),
        }
WALKABLE = {ch for ch, entry in LEGEND.items() if entry["walkable"]}


def city_norm(x: int, y: int) -> float:
    """Normalised ellipse distance of a tile centre (<= 1 inside the city)."""
    dx = (x + 0.5 - CITY_CX) / CITY_RX
    dy = (y + 0.5 - CITY_CY) / CITY_RY
    return dx * dx + dy * dy


def in_city(x: int, y: int) -> bool:
    return city_norm(x, y) <= 1.0


def is_outer_wall(x: int, y: int) -> bool:
    """True on the outer wall: the 1-tile border plus the rounded corners."""
    if x <= 0 or y <= 0 or x >= WIDTH - 1 or y >= HEIGHT - 1:
        return True
    # Inside the 1-tile border, round each corner with CORNER_RADIUS.
    r = CORNER_RADIUS
    cx = None
    cy = None
    if x < 1 + r:
        cx = 1 + r
    elif x >= WIDTH - 1 - r:
        cx = WIDTH - 1 - r
    if y < 1 + r:
        cy = 1 + r
    elif y >= HEIGHT - 1 - r:
        cy = HEIGHT - 1 - r
    if cx is None or cy is None:
        return False
    return math.hypot(x + 0.5 - cx, y + 0.5 - cy) > r


def rim_torches() -> list[tuple[int, int]]:
    """Torch posts around the city rim, just inside the ellipse."""
    tiles = []
    for k in range(RIM_TORCH_COUNT):
        angle = 2.0 * math.pi * k / RIM_TORCH_COUNT
        tx = int(math.floor(CITY_CX + math.cos(angle) * (CITY_RX - 2.0)))
        ty = int(math.floor(CITY_CY + math.sin(angle) * (CITY_RY - 2.0)))
        if in_city(tx, ty):
            tiles.append((tx, ty))
    return tiles


def reserved_tiles() -> set[tuple[int, int]]:
    """Plaza props and torch posts that a house must never cover."""
    reserved = {ENTRY, MERCHANT_TILE, BARREL, CRATE}
    for j in range(2):
        for i in range(2):
            reserved.add((FOUNTAIN[0] + i, FOUNTAIN[1] + j))
    reserved.update(PLAZA_TORCHES)
    reserved.update(rim_torches())
    return reserved


def house_layouts() -> list[dict]:
    """Deterministic house placements: size and palette vary row by row."""
    layouts = []
    for row_idx, (dy, xs) in enumerate(HOUSE_ROWS):
        for col_idx, dx in enumerate(xs):
            w, h = HOUSE_SIZES[(row_idx + col_idx) % 2]
            slot = row_idx * 2 + col_idx
            door_i = 1 + slot % (w - 2)
            layouts.append({
                "dx": dx,
                "dy": dy,
                "w": w,
                "h": h,
                "variant": "a" if (row_idx + col_idx // 2) % 2 == 0 else "b",
                "door_i": door_i,
                "window_i": 1 + door_i % (w - 2),
                "window_row": h - 2 if h > 3 else h - 1,
            })
    return layouts


def house_part_char(house: dict, i: int, j: int) -> str:
    """Legend char for column i / row j of a house footprint."""
    parts = HOUSE_PART_CHARS[house["variant"]]
    w, h = house["w"], house["h"]
    if j == 0:
        edge = "l" if i == 0 else "r" if i == w - 1 else "m"
        return parts["ridge_" + edge]
    if j == 1:
        edge = "l" if i == 0 else "r" if i == w - 1 else "m"
        return parts["roof_" + edge]
    if j == h - 1 and i == house["door_i"]:
        return parts["door"]
    if j == house["window_row"] and i == house["window_i"]:
        return parts["window"]
    return parts["wall"]


def build_world(rng: random.Random) -> list[list[str]]:
    grid = [["." for _ in range(WIDTH)] for _ in range(HEIGHT)]
    for y in range(HEIGHT):
        for x in range(WIDTH):
            if is_outer_wall(x, y):
                grid[y][x] = "#"
            elif in_city(x, y):
                grid[y][x] = "T"
            elif rng.random() < 0.05:
                grid[y][x] = ","

    # Houses (JGT-123): bigger footprints assembled from roof/wall/window/door parts.
    icx, icy = int(CITY_CX), int(CITY_CY)
    reserved = reserved_tiles()
    houses = []
    for layout in house_layouts():
        hx, hy = icx + layout["dx"], icy + layout["dy"]
        w, h = layout["w"], layout["h"]
        cells = [(hx + i, hy + j) for j in range(h) for i in range(w)]
        assert all(city_norm(cx, cy) <= 0.8 for cx, cy in cells), "house %s outside the city core" % str(layout)
        houses.append(dict(layout, x=hx, y=hy, cells=cells))

    house_cells: set[tuple[int, int]] = set()
    for house in houses:
        assert house_cells.isdisjoint(house["cells"]), "house %s overlaps another house" % str(house)
        assert reserved.isdisjoint(house["cells"]), "house %s covers a plaza prop" % str(house)
        house_cells.update(house["cells"])

    for house in houses:
        approach = (house["x"] + house["door_i"], house["y"] + house["h"])
        assert approach not in house_cells, "house %s door faces another house" % str(house)
        assert approach not in reserved, "house %s door faces a plaza prop" % str(house)
        assert in_city(approach[0], approach[1]), "house %s door faces open town floor" % str(house)
        for j in range(house["h"]):
            for i in range(house["w"]):
                grid[house["y"] + j][house["x"] + i] = house_part_char(house, i, j)

    fx, fy = FOUNTAIN
    for j in range(2):
        for i in range(2):
            grid[fy + j][fx + i] = "F"
    grid[BARREL[1]][BARREL[0]] = "B"
    grid[CRATE[1]][CRATE[0]] = "K"
    for tx, ty in PLAZA_TORCHES:
        grid[ty][tx] = "t"

    # Torch posts around the city rim, just inside the ellipse.
    for tx, ty in rim_torches():
        grid[ty][tx] = "t"

    for x in range(GATE_X0 - 1, GATE_X0 + GATE_W + 1):
        grid[GATE_Y][x] = "P" if x in (GATE_X0 - 1, GATE_X0 + GATE_W) else "G"

    for x, y in (ENTRY, MERCHANT_TILE):
        assert grid[y][x] == "T", "entry/merchant must be on open town floor"
    return grid


def chunk_id(cx: int, cy: int) -> str:
    return "floor1_x%d_y%d" % (cx, cy)


def zone_stem(cx: int, cy: int) -> str:
    return "chunk_x%d_y%d" % (cx, cy)


def chunk_spawns(grid: list[list[str]], cx: int, cy: int, rng: random.Random) -> list[dict]:
    ox, oy = cx * CHUNK, cy * CHUNK
    entry = chunk_entry(grid, cx, cy)
    candidates = []
    for ly in range(3, CHUNK - 3):
        for lx in range(3, CHUNK - 3):
            x, y = ox + lx, oy + ly
            if [lx, ly] == entry:
                continue  # never spawn an enemy on top of the chunk entry
            if grid[y][x] not in WALKABLE or in_city(x, y):
                continue
            if city_norm(x, y) < SPAWN_MIN_CITY_NORM ** 2:
                continue
            # Keep spawns three tiles off the outer wall.
            if any(
                is_outer_wall(x + dx, y + dy)
                for dx in range(-3, 4)
                for dy in range(-3, 4)
                if 0 <= x + dx < WIDTH and 0 <= y + dy < HEIGHT
            ):
                continue
            candidates.append((lx, ly))
    full = (CHUNK - 6) * (CHUNK - 6)
    count = int(round(SPAWNS_PER_FULL_CHUNK * len(candidates) / full))
    rng.shuffle(candidates)
    picked: list[tuple[int, int]] = []
    for lx, ly in candidates:
        if len(picked) >= count:
            break
        if all(abs(lx - px) + abs(ly - py) >= SPAWN_MIN_SPACING for px, py in picked):
            picked.append((lx, ly))
    picked.sort(key=lambda t: (t[1], t[0]))
    return [
        {"enemy": rng.choice(ENEMIES), "tile": [lx, ly], "respawn_s": RESPAWN_S}
        for lx, ly in picked
    ]


def chunk_entry(grid: list[list[str]], cx: int, cy: int) -> list[int]:
    """Walkable tile closest to the chunk centre (the global entry in its chunk)."""
    ox, oy = cx * CHUNK, cy * CHUNK
    if ox <= ENTRY[0] < ox + CHUNK and oy <= ENTRY[1] < oy + CHUNK:
        return [ENTRY[0] - ox, ENTRY[1] - oy]
    best = None
    for ly in range(CHUNK):
        for lx in range(CHUNK):
            if grid[oy + ly][ox + lx] not in WALKABLE:
                continue
            d = (lx - CHUNK // 2) ** 2 + (ly - CHUNK // 2) ** 2
            if best is None or d < best[0]:
                best = (d, [lx, ly])
    assert best is not None, "chunk without walkable tiles"
    return best[1]


def write_json(path: str, data: dict) -> None:
    with open(path, "w", encoding="utf-8") as f:
        text = json.dumps(data, indent=2)
        # Keep [x, y] pairs on one line, like the hand-written zone files.
        text = re.sub(r"\[\s+(-?\d+),\s+(-?\d+)\s+\]", r"[\1, \2]", text)
        f.write(text + "\n")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[1])
    parser.add_argument("--out-dir", default=DEFAULT_OUT_DIR)
    args = parser.parse_args()

    rng = random.Random(SEED)
    grid = build_world(rng)
    os.makedirs(args.out_dir, exist_ok=True)

    chunks = []
    for cy in range(GRID_H):
        for cx in range(GRID_W):
            ox, oy = cx * CHUNK, cy * CHUNK
            rows = ["".join(grid[oy + ly][ox : ox + CHUNK]) for ly in range(CHUNK)]
            used = sorted({ch for row in rows for ch in row})
            has_city = any(in_city(ox + lx, oy + ly) for ly in range(CHUNK) for lx in range(CHUNK))
            npcs = []
            mx, my = MERCHANT_TILE
            if ox <= mx < ox + CHUNK and oy <= my < oy + CHUNK:
                npcs.append(dict(MERCHANT, tile=[mx - ox, my - oy]))
            zone = {
                "legend": {ch: LEGEND[ch] for ch in used},
                "entry": chunk_entry(grid, cx, cy),
                "npcs": npcs,
                "spawns": chunk_spawns(grid, cx, cy, rng),
                "exits": [],
            }
            stem = zone_stem(cx, cy)
            with open(os.path.join(args.out_dir, stem + ".map"), "w", encoding="utf-8") as f:
                f.write("\n".join(rows) + "\n")
            write_json(os.path.join(args.out_dir, stem + ".json"), zone)
            chunks.append({
                "id": chunk_id(cx, cy),
                "grid": [cx, cy],
                "zone": stem,
                "kind": "city" if has_city else "plains",
            })

    gate_cx, gate_cy = GATE_X0 // CHUNK, GATE_Y // CHUNK
    transitions = []
    for i in range(GATE_W):
        gx = GATE_X0 + i
        assert gx // CHUNK == gate_cx, "gate must sit inside one chunk"
        assert grid[GATE_Y - GATE_RETURN_DY][gx] in WALKABLE, "gate return tile must be walkable"
        transitions.append({
            "id": "boss_gate_%d" % i,
            "kind": "door",
            "from": {"chunk": chunk_id(gate_cx, gate_cy), "tile": [gx % CHUNK, GATE_Y % CHUNK]},
            "to": {"zone": GATE_DOOR_ZONE, "tile": list(GATE_DOOR_TILE)},
            "return": {
                "tile": list(GATE_RETURN_TILE),
                "chunk": chunk_id(gate_cx, gate_cy),
                "to_tile": [gx % CHUNK, (GATE_Y - GATE_RETURN_DY) % CHUNK],
            },
            "label": "Boss Gate",
        })

    world = {
        "chunk_size": [CHUNK, CHUNK],
        "load_radius": 1,
        "chunks": chunks,
        "transitions": transitions,
    }
    write_json(os.path.join(args.out_dir, "world.json"), world)
    ex, ey = ENTRY
    print("start chunk: %s, entry local %s" % (chunk_id(ex // CHUNK, ey // CHUNK), [ex % CHUNK, ey % CHUNK]))


if __name__ == "__main__":
    main()
