class_name Facing
extends RefCounted

## 8-way facing directions in world space (+x east, +y south), clockwise.
const NONE: int = -1
const EAST: int = 0
const SOUTH_EAST: int = 1
const SOUTH: int = 2
const SOUTH_WEST: int = 3
const WEST: int = 4
const NORTH_WEST: int = 5
const NORTH: int = 6
const NORTH_EAST: int = 7


## Quantizes a direction to the nearest of the 8 octants; NONE for a zero or
## non-finite vector.
static func octant(v: Vector2) -> int:
	if not v.is_finite() or v.is_zero_approx():
		return NONE
	var sector: int = int(roundf(atan2(v.y, v.x) / (PI / 4.0)))
	return posmod(sector, 8)
