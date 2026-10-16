extends RefCounted
## Procedural island heightfield.
##
## A continuous elevation field (domain-warped fbm minus a radial falloff) is
## pushed through a terrace curve, giving flat plateaus separated by steep cliff
## risers: readable tactical levels with a sculpted, diorama silhouette.

const LEVEL_H := 1.25      # height of one terrace step
const BEACH_H := 0.28      # height of the beach band above the waterline
const SEA_FLOOR := -9.0

var size := 84.0           # world metres across the whole field
var res := 421             # vertices per side
var step := 0.0
var x0 := 0.0
var heights := PackedFloat32Array()
var elevation := PackedFloat32Array()   # raw continuous field, for scatter masks
var rng_seed := 0
var archetype := "round"
const ARCHETYPES := ["round", "ridge", "twin", "crescent", "atoll", "highland"]


func _init(p_seed: int) -> void:
	rng_seed = p_seed
	step = size / float(res - 1)
	x0 = -size * 0.5

	var base := _fbm(p_seed, 0.038, 5)
	var warp := _fbm(p_seed + 11, 0.022, 3)
	var detail := _fbm(p_seed + 23, 0.21, 2)
	var beach := _fbm(p_seed + 37, 0.06, 2)
	var ar := RandomNumberGenerator.new()
	ar.seed = p_seed * 13 + 7
	archetype = ARCHETYPES[ar.randi() % ARCHETYPES.size()]
	if Capture.has("shape"):
		archetype = Capture.arg("shape")
	var spin := ar.randf() * TAU
	var cs := cos(spin)
	var sn := sin(spin)

	heights.resize(res * res)
	elevation.resize(res * res)
	for j in res:
		for i in res:
			var x := x0 + i * step
			var z := x0 + j * step
			var wx := x + warp.get_noise_2d(x, z) * 7.0
			var wz := z + warp.get_noise_2d(x + 131.0, z - 71.0) * 7.0
			# Rotate into the archetype's own frame.
			var u := wx * cs - wz * sn
			var v := wx * sn + wz * cs
			var r := Vector2(u * 0.92, v * 1.08).length() / (60.0 * 0.33)
			var falloff := pow(r, 2.0) * 1.15
			var lift := 0.0
			match archetype:
				"ridge":
					# A long spine: steep sides, beaches at both tips.
					falloff = pow(Vector2(u * 0.62, v * 1.55).length() / 19.8, 2.0) * 1.15
					lift = 0.12
				"twin":
					# Two hills joined by a low saddle.
					var r1 := Vector2(u - 8.5, v).length() / 13.0
					var r2 := Vector2(u + 8.5, v).length() / 13.0
					falloff = minf(pow(r1, 2.0), pow(r2, 2.0)) * 1.15 + 0.12
				"crescent":
					# A bay bitten out of one side.
					var bite := Vector2(u - 9.0, v).length() / 9.5
					falloff += maxf(0.0, 1.0 - bite) * 1.4
				"atoll":
					# A ring of land round a sheltered lagoon.
					var ring := absf(r - 0.68) / 0.36
					falloff = pow(ring, 2.0) * 1.15 + 0.05
				"highland":
					# A tall plateau with cliffs straight into the sea.
					falloff = pow(r, 3.2) * 1.35
					lift = 0.22
			var e := 1.0 - falloff + lift + base.get_noise_2d(wx, wz) * 0.62
			var k := j * res + i
			elevation[k] = e
			heights[k] = _shape(e, detail.get_noise_2d(x, z), beach.get_noise_2d(x, z))


func _fbm(s: int, f: float, oct: int) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = s
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = oct
	n.frequency = f
	return n


## Maps continuous elevation to terraced height.
func _shape(e: float, detail: float, beach_n: float) -> float:
	if e <= 0.0:
		# Underwater shelf: shallow near the coast, then dropping away.
		var d := -e
		return lerpf(-0.12, SEA_FLOOR, clampf(pow(d * 0.9, 0.85), 0.0, 1.0))
	# Beach width varies around the coast; where it is thin, cliffs meet the sea.
	var beach_w := clampf(0.05 + beach_n * 0.09, 0.0, 0.12)
	var t := maxf(e - beach_w, 0.0) * 2.7
	var f := floorf(t)
	var fr := t - f
	var rise := smoothstep(0.80, 0.97, fr)
	var h := BEACH_H + (f + rise) * LEVEL_H
	if e < beach_w + 0.0001:
		h = lerpf(-0.12, BEACH_H, smoothstep(0.0, maxf(beach_w, 0.001), e))
	# Gentle undulation on plateaus, none on the cliff faces.
	h += detail * 0.05 * (1.0 - rise)
	return h


func idx(i: int, j: int) -> int:
	return clampi(j, 0, res - 1) * res + clampi(i, 0, res - 1)


func h_at_idx(i: int, j: int) -> float:
	return heights[idx(i, j)]


func normal_idx(i: int, j: int) -> Vector3:
	var hl := h_at_idx(i - 1, j)
	var hr := h_at_idx(i + 1, j)
	var hd := h_at_idx(i, j - 1)
	var hu := h_at_idx(i, j + 1)
	return Vector3(hl - hr, 2.0 * step, hd - hu).normalized()


func _sample(arr: PackedFloat32Array, x: float, z: float) -> float:
	var fx := clampf((x - x0) / step, 0.0, res - 1.001)
	var fz := clampf((z - x0) / step, 0.0, res - 1.001)
	var i := int(fx)
	var j := int(fz)
	var tx := fx - i
	var tz := fz - j
	var a := lerpf(arr[j * res + i], arr[j * res + i + 1], tx)
	var b := lerpf(arr[(j + 1) * res + i], arr[(j + 1) * res + i + 1], tx)
	return lerpf(a, b, tz)


func height_at(x: float, z: float) -> float:
	return _sample(heights, x, z)


func elevation_at(x: float, z: float) -> float:
	return _sample(elevation, x, z)


func normal_at(x: float, z: float) -> Vector3:
	var e := step
	var hl := height_at(x - e, z)
	var hr := height_at(x + e, z)
	var hd := height_at(x, z - e)
	var hu := height_at(x, z + e)
	return Vector3(hl - hr, 2.0 * e, hd - hu).normalized()


## Height spread across a footprint: small means flat enough to build on.
func flatness(x: float, z: float, radius: float) -> float:
	var lo := INF
	var hi := -INF
	for a in 8:
		var ang := a * TAU / 8.0
		for r in [radius * 0.5, radius]:
			var h := height_at(x + cos(ang) * r, z + sin(ang) * r)
			lo = minf(lo, h)
			hi = maxf(hi, h)
	var c := height_at(x, z)
	return maxf(hi, c) - minf(lo, c)


func terrace_level(h: float) -> int:
	return int(floor((h - BEACH_H + 0.2) / LEVEL_H))
