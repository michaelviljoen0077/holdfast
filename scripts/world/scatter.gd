extends RefCounted
## Populates the island: grass, forests, rocks. Everything is MultiMesh-instanced.

const Props := preload("res://scripts/world/props.gd")

var island
var rng := RandomNumberGenerator.new()
var forest_noise := FastNoiseLite.new()
var meadow_noise := FastNoiseLite.new()
var blocked: Array[Vector3] = []   # xz centre + radius (in .y) kept clear for buildings
var paths   # optional path mask; grass and trees stay off worn ground


func _init(p_island, p_seed: int) -> void:
	island = p_island
	rng.seed = p_seed
	forest_noise.seed = p_seed + 101
	forest_noise.frequency = 0.07
	forest_noise.fractal_octaves = 2
	meadow_noise.seed = p_seed + 202
	meadow_noise.frequency = 0.12


func block(x: float, z: float, r: float) -> void:
	blocked.append(Vector3(x, r, z))


func _is_blocked(x: float, z: float, pad := 0.0) -> bool:
	if paths and paths.value_at(x, z) > 0.45 - pad * 0.3:
		return true
	for b in blocked:
		if Vector2(x - b.x, z - b.z).length() < b.y + pad:
			return true
	return false


func _ground_ok(x: float, z: float, min_up: float) -> bool:
	var h: float = island.height_at(x, z)
	if h < island.BEACH_H + 0.1:
		return false
	return island.normal_at(x, z).y > min_up


func build_grass(parent: Node3D, mat: ShaderMaterial, flower_mat: ShaderMaterial) -> void:
	if Capture.has("nograss"):
		return
	var clump := _grass_clump_mesh()
	var xforms: Array[Transform3D] = []
	var cols: Array[Color] = []
	var half := 30.0
	var attempts := 150000
	for _a in attempts:
		var x := rng.randf_range(-half, half)
		var z := rng.randf_range(-half, half)
		if not _ground_ok(x, z, 0.93):
			continue
		var m := meadow_noise.get_noise_2d(x, z)
		if m < -0.35 and rng.randf() < 0.75:
			continue
		if _is_blocked(x, z, -0.3):
			continue
		var y: float = island.height_at(x, z)
		var s := rng.randf_range(0.7, 1.25) * (1.0 + maxf(m, 0.0) * 0.6)
		var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.8, 1.2), s))
		xforms.append(Transform3D(b, Vector3(x, y - 0.02, z)))
		var v := rng.randf_range(0.85, 1.1)
		cols.append(Color(v, v, v * rng.randf_range(0.9, 1.0)))
	_spawn_multimesh(parent, clump, mat, xforms, cols, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)

	if Capture.has("noflowers"):
		return
	# Wildflowers: sparse dots of colour in the meadows.
	var flower := _flower_mesh()
	var fx: Array[Transform3D] = []
	var fc: Array[Color] = []
	var palette := [Color(0.95, 0.92, 0.85), Color(0.98, 0.82, 0.25), Color(0.86, 0.42, 0.55), Color(0.55, 0.62, 0.95)]
	for _a in 9000:
		var x := rng.randf_range(-half, half)
		var z := rng.randf_range(-half, half)
		if not _ground_ok(x, z, 0.95) or _is_blocked(x, z):
			continue
		if meadow_noise.get_noise_2d(x + 40.0, z) < 0.15:
			continue
		var y: float = island.height_at(x, z)
		fx.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(x, y, z)))
		fc.append(palette[rng.randi() % palette.size()])
	_spawn_multimesh(parent, flower, flower_mat, fx, fc, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)


func build_trees(parent: Node3D, mat: ShaderMaterial) -> void:
	if Capture.has("notrees"):
		return
	var variants := 4
	var pines: Array = []
	var leafy: Array = []
	for v in variants:
		pines.append({"mesh": Props.pine(rng.randi()), "x": [] as Array[Transform3D]})
		leafy.append({"mesh": Props.broadleaf(rng.randi()), "x": [] as Array[Transform3D]})
	var half := 30.0
	var placed: Array[Vector2] = []
	for _a in 7000:
		var x := rng.randf_range(-half, half)
		var z := rng.randf_range(-half, half)
		if not _ground_ok(x, z, 0.86) or _is_blocked(x, z, 0.8):
			continue
		var f := forest_noise.get_noise_2d(x, z)
		if f < 0.12:
			if rng.randf() > 0.012:
				continue
		var p := Vector2(x, z)
		var too_close := false
		for q in placed:
			if p.distance_squared_to(q) < 0.9:
				too_close = true
				break
		if too_close:
			continue
		# Keep trees off cliff lips so silhouettes stay readable.
		if island.flatness(x, z, 0.7) > 0.35:
			continue
		placed.append(p)
		var y: float = island.height_at(x, z)
		var s := rng.randf_range(0.75, 1.3)
		var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.9, 1.15), s)), Vector3(x, y - 0.05, z))
		var high: bool = y > island.BEACH_H + island.LEVEL_H * 1.5
		var use_pine := rng.randf() < (0.75 if high else 0.3)
		var bucket: Dictionary = (pines if use_pine else leafy)[rng.randi() % variants]
		(bucket["x"] as Array[Transform3D]).append(xf)
	for b in pines + leafy:
		_spawn_multimesh(parent, b["mesh"], mat, b["x"], [], GeometryInstance3D.SHADOW_CASTING_SETTING_ON)


func build_rocks(parent: Node3D, mat: ShaderMaterial) -> void:
	if Capture.has("norocks"):
		return
	var meshes: Array = []
	for v in 5:
		meshes.append({"mesh": Props.rock(rng.randi()), "x": [] as Array[Transform3D]})
	var half := 30.0
	for _a in 6000:
		var x := rng.randf_range(-half, half)
		var z := rng.randf_range(-half, half)
		var h: float = island.height_at(x, z)
		var up: float = island.normal_at(x, z).y
		if h < -1.2 or _is_blocked(x, z):
			continue
		# Rocks gather on beaches, at the feet of cliffs, and in the shallows.
		var at_cliff_foot: bool = up > 0.8 and island.flatness(x, z, 1.0) > 0.6
		var on_beach: bool = h < island.BEACH_H + 0.05 and h > -0.6
		if not ((at_cliff_foot and rng.randf() < 0.3) or (on_beach and rng.randf() < 0.06)):
			continue
		var s := rng.randf_range(0.35, 1.2) * (1.4 if h < 0.0 else 1.0)
		var b := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3(1, 0, 0), rng.randf_range(-0.3, 0.3))
		b = b.scaled(Vector3(s, s * rng.randf_range(0.6, 1.1), s))
		(meshes[rng.randi() % meshes.size()]["x"] as Array[Transform3D]).append(Transform3D(b, Vector3(x, h - 0.08 * s, z)))
	for m in meshes:
		_spawn_multimesh(parent, m["mesh"], mat, m["x"], [], GeometryInstance3D.SHADOW_CASTING_SETTING_ON)


func _spawn_multimesh(parent: Node3D, mesh: Mesh, mat: Material, xforms: Array, cols: Array, shadows: int) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = not cols.is_empty()
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		if mm.use_colors:
			mm.set_instance_color(i, cols[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = shadows
	parent.add_child(mmi)
	return mmi


## Five tapered blades in one mesh. UV.y = 0 at the root, 1 at the tip.
func _grass_clump_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var r := RandomNumberGenerator.new()
	r.seed = 5
	for b in 9:
		var ang := r.randf() * TAU
		var off := Vector3(r.randf_range(-0.07, 0.07), 0, r.randf_range(-0.07, 0.07))
		var height := r.randf_range(0.12, 0.24)
		var width := r.randf_range(0.016, 0.026)
		var lean := Vector3(cos(ang), 0, sin(ang)) * r.randf_range(0.02, 0.08)
		var side := Vector3(-sin(ang), 0, cos(ang)) * width
		var segs := 3
		var pts := []
		for s in segs + 1:
			var t := float(s) / segs
			var centre := off + lean * t * t + Vector3(0, height * t, 0)
			var w := 1.0 - t
			pts.append([centre - side * w, centre + side * w, t])
		for s in segs:
			var a = pts[s]
			var c = pts[s + 1]
			var n := side.cross(Vector3.UP).normalized()
			for v in [[a[0], a[2]], [a[1], a[2]], [c[1], c[2]], [a[0], a[2]], [c[1], c[2]], [c[0], c[2]]]:
				st.set_normal(n)
				st.set_uv(Vector2(0, v[1]))
				st.add_vertex(v[0])
	return st.commit()


func _flower_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stem_top := Vector3(0, 0.16, 0)
	var green := Color(0.3, 0.5, 0.2)
	# Stem: a thin cross of two cards.
	for ang in [0.0, PI * 0.5]:
		var sd := Vector3(cos(ang), 0, sin(ang)) * 0.006
		for v in [-sd, sd, stem_top + sd, -sd, stem_top + sd, stem_top - sd]:
			st.set_color(green)
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(0, 0.5))
			st.add_vertex(v)
	# Head: a small flat star facing up.
	var petals := 5
	for p in petals:
		var a0 := TAU * p / petals
		var a1 := TAU * (p + 0.5) / petals
		for v in [stem_top, stem_top + Vector3(cos(a0), 0.01, sin(a0)) * 0.035, stem_top + Vector3(cos(a1), 0.0, sin(a1)) * 0.015]:
			st.set_color(Color(1, 1, 1))
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(0, 1.0))
			st.add_vertex(v)
	return st.commit()
