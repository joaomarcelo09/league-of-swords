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
  - The four quarters between the roads hold mirrored rows of houses and shops,
    each fronted by a two tile alley (JGT-137); the roads are dressed with
    torches, barrels and crates on the town floor beside them.
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
HOUSE_MAX_CITY_DIST = 52.0  # buildings stop short of the floor edge and rim torches
HUB_BUILDING_MARGIN = 1.25  # keep a one tile walkable margin around the hub
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

# Buildings (JGT-123/JGT-137): houses are 8x6 or 7x5 footprints assembled from
# roof, wall, window and door parts; shops are 8x5 or 7x5 (JGT-136). Rows are
# filled from the east/west road outward, every door faces south onto a two tile
# alley and neighbouring footprints keep a one tile gap. The (door row, height
# budget) pairs below start at the road and step north; a 6 row alternates 8x6
# and 7x5 houses, a 5 row stays 7x5. Rows reuse the same mirrored slots, so all
# four quarters hold the same buildings.
HOUSE_SIZES = [(8, 6), (7, 5)]
BUILDING_ROWS = [
    (57, 6),
    (49, 6),
    (41, 6),
    (33, 6),
    (25, 5),
    (18, 5),
]
BUILDING_COLUMNS = 8  # enough slots to reach the western floor edge
SHOP_EVERY = 3  # roughly one shop for every three buildings

# Road dressing: barrels, crates and torches on the town floor beside the roads,
# in mirror pairs so the decoration stays symmetric around the city centre.
ROAD_PROP_CHARS = ["t", "B", "K"]
ROAD_PROP_EW_OFFSETS = [18, 25, 32, 39, 46]
ROAD_PROP_NS_OFFSETS = [27, 34, 41, 48]

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
    # Road-side props stand on town floor; the hub keeps its own letters.
    "B": {"type": "town_floor", "walkable": False, "safe": True, "decor": "barrel"},
    "K": {"type": "town_floor", "walkable": False, "safe": True, "decor": "crate"},
    "v": {"type": "hub_floor", "walkable": False, "safe": True, "decor": "barrel"},
    "w": {"type": "hub_floor", "walkable": False, "safe": True, "decor": "crate"},
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
    """Plaza props and torch posts that a building must never cover."""
    reserved = {ENTRY, MERCHANT_TILE, BARREL, CRATE}
    for j in range(2):
        for i in range(2):
            reserved.add((FOUNTAIN[0] + i, FOUNTAIN[1] + j))
    reserved.update(PLAZA_TORCHES)
    reserved.update(rim_torches())
    return reserved


def _derive_windows(layout: dict) -> None:
    """Set the window cells for the layout's current width, height and door."""
    w, h = layout["w"], layout["h"]
    door_i = layout["door_i"]
    layout["window_i"] = 1 + door_i % (w - 2)
    layout["window_row"] = h - 2
    layout["window_i2"] = 1 + (door_i + 3) % (w - 2)
    layout["window_row2"] = h - 3


def _slot_cells(layout: dict) -> list[tuple[int, int]]:
    return [
        (layout["x"] + i, layout["y"] + j)
        for j in range(layout["h"])
        for i in range(layout["w"])
    ]


def _slot_fits(layout: dict, reserved: set[tuple[int, int]]) -> bool:
    """True when every footprint tile is clear city floor, off the hub/roads."""
    for x, y in _slot_cells(layout):
        if not on_city_floor(x, y):
            return False
        if city_dist(x, y) > HOUSE_MAX_CITY_DIST:
            return False
        if city_dist(x, y) <= HUB_RADIUS + HUB_BUILDING_MARGIN:
            return False
        if on_hub(x, y) or on_road(x, y):
            return False
        if (x, y) in reserved:
            return False
    return True


def _north_building_layouts(reserved: set[tuple[int, int]]) -> list[dict]:
    """Buildings in the north-west quarter, packed from the N/S road outward."""
    layouts = []
    for row_idx, (door_y, row_h) in enumerate(BUILDING_ROWS):
        right = ROAD_X_MIN - 2  # leave one town floor tile beside the road
        for col in range(BUILDING_COLUMNS):
            # Only the 8 wide house is 6 tall; the 7 wide ones are 7x5.
            w = 8 if (row_h == 6 and col % 2 == 0) else 7
            h = 6 if w == 8 else 5
            left = right - w + 1
            if left < 0:
                break
            layout = {
                "x": left,
                "y": door_y - h + 1,
                "w": w,
                "h": h,
                "door_i": 1 + (row_idx * 3 + col) % (w - 2),
                "variant": "a" if (row_idx + col) % 2 == 0 else "b",
                "kind": "house",
                "row": row_idx,
                "col": col,
            }
            _derive_windows(layout)
            if _slot_fits(layout, reserved):
                layouts.append(layout)
            right = left - 2  # one clear tile between neighbouring footprints
    return layouts


def _assign_shops(layouts: list[dict]) -> None:
    """Turn the third of the buildings closest to the hub/roads into shops."""
    shop_count = (len(layouts) + SHOP_EVERY - 1) // SHOP_EVERY
    order = sorted(
        range(len(layouts)),
        key=lambda i: (
            min(city_dist(x, y) for x, y in _slot_cells(layouts[i])),
            layouts[i]["y"],
            layouts[i]["x"],
        ),
    )
    for i in order[:shop_count]:
        layout = layouts[i]
        bottom = layout["y"] + layout["h"] - 1
        layout["kind"] = "shop"
        layout["variant"] = "m"
        layout["h"] = 5
        layout["y"] = bottom - layout["h"] + 1
        _derive_windows(layout)
    for layout in layouts:
        layout["cells"] = _slot_cells(layout)


def _mirror_x(layout: dict) -> dict:
    """Mirror a footprint across the north/south roads (x -> 191 - x)."""
    w = layout["w"]
    mirrored = dict(layout)
    mirrored["x"] = 191 - (layout["x"] + w - 1)
    mirrored["door_i"] = w - 1 - layout["door_i"]
    mirrored["cells"] = [(191 - x, y) for x, y in layout["cells"]]
    _derive_windows(mirrored)
    return mirrored


def _mirror_y(layout: dict) -> dict:
    """Point-reflect a footprint across y = 64, keeping its door facing south."""
    h = layout["h"]
    mirrored = dict(layout)
    mirrored["y"] = 127 - (layout["y"] + h - 1)
    mirrored["cells"] = [(x, 127 - y) for x, y in layout["cells"]]
    _derive_windows(mirrored)
    return mirrored


def building_layouts() -> list[dict]:
    """All city buildings, mirrored into the four quarters between the roads."""
    reserved = reserved_tiles()
    north = _north_building_layouts(reserved)
    _assign_shops(north)
    layouts = []
    for layout in north:
        layouts.append(layout)
        layouts.append(_mirror_x(layout))
        layouts.append(_mirror_y(layout))
        layouts.append(_mirror_x(_mirror_y(layout)))
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


def road_props(grid: list[list[str]], buildings: list[dict]) -> list[tuple[int, int, str]]:
    """Barrels, crates and torches on town floor beside the roads.

    Each offset is stamped as a four-way mirror group, so the decoration stays
    symmetric. Groups that would touch a building, a door approach or a plaza
    prop are skipped whole, which keeps the mirror pairs intact.
    """
    building_cells = {cell for building in buildings for cell in building["cells"]}
    approaches = {
        (building["x"] + building["door_i"], building["y"] + building["h"])
        for building in buildings
    }
    around_doors = {
        (x + dx, y + dy)
        for x, y in approaches
        for dx in range(-1, 2)
        for dy in range(-1, 2)
    }
    reserved = reserved_tiles()
    used: set[tuple[int, int]] = set()
    props = []

    def add_group(coords: list[tuple[int, int]], char: str) -> None:
        for x, y in coords:
            if grid[y][x] != "T":
                return
            if (x, y) in building_cells or (x, y) in reserved or (x, y) in used:
                return
            if (x, y) in around_doors:
                return
        for x, y in coords:
            used.add((x, y))
            props.append((x, y, char))

    for i, off in enumerate(ROAD_PROP_EW_OFFSETS):
        char = ROAD_PROP_CHARS[i % len(ROAD_PROP_CHARS)]
        west = int(CITY_CX) - off
        east = 191 - west
        coords = [
            (x, y)
            for x in (west, east)
            for y in (ROAD_Y_MIN - 1, GATE_ROW_MAX + 1)
        ]
        add_group(coords, char)

    for i, off in enumerate(ROAD_PROP_NS_OFFSETS):
        char = ROAD_PROP_CHARS[(i + 1) % len(ROAD_PROP_CHARS)]
        south = int(CITY_CY) + off
        north = 127 - south
        coords = [
            (x, y)
            for x in (ROAD_X_MIN - 1, ROAD_X_MIN + ROAD_WIDTH)
            for y in (south, north)
        ]
        add_group(coords, char)

    return props


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

    # Buildings (JGT-123/JGT-137): houses and shops fill the four quarters in
    # mirrored rows, each door facing south onto a two tile alley.
    reserved = reserved_tiles()
    buildings = building_layouts()

    building_cells: set[tuple[int, int]] = set()
    for building in buildings:
        cells = building["cells"]
        assert all(on_city_floor(x, y) for x, y in cells), "building %s outside the city floor" % str(building)
        assert all(city_dist(x, y) <= HOUSE_MAX_CITY_DIST for x, y in cells), "building %s outside the city core" % str(building)
        assert building_cells.isdisjoint(cells), "building %s overlaps another building" % str(building)
        assert reserved.isdisjoint(cells), "building %s covers a plaza prop" % str(building)
        for x, y in cells:
            assert grid[y][x] == "T", "building %s overlaps a non-town-floor tile" % str(building)
            # Keep a one tile margin from the roads and the hub.
            for dx in range(-1, 2):
                for dy in range(-1, 2):
                    assert not on_road(x + dx, y + dy), "building %s touches a road" % str(building)
                    assert city_dist(x + dx, y + dy) > HUB_RADIUS, "building %s touches the hub" % str(building)
        building_cells.update(cells)

    for building in buildings:
        approach = (building["x"] + building["door_i"], building["y"] + building["h"])
        assert 0 <= approach[0] < WIDTH and 0 <= approach[1] < HEIGHT, "building %s door is outside the map" % str(building)
        assert approach not in building_cells, "building %s door faces another building" % str(building)
        assert approach not in reserved, "building %s door faces a plaza prop" % str(building)
        assert grid[approach[1]][approach[0]] in ("T", "R", "o"), "building %s door faces a walkable tile" % str(building)

    quarter_counts: dict[str, int] = {}
    for building in buildings:
        door_x = building["x"] + building["door_i"]
        door_y = building["y"] + building["h"]
        quarter = ("N" if door_y < ROAD_Y_MIN else "S") + ("W" if door_x < ROAD_X_MIN else "E")
        quarter_counts[quarter] = quarter_counts.get(quarter, 0) + 1
    assert set(quarter_counts) == {"NW", "NE", "SW", "SE"}, "every quarter holds buildings"
    assert len(set(quarter_counts.values())) == 1, "the four quarters hold the same number of buildings"

    for building in buildings:
        if building["kind"] == "shop":
            place_shop(grid, building["x"], building["y"], building["w"], building["h"], building["door_i"], building["variant"])
    for building in buildings:
        if building["kind"] != "house":
            continue
        for j in range(building["h"]):
            for i in range(building["w"]):
                grid[building["y"] + j][building["x"] + i] = house_part_char(building, i, j)

    fx, fy = FOUNTAIN
    for j in range(2):
        for i in range(2):
            grid[fy + j][fx + i] = "F"
    grid[BARREL[1]][BARREL[0]] = "v"
    grid[CRATE[1]][CRATE[0]] = "w"
    for tx, ty in PLAZA_TORCHES:
        grid[ty][tx] = "u"

    # Torch posts in a ring just inside the city wall, then dress the roads with
    # barrels, crates and torches on the town floor beside them.
    for tx, ty in rim_torches():
        grid[ty][tx] = "t"
    for tx, ty, char in road_props(grid, buildings):
        grid[ty][tx] = char

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
