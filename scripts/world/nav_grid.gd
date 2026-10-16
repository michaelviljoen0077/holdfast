extends RefCounted
## Walkability grid over the island, used for connectivity analysis (ramp
## carving) and unit pathfinding.
##
## Cells are CELL metres square. A cell is walkable when its ground is above
## deep water and not too steep; two neighbouring cells are linked when the
## height step between them is small enough to walk, so cliffs block movement.

const CELL := 0.5
const EXTENT := 30.0
const MAX_STEP := 0.32         # max height change between orthogonal neighbours
const WADE_DEPTH := -0.55      # units can wade into shallow water down to here

var n := int(EXTENT * 2.0 / CELL)
var heights := PackedFloat32Array()
var walkable := PackedByteArray()
var component := PackedInt32Array()
var blocked := PackedByteArray()      # cells covered by standing structures
var astar := AStar2D.new()
var island

const DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]


func _init(p_island) -> void:
	island = p_island
	rebuild()


func rebuild() -> void:
	heights.resize(n * n)
	walkable.resize(n * n)
	component.resize(n * n)
	if blocked.size() != n * n:
		blocked.resize(n * n)
		blocked.fill(0)
	for j in n:
		for i in n:
			var p := cell_centre(i, j)
			var h: float = island.height_at(p.x, p.y)
			var k := j * n + i
			heights[k] = h
			walkable[k] = 1 if h > WADE_DEPTH and island.normal_at(p.x, p.y).y > 0.78 else 0
	_label_components()


func cell_centre(i: int, j: int) -> Vector2:
	return Vector2(-EXTENT + (i + 0.5) * CELL, -EXTENT + (j + 0.5) * CELL)


func cell_of(p: Vector2) -> Vector2i:
	return Vector2i(clampi(int((p.x + EXTENT) / CELL), 0, n - 1), clampi(int((p.y + EXTENT) / CELL), 0, n - 1))


func idx(c: Vector2i) -> int:
	return c.y * n + c.x


func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < n and c.y < n


func is_walkable(c: Vector2i) -> bool:
	return in_bounds(c) and walkable[idx(c)] == 1 and blocked[idx(c)] == 0


## Cells within `half_width` of segment a-b (a structure's footprint).
func cells_along(a: Vector2, b: Vector2, half_width: float) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var lo := cell_of(Vector2(minf(a.x, b.x) - half_width - CELL, minf(a.y, b.y) - half_width - CELL))
	var hi := cell_of(Vector2(maxf(a.x, b.x) + half_width + CELL, maxf(a.y, b.y) + half_width + CELL))
	var ab := b - a
	for j in range(lo.y, hi.y + 1):
		for i in range(lo.x, hi.x + 1):
			var p := cell_centre(i, j)
			var t := 0.0
			if ab.length_squared() > 1e-6:
				t = clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
			if (a + ab * t).distance_to(p) <= half_width + CELL * 0.35:
				out.append(Vector2i(i, j))
	return out


func block(cells: Array[Vector2i]) -> void:
	for c in cells:
		if not in_bounds(c):
			continue
		var k := idx(c)
		blocked[k] = 1
		if astar.has_point(k):
			astar.set_point_disabled(k, true)


func unblock(cells: Array[Vector2i]) -> void:
	for c in cells:
		if not in_bounds(c):
			continue
		var k := idx(c)
		blocked[k] = 0
		if astar.has_point(k):
			astar.set_point_disabled(k, false)


func linked(a: Vector2i, b: Vector2i) -> bool:
	if not is_walkable(a) or not is_walkable(b):
		return false
	var d := b - a
	var limit := MAX_STEP * (1.42 if d.x != 0 and d.y != 0 else 1.0)
	if absf(heights[idx(a)] - heights[idx(b)]) > limit:
		return false
	# No corner cutting past an unwalkable or cliff cell.
	if d.x != 0 and d.y != 0:
		var s1 := Vector2i(a.x + d.x, a.y)
		var s2 := Vector2i(a.x, a.y + d.y)
		if not (is_walkable(s1) and is_walkable(s2)):
			return false
		if absf(heights[idx(s1)] - heights[idx(a)]) > MAX_STEP or absf(heights[idx(s2)] - heights[idx(a)]) > MAX_STEP:
			return false
	return true


func _label_components() -> void:
	component.fill(-1)
	var next := 0
	for k in n * n:
		if walkable[k] == 0 or component[k] != -1:
			continue
		var stack: Array[Vector2i] = [Vector2i(k % n, k / n)]
		component[k] = next
		while not stack.is_empty():
			var c: Vector2i = stack.pop_back()
			for d in DIRS:
				var nb: Vector2i = c + d
				if in_bounds(nb) and component[idx(nb)] == -1 and linked(c, nb):
					component[idx(nb)] = next
					stack.push_back(nb)
		next += 1


## Component id -> cell count, for land above the waterline only.
func component_sizes() -> Dictionary:
	var sizes := {}
	for k in n * n:
		var c := component[k]
		if c >= 0 and heights[k] > 0.0:
			sizes[c] = sizes.get(c, 0) + 1
	return sizes


func build_astar() -> void:
	astar.clear()
	astar.reserve_space(n * n)
	for k in n * n:
		if walkable[k] == 1:
			var c := Vector2i(k % n, k / n)
			# Wading is slow; keep units on dry land when there is a choice.
			var w := 3.0 if heights[k] < -0.05 else 1.0
			astar.add_point(k, cell_centre(c.x, c.y), w)
	for k in n * n:
		if walkable[k] == 0:
			continue
		var c := Vector2i(k % n, k / n)
		for d in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, -1)]:
			var nb: Vector2i = c + d
			if linked(c, nb):
				astar.connect_points(k, idx(nb))


## Nearest walkable cell to a world point (searching outward in rings).
func nearest_walkable(p: Vector2, max_r := 12) -> Vector2i:
	var c := cell_of(p)
	if is_walkable(c):
		return c
	for r in range(1, max_r):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) != r and absi(dy) != r:
					continue
				var nb := c + Vector2i(dx, dy)
				if is_walkable(nb):
					return nb
	return Vector2i(-1, -1)


## World-space path between two points, string-pulled to remove grid zig-zag.
func find_path(from: Vector2, to: Vector2) -> PackedVector2Array:
	var a := nearest_walkable(from)
	var b := nearest_walkable(to)
	if a.x < 0 or b.x < 0:
		return PackedVector2Array()
	var raw := astar.get_point_path(idx(a), idx(b), true)
	if raw.is_empty():
		return raw
	raw[0] = from
	return _smooth(raw)


func _smooth(raw: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array([raw[0]])
	var i := 0
	while i < raw.size() - 1:
		var j := raw.size() - 1
		while j > i + 1 and not clear_line(raw[i], raw[j]):
			j -= 1
		out.append(raw[j])
		i = j
	return out


## True when a straight walk from a to b never crosses a cliff or unwalkable cell.
func clear_line(a: Vector2, b: Vector2) -> bool:
	var dist := a.distance_to(b)
	var steps := int(dist / (CELL * 0.5)) + 1
	var prev := cell_of(a)
	for s in range(1, steps + 1):
		var c := cell_of(a.lerp(b, float(s) / steps))
		if c == prev:
			continue
		if not linked(prev, c):
			# Allow straight diagonal steps that 'linked' rejects only for corner rules.
			return false
		prev = c
	return true


func height_at(p: Vector2) -> float:
	return island.height_at(p.x, p.y)
