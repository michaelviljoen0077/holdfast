extends RefCounted
## Guarantees every walkable plateau is reachable by carving ramps through the
## cliff risers that separate it from its neighbours. Ramps double as the
## island's natural chokepoints.

const MIN_COMPONENT := 24      # cells; smaller pockets are ignored
const RAMP_WIDTH := 1.7
const RAMP_BLEND := 0.8
const MAX_GRADE := 0.36        # rise over run

var island
var nav
var ramps: Array[Dictionary] = []   # {start, end} world xz, for debugging and AI


func _init(p_island, p_nav) -> void:
	island = p_island
	nav = p_nav


func run() -> void:
	var failures := {}
	for _iter in 40:
		var sizes: Dictionary = nav.component_sizes()
		var comps := sizes.keys().filter(func(c): return sizes[c] >= MIN_COMPONENT and failures.get(c, 0) < 3)
		if comps.size() <= 1:
			break
		# Connect the smallest pocket first: it has the fewest options.
		comps.sort_custom(func(a, b): return sizes[a] < sizes[b])
		var a_comp: int = comps[0]
		var pair := _closest_pair(a_comp, sizes)
		if pair.is_empty():
			failures[a_comp] = failures.get(a_comp, 0) + 1
			continue
		_carve(pair["a"], pair["b"])
		nav.rebuild()
		var still: bool = nav.component[nav.idx(nav.cell_of(pair["a"]))] != nav.component[nav.idx(nav.cell_of(pair["b"]))]
		if still:
			failures[a_comp] = failures.get(a_comp, 0) + 1


## Adds ramps where the walk between two sides of a cliff is a long detour.
## These become the contested routes between terraces.
func add_shortcuts(max_ramps: int, rng: RandomNumberGenerator) -> void:
	var n: int = nav.n
	for _r in max_ramps:
		nav.build_astar()
		var best := {}
		var best_gain := 18.0
		for _s in 500:
			var c := Vector2i(rng.randi_range(4, n - 5), rng.randi_range(4, n - 5))
			var k: int = nav.idx(c)
			if nav.walkable[k] == 0 or nav.heights[k] < 0.05:
				continue
			# Look straight across the nearest riser in a random direction.
			var ang := rng.randf() * TAU
			var dir := Vector2(cos(ang), sin(ang))
			var p: Vector2 = nav.cell_centre(c.x, c.y)
			var ha: float = nav.heights[k]
			for step in range(2, 9):
				var q: Vector2 = p + dir * step * nav.CELL
				var qc: Vector2i = nav.cell_of(q)
				if not nav.is_walkable(qc):
					continue
				var hb: float = nav.heights[nav.idx(qc)]
				var dh := absf(hb - ha)
				if dh < island.LEVEL_H * 0.7 or dh > island.LEVEL_H * 1.4 or hb < 0.05:
					continue
				var too_close := false
				for r in ramps:
					if ((r["start"] + r["end"]) * 0.5).distance_to((p + q) * 0.5) < 9.0:
						too_close = true
						break
				if too_close:
					break
				var path: PackedVector2Array = nav.find_path(p, q)
				var walk := 0.0
				for i in range(1, path.size()):
					walk += path[i - 1].distance_to(path[i])
				if path.is_empty():
					walk = 999.0
				var gain := walk - p.distance_to(q)
				if gain > best_gain:
					best_gain = gain
					best = {"a": p, "b": q}
				break
		if best.is_empty():
			break
		_carve(best["a"], best["b"])
		nav.rebuild()


func _closest_pair(a_comp: int, sizes: Dictionary) -> Dictionary:
	var n: int = nav.n
	var best := {}
	var best_score := INF
	var radius := 9
	for k in n * n:
		if nav.component[k] != a_comp:
			continue
		var c := Vector2i(k % n, k / n)
		# Boundary cells only.
		var edge := false
		for d in nav.DIRS:
			var nb: Vector2i = c + d
			if not nav.in_bounds(nb) or nav.component[nav.idx(nb)] != a_comp:
				edge = true
				break
		if not edge:
			continue
		var ha: float = nav.heights[k]
		if ha < 0.0:
			continue
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				var o := c + Vector2i(dx, dy)
				if not nav.in_bounds(o):
					continue
				var ok: int = nav.idx(o)
				var oc: int = nav.component[ok]
				if oc < 0 or oc == a_comp or sizes.get(oc, 0) < MIN_COMPONENT:
					continue
				var hb: float = nav.heights[ok]
				if hb < 0.0:
					continue
				var dh := absf(hb - ha)
				if dh < 0.4 or dh > island.LEVEL_H * 1.6:
					continue
				var dist: float = Vector2(dx, dy).length() * nav.CELL
				# Prefer short crossings near the island's heart over remote corners.
				var p: Vector2 = nav.cell_centre(c.x, c.y)
				var score: float = dist + dh * 0.5 + p.length() * 0.04
				if score < best_score:
					best_score = score
					best = {"a": p, "b": nav.cell_centre(o.x, o.y)}
	return best


func _carve(a: Vector2, b: Vector2) -> void:
	var ha: float = island.height_at(a.x, a.y)
	var hb: float = island.height_at(b.x, b.y)
	var g := (b - a).normalized()
	var perp := g.orthogonal()
	var length := maxf(absf(hb - ha) / MAX_GRADE, a.distance_to(b) + 1.6)
	var centre := (a + b) * 0.5
	var start := centre - g * length * 0.5
	var end := centre + g * length * 0.5
	# Sample the plateaus a little beyond each end so the ramp lands flush.
	var hs: float = island.height_at(start.x - g.x * 0.4, start.y - g.y * 0.4)
	var he: float = island.height_at(end.x + g.x * 0.4, end.y + g.y * 0.4)
	ramps.append({"start": start, "end": end})
	var reach := length * 0.5 + 1.5 + RAMP_WIDTH
	var res: int = island.res
	var i0 := clampi(int((centre.x - reach - island.x0) / island.step), 0, res - 1)
	var i1 := clampi(int((centre.x + reach - island.x0) / island.step) + 1, 0, res - 1)
	var j0 := clampi(int((centre.y - reach - island.x0) / island.step), 0, res - 1)
	var j1 := clampi(int((centre.y + reach - island.x0) / island.step) + 1, 0, res - 1)
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			var p := Vector2(island.x0 + i * island.step, island.x0 + j * island.step)
			var rel := p - start
			var t := rel.dot(g) / length
			var s := absf(rel.dot(perp))
			if t < -0.2 or t > 1.2 or s > RAMP_WIDTH * 0.5 + RAMP_BLEND:
				continue
			var target := lerpf(hs, he, clampf(t, 0.0, 1.0))
			var wl := 1.0 - smoothstep(RAMP_WIDTH * 0.5, RAMP_WIDTH * 0.5 + RAMP_BLEND, s)
			var wt := smoothstep(-0.2, 0.0, t) * (1.0 - smoothstep(1.0, 1.2, t))
			var k: int = j * res + i
			island.heights[k] = lerpf(island.heights[k], target, wl * wt)
