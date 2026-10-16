extends RefCounted
## Faceted low-poly mesh construction helpers built on SurfaceTool.
## Every triangle is emitted with an outward hint so winding is always correct.

var st := SurfaceTool.new()
var rng := RandomNumberGenerator.new()
var _sway := 0.0


func _init(p_seed := 0) -> void:
	rng.seed = p_seed
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)


## Vertex alpha carries a wind sway weight read by the foliage shader.
func set_sway(w: float) -> void:
	_sway = w


func tri(a: Vector3, b: Vector3, c: Vector3, col: Color, outward: Vector3) -> void:
	if (b - a).cross(c - a).length_squared() < 1e-12:
		return
	# Godot front faces wind clockwise: (b-a)x(c-a) must point away from the viewer.
	if (b - a).cross(c - a).dot(outward) > 0.0:
		var tmp := b
		b = c
		c = tmp
	col.a = _sway
	for v in [a, b, c]:
		st.set_color(col)
		st.add_vertex(v)


## Triangle with a colour per corner (for gradients across a surface).
func tri3(a: Vector3, b: Vector3, c: Vector3, ca: Color, cb: Color, cc: Color, outward: Vector3) -> void:
	if (b - a).cross(c - a).length_squared() < 1e-12:
		return
	if (b - a).cross(c - a).dot(outward) > 0.0:
		var tmp := b
		b = c
		c = tmp
		var tc := cb
		cb = cc
		cc = tc
	for pair in [[a, ca], [b, cb], [c, cc]]:
		var col: Color = pair[1]
		col.a = _sway
		st.set_color(col)
		st.add_vertex(pair[0])


func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, outward: Vector3) -> void:
	tri(a, b, c, col, outward)
	tri(a, c, d, col, outward)


func box(xf: Transform3D, size: Vector3, col: Color) -> void:
	var h := size * 0.5
	var p := func(x: float, y: float, z: float) -> Vector3:
		return xf * Vector3(x * h.x, y * h.y, z * h.z)
	var b := xf.basis
	var faces := [
		[Vector3(1, 0, 0), [p.call(1, -1, -1), p.call(1, 1, -1), p.call(1, 1, 1), p.call(1, -1, 1)]],
		[Vector3(-1, 0, 0), [p.call(-1, -1, -1), p.call(-1, -1, 1), p.call(-1, 1, 1), p.call(-1, 1, -1)]],
		[Vector3(0, 1, 0), [p.call(-1, 1, -1), p.call(-1, 1, 1), p.call(1, 1, 1), p.call(1, 1, -1)]],
		[Vector3(0, -1, 0), [p.call(-1, -1, -1), p.call(1, -1, -1), p.call(1, -1, 1), p.call(-1, -1, 1)]],
		[Vector3(0, 0, 1), [p.call(-1, -1, 1), p.call(1, -1, 1), p.call(1, 1, 1), p.call(-1, 1, 1)]],
		[Vector3(0, 0, -1), [p.call(-1, -1, -1), p.call(-1, 1, -1), p.call(1, 1, -1), p.call(1, -1, -1)]],
	]
	for f in faces:
		var q: Array = f[1]
		quad(q[0], q[1], q[2], q[3], col, b * f[0])


## Frustum along local +Y from y0 to y1. r1 = 0 makes a cone.
func cylinder(xf: Transform3D, r0: float, r1: float, y0: float, y1: float, sides: int, col: Color, caps := true) -> void:
	var axis := xf.basis * Vector3.UP
	var centre_lo := xf * Vector3(0, y0, 0)
	var centre_hi := xf * Vector3(0, y1, 0)
	for s in sides:
		var a0 := TAU * s / sides
		var a1 := TAU * (s + 1) / sides
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		var lo0 := xf * (d0 * r0 + Vector3(0, y0, 0))
		var lo1 := xf * (d1 * r0 + Vector3(0, y0, 0))
		var hi0 := xf * (d0 * r1 + Vector3(0, y1, 0))
		var hi1 := xf * (d1 * r1 + Vector3(0, y1, 0))
		var out := xf.basis * ((d0 + d1) * 0.5)
		if r1 > 0.0001:
			quad(lo0, lo1, hi1, hi0, col, out)
		else:
			tri(lo0, lo1, hi0, col, out)
		if caps:
			tri(centre_lo, lo1, lo0, col.darkened(0.15), -axis)
			if r1 > 0.0001:
				tri(centre_hi, hi0, hi1, col, axis)


## Icosphere (subdivided once) with per-vertex noise jitter: rocks, foliage.
func blob(centre: Vector3, radius: Vector3, col: Color, jitter: float, subdiv := 1, col_jitter := 0.0, smooth := false, moss := Color(0, 0, 0, 0)) -> void:
	var t := (1.0 + sqrt(5.0)) / 2.0
	var v := [
		Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]
	var f := [
		[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11],
		[1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
		[3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9],
		[4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1]]
	for i in v.size():
		v[i] = (v[i] as Vector3).normalized()
	for _s in subdiv:
		var cache := {}
		var nf := []
		var mid := func(a: int, b: int) -> int:
			var key := mini(a, b) * 4096 + maxi(a, b)
			if cache.has(key):
				return cache[key]
			v.append(((v[a] as Vector3) + (v[b] as Vector3)).normalized())
			cache[key] = v.size() - 1
			return v.size() - 1
		for tri_i in f:
			var a: int = tri_i[0]
			var b: int = tri_i[1]
			var c: int = tri_i[2]
			var ab: int = mid.call(a, b)
			var bc: int = mid.call(b, c)
			var ca: int = mid.call(c, a)
			nf.append_array([[a, ab, ca], [b, bc, ab], [c, ca, bc], [ab, bc, ca]])
		f = nf
	var pts := []
	var cols := []
	for p in v:
		var k := 1.0 + rng.randf_range(-jitter, jitter)
		var dir := p as Vector3
		pts.append(centre + dir * radius * k)
		# Darker underside, lighter crown: reads as volume and self-occlusion.
		var g := 0.62 + 0.5 * smoothstep(-0.9, 0.9, dir.y)
		var vc := Color(col.r * g, col.g * g, col.b * g)
		if moss.a > 0.0:
			vc = vc.lerp(moss, moss.a * smoothstep(0.35, 0.8, dir.y + rng.randf_range(-0.2, 0.2)))
		cols.append(vc)
	st.set_smooth_group(0 if smooth else -1)
	for tri_i in f:
		var a: Vector3 = pts[tri_i[0]]
		var b: Vector3 = pts[tri_i[1]]
		var c: Vector3 = pts[tri_i[2]]
		var shade := 1.0 + rng.randf_range(-col_jitter, col_jitter)
		var ca: Color = cols[tri_i[0]] * shade
		var cb: Color = cols[tri_i[1]] * shade
		var cc: Color = cols[tri_i[2]] * shade
		if smooth:
			tri3(a, b, c, cols[tri_i[0]], cols[tri_i[1]], cols[tri_i[2]], (a + b + c) / 3.0 - centre)
		else:
			tri3(a, b, c, ca, cb, cc, (a + b + c) / 3.0 - centre)
	st.set_smooth_group(-1)


func commit() -> ArrayMesh:
	st.generate_normals()
	var arrays := st.commit_to_arrays()
	# Smooth-group averaging can cancel to a zero normal on folded geometry,
	# which lights to NaN and blooms into a glowing speck. Repair any such normal.
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bad := 0
	for i in normals.size():
		var n := normals[i]
		if not n.is_finite() or n.length_squared() < 1e-8:
			var t0 := i - i % 3
			var fn := (verts[t0 + 2] - verts[t0]).cross(verts[t0 + 1] - verts[t0])
			normals[i] = fn.normalized() if fn.length_squared() > 1e-12 else Vector3.UP
			bad += 1
		else:
			normals[i] = n.normalized()
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
