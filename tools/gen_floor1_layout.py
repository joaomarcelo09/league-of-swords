#!/usr/bin/env python3
"""
tools/gen_floor1_layout.py

Generates the Floor 1 chunk grid: data/zones/floor1/world.json plus one zone
pair (<stem>.map + <stem>.json) per chunk.

Layout (see .team/plans/floor1-layout-sketch.md):
  - 9x4 chunks of 32x32 tiles = 288x128 tiles.
  - Outer boundary of the whole map is wall, with slightly rounded corners.
  - City (safe zone, town_floor) = circle centred at (96, 64), outer radius
    61 tiles (diameter ~122), ringed by a 3 tile thick wall with an 8 tile
    wide gate on its west and east side.
  - Central hub (hub_floor) plus four 8 tile wide roads (road) reaching the
    wall, and a diamond tower at the exact centre (JGT-134).
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

# City circle (tile units, measured on tile centres). Centred at (96, 64),
# outer radius 61 tiles (diameter ~122), ringed by a 3 tile thick wall. Pinned
# to the city's original absolute position: the east plains columns (JGT-132)
# grow the map but must not move the fountain, houses, merchant, torches or the
# floor1_x2_y1 start chunk. Do not derive this from WIDTH.
CITY_CX = 96.0
CITY_CY = HEIGHT / 2.0  # 64
CITY_RADIUS = 61.0  # outer edge of the city wall ring
CITY_FLOOR_RADIUS = 58.0  # inner edge of the wall ring (town floor is inside)
GATE_ROW_MIN = 60  # west/east gate openings: rows 60..67, centred on y = 64
GATE_ROW_MAX = 67
HOUSE_ANCHOR = (96, 61)  # keeps every house on its original absolute tile
HOUSE_MAX_CITY_DIST = 50.0  # houses stay at least 8 tiles inside the floor edge
RIM_TORCH_RADIUS = 54.0  # torch ring just inside the wall
RIM_TORCH_GATE_CLEARANCE = 6  # keep rim torches this far (in y) off the gate rows

# Central hub, diamond tower and the four roads out to the city wall (JGT-134).
# The hub diameter is 22% of the city diameter, so the radius ratio is the same.
HUB_RADIUS = CITY_RADIUS * 0.22  # ~13.4 tiles
ROAD_WIDTH = 8  # matches the 8 tile gates: E/W rows 60..67, N/S columns 92..99
ROAD_X_MIN = int(CITY_CX - ROAD_WIDTH / 2)  # 92
ROAD_Y_MIN = int(CITY_CY - ROAD_WIDTH / 2)  # 60
TOWER_RADIUS = 3.0  # Manhattan diamond half-diagonal around the exact city centre

# Rounded corners of the outer wall (radius in tiles).
CORNER_RADIUS = 6

SEED = 20261116
DEFAULT_OUT_DIR = os.path.join("data", "zones", "floor1")

# Plaza, merchant and entry, as world tiles.
FOUNTAIN = (93, 60)  # top-left of a 2x2 fountain, clear of the central tower
ENTRY = (93, 58)
MERCHANT_TILE = (90, 60)
MERCHANT = {"id": "floor1_city_merchant", "kind": "merchant", "name": "Merchant Tavi"}
BARREL = (89, 58)
CRATE = (89, 62)
PLAZA_TORCHES = [(92, 56), (99, 56), (92, 65), (99, 65)]
RIM_TORCH_COUNT = 12

# Houses (JGT-123): multi-tile footprints (8x6 and 7x5) assembled from roof,
# wall, window and door parts. Offsets are top-left tiles from the city centre;
# doors always face south onto open town floor. Rows leave room for the wider
# footprints and the one tile door approach between them.
HOUSE_SIZES = [(8, 6), (7, 5)]
HOUSE_ROWS = [
    (-24, [-26, -17, -8, 3, 14, 25]),
    (-16, [-28, -18, -8, 2, 12, 22]),
    (10, [-29, -20, -9, 2, 13, 23]),
    (18, [-29, -19, -8, 3, 12, 22]),
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

# Shop parts (JGT-136): flat parapet with a hanging sign band, striped market
# awning, wide display window and a warm honey-timber wall. Footprints are 8x5
# or 7x5; only the door cell is walkable and the door faces south onto a road
# or open town floor.
SHOP_SIZES = [(8, 5), (7, 5)]
SHOP_PART_CHARS = {
    "m": {
        "parapet_l": "j", "parapet_m": "k", "parapet_r": "l",
        "awning_l": "m", "awning_m": "n", "awning_r": "p",
        "wall": "q", "window": "r", "door": "s",
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
SPAWN_MIN_CITY_DIST = CITY_RADIUS + 3.0  # keep spawns off the city wall
SPAWN_MIN_SPACING = 6

LEGEND = {
    "#": {"type": "wall", "walkable": False},
    ".": {"type": "grass", "walkable": True},
    ",": {"type": "grass", "walkable": True, "decor": "grass_tuft"},
    "T": {"type": "town_floor", "walkable": True, "safe": True},
    "o": {"type": "hub_floor", "walkable": True, "safe": True},
    "R": {"type": "road", "walkable": True, "safe": True},
    "X": {"type": "hub_floor", "walkable": False, "safe": True, "decor": "tower"},
    "H": {"type": "town_floor", "walkable": False, "safe": True, "decor": "house"},
    "F": {"type": "hub_floor", "walkable": False, "safe": True, "decor": "fountain"},
    "t": {"type": "town_floor", "walkable": False, "safe": True, "decor": "torch"},
    "u": {"type": "hub_floor", "walkable": False, "safe": True, "decor": "torch"},
    "B": {"type": "hub_floor", "walkable": False, "safe": True, "decor": "barrel"},
    "K": {"type": "hub_floor", "walkable": False, "safe": True, "decor": "crate"},
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
# Shop parts are decor cells on town floor too; only the door cell is walkable.
for _variant, _parts in SHOP_PART_CHARS.items():
    for _part, _char in _parts.items():
        LEGEND[_char] = {
            "type": "town_floor",
            "walkable": _part == "door",
            "safe": True,
            "decor": "shop_%s" % _part,
        }
WALKABLE = {ch for ch, entry in LEGEND.items() if entry["walkable"]}


def city_dist(x: int, y: int) -> float:
    """Distance in tiles of a tile centre from the city centre."""
    return math.hypot(x + 0.5 - CITY_CX, y + 0.5 - CITY_CY)


def in_city(x: int, y: int) -> bool:
    """True inside the city wall (town floor plus the wall ring)."""
    return city_dist(x, y) <= CITY_RADIUS


def on_city_floor(x: int, y: int) -> bool:
    """True on the town floor inside the city wall."""
    return city_dist(x, y) <= CITY_FLOOR_RADIUS


def on_city_wall(x: int, y: int) -> bool:
    """True on the 3 tile thick wall that rings the city floor."""
    return CITY_FLOOR_RADIUS < city_dist(x, y) <= CITY_RADIUS


def on_hub(x: int, y: int) -> bool:
    """True on the circular central plaza."""
    return city_dist(x, y) <= HUB_RADIUS


def on_tower(x: int, y: int) -> bool:
    """True on the diamond tower footprint, centred on the exact city centre."""
    return abs(x + 0.5 - CITY_CX) + abs(y + 0.5 - CITY_CY) <= TOWER_RADIUS


def on_road(x: int, y: int) -> bool:
    """True on one of the four straight roads from the hub edge to the city wall.

    The east/west roads run through the gate openings; the north/south roads
    stop at the inner edge of the wall ring.
    """
    dx = x + 0.5 - CITY_CX
    dy = y + 0.5 - CITY_CY
    on_ew_row = ROAD_Y_MIN <= y < ROAD_Y_MIN + ROAD_WIDTH
    on_ns_col = ROAD_X_MIN <= x < ROAD_X_MIN + ROAD_WIDTH
    if on_ew_row and HUB_RADIUS < abs(dx) <= CITY_RADIUS:
        return True
    return on_ns_col and HUB_RADIUS < abs(dy) <= CITY_FLOOR_RADIUS


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
    """Torch posts in a ring just inside the city wall, clear of the gate approaches."""
    tiles = []
    for k in range(RIM_TORCH_COUNT):
        angle = 2.0 * math.pi * k / RIM_TORCH_COUNT
        tx = int(math.floor(CITY_CX + math.cos(angle) * RIM_TORCH_RADIUS))
        ty = int(math.floor(CITY_CY + math.sin(angle) * RIM_TORCH_RADIUS))
        if not in_city(tx, ty):
            continue
        near_gate_rows = GATE_ROW_MIN - RIM_TORCH_GATE_CLEARANCE <= ty <= GATE_ROW_MAX + RIM_TORCH_GATE_CLEARANCE
        on_gate_side = tx < CITY_CX or tx > CITY_CX
        if on_gate_side and near_gate_rows:
            continue
        if on_road(tx, ty):
            continue  # the N/S roads reach the rim torch ring
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
            layout = {
                "dx": dx,
                "dy": dy,
                "w": w,
                "h": h,
                "variant": "a" if (row_idx + col_idx // 2) % 2 == 0 else "b",
                "door_i": door_i,
                "window_i": 1 + door_i % (w - 2),
                "window_row": h - 2,
            }
            if w >= 7:
                # Wider houses get a second window on another wall row.
                layout["window_i2"] = 1 + (door_i + 3) % (w - 2)
                layout["window_row2"] = h - 3
            layouts.append(layout)
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
    if j == house.get("window_row2") and i == house.get("window_i2"):
        return parts["window"]
    return parts["wall"]


def shop_part_char(shop: dict, i: int, j: int) -> str:
    """Legend char for column i / row j of a shop footprint.

    Row 0 is the flat parapet with the hanging sign band (the middle cell),
    row 1 the striped awning, the row above the door holds the display window
    and the bottom row holds the wall with the shop door.
    """
    parts = SHOP_PART_CHARS[shop["variant"]]
    w, h = shop["w"], shop["h"]
    window_i = shop.get("window_i", 1 + shop["door_i"] % (w - 2))
    if j == 0:
        edge = "l" if i == 0 else "r" if i == w - 1 else "m"
        return parts["parapet_" + edge]
    if j == 1:
        edge = "l" if i == 0 else "r" if i == w - 1 else "m"
        return parts["awning_" + edge]
    if j == h - 1 and i == shop["door_i"]:
        return parts["door"]
    if j == h - 2 and i == window_i:
        return parts["window"]
    return parts["wall"]


def place_shop(
    grid: list[list[str]],
    x: int,
    y: int,
    w: int,
    h: int,
    door_i: int,
    variant: str,
) -> dict:
    """Stamp a shop footprint with its door facing south onto a walkable tile.

    The footprint must sit on open city town floor and the tile just below the
    door must be town floor, road or hub floor (T/R/o). Returns the layout dict.
    """
    assert variant in SHOP_PART_CHARS, "unknown shop variant %s" % variant
    assert (w, h) in SHOP_SIZES, "shop size %dx%d is not supported" % (w, h)
    assert 1 <= door_i <= w - 2, "shop door must sit between the corners"
    shop = {
        "x": x,
        "y": y,
        "w": w,
        "h": h,
        "door_i": door_i,
        "variant": variant,
        "window_i": 1 + door_i % (w - 2),
    }
    for j in range(h):
        for i in range(w):
            cx, cy = x + i, y + j
            assert 0 <= cx < WIDTH and 0 <= cy < HEIGHT, "shop %s is outside the map" % str(shop)
            assert on_city_floor(cx, cy), "shop %s must sit inside the city floor" % str(shop)
            assert grid[cy][cx] == "T", "shop %s overlaps a non-town-floor tile" % str(shop)
    ax, ay = x + door_i, y + h
    assert 0 <= ax < WIDTH and 0 <= ay < HEIGHT, "shop %s door approach is outside the map" % str(shop)
    assert grid[ay][ax] in ("T", "R", "o"), "shop %s door must face a walkable tile" % str(shop)
    for j in range(h):
        for i in range(w):
            grid[y + j][x + i] = shop_part_char(shop, i, j)
    return shop


def carve_city_gates(grid: list[list[str]]) -> None:
    """Cut the west and east gate openings through the wall, then post their jambs."""
    for y in range(GATE_ROW_MIN, GATE_ROW_MAX + 1):
        for x in range(WIDTH):
            if on_city_wall(x, y):
                grid[y][x] = "T"
    for y in (GATE_ROW_MIN - 1, GATE_ROW_MAX + 1):
        for x in range(WIDTH):
            if on_city_wall(x, y):
                grid[y][x] = "P"


def paint_city_center(grid: list[list[str]]) -> None:
    """Stamp the central hub, its four roads and the diamond tower."""
    for y in range(HEIGHT):
        for x in range(WIDTH):
            if on_hub(x, y):
                grid[y][x] = "o"
            elif on_road(x, y):
                grid[y][x] = "R"
    for y in range(HEIGHT):
        for x in range(WIDTH):
            if on_tower(x, y):
                grid[y][x] = "X"


def build_world(rng: random.Random) -> list[list[str]]:
    grid = [["." for _ in range(WIDTH)] for _ in range(HEIGHT)]
    for y in range(HEIGHT):
        for x in range(WIDTH):
            if is_outer_wall(x, y):
                grid[y][x] = "#"
            elif on_city_floor(x, y):
                grid[y][x] = "T"
            elif on_city_wall(x, y):
                grid[y][x] = "#"
            elif rng.random() < 0.05:
                grid[y][x] = ","
    carve_city_gates(grid)
    paint_city_center(grid)

    # Houses (JGT-123): bigger footprints assembled from roof/wall/window/door parts.
    icx, icy = HOUSE_ANCHOR
    reserved = reserved_tiles()
    houses = []
    for layout in house_layouts():
        hx, hy = icx + layout["dx"], icy + layout["dy"]
        w, h = layout["w"], layout["h"]
        # Keep the hub and the roads clear (JGT-134 will rebuild these houses).
        if any(
            on_hub(hx + i, hy + j) or on_road(hx + i, hy + j)
            for j in range(-1, h + 1)
            for i in range(-1, w + 1)
        ):
            continue
        cells = [(hx + i, hy + j) for j in range(h) for i in range(w)]
        assert all(city_dist(cx, cy) <= HOUSE_MAX_CITY_DIST for cx, cy in cells), "house %s outside the city core" % str(layout)
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
        assert on_city_floor(approach[0], approach[1]), "house %s door faces open town floor" % str(house)
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
        grid[ty][tx] = "u"

    # Torch posts in a ring just inside the city wall.
    for tx, ty in rim_torches():
        grid[ty][tx] = "t"

    for x in range(GATE_X0 - 1, GATE_X0 + GATE_W + 1):
        grid[GATE_Y][x] = "P" if x in (GATE_X0 - 1, GATE_X0 + GATE_W) else "G"

    for x, y in (ENTRY, MERCHANT_TILE):
        assert grid[y][x] == "o", "entry/merchant must be on open hub floor"
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
            if city_dist(x, y) < SPAWN_MIN_CITY_DIST:
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
