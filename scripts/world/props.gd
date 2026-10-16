extends RefCounted
## Procedural prop meshes. Each builder returns a faceted ArrayMesh using
## vertex colours (alpha = wind sway weight) for the shared prop shader.

const MeshKit := preload("res://scripts/world/mesh_kit.gd")

const BARK := Color(0.36, 0.25, 0.17)
const PINE := Color(0.13, 0.31, 0.12)
const LEAF := Color(0.27, 0.47, 0.10)


static func pine(p_seed: int) -> ArrayMesh:
	var k := MeshKit.new(p_seed)
	var xf := Transform3D.IDENTITY
	k.set_sway(0.0)
	k.cylinder(xf, 0.09, 0.06, 0.0, 0.55, 6, BARK)
	var tiers := 3 + k.rng.randi_range(0, 1)
	var y := 0.35
	var r := 0.62 + k.rng.randf_range(-0.06, 0.08)
	for t in tiers:
		var col := PINE.lightened(0.05 * t + k.rng.randf_range(-0.03, 0.03))
		k.set_sway(0.3 + 0.25 * t)
		var rot := Transform3D(Basis(Vector3.UP, k.rng.randf() * TAU), Vector3.ZERO)
		k.cylinder(rot, r, 0.0, y, y + 0.85 - t * 0.08, 7, col)
		y += 0.48 - t * 0.04
		r *= 0.74
	return k.commit()


static func broadleaf(p_seed: int) -> ArrayMesh:
	var k := MeshKit.new(p_seed)
	k.set_sway(0.0)
	var lean := Basis(Vector3(1, 0, 0), k.rng.randf_range(-0.08, 0.08))
	k.cylinder(Transform3D(lean, Vector3.ZERO), 0.11, 0.07, 0.0, 0.9, 6, BARK)
	k.cylinder(Transform3D(lean * Basis(Vector3(0, 0, 1), 0.6), Vector3(0, 0.6, 0)), 0.05, 0.03, 0.0, 0.45, 5, BARK)
	var top := lean * Vector3(0, 1.15, 0)
	k.set_sway(0.7)
	# Occasional autumn-turned tree for colour accents.
	var base := LEAF
	var roll := k.rng.randf()
	if roll < 0.1:
		base = Color(0.78, 0.42, 0.10)
	elif roll < 0.2:
		base = Color(0.62, 0.58, 0.14)
	for b in 5:
		var off := Vector3(k.rng.randf_range(-0.4, 0.4), k.rng.randf_range(-0.15, 0.32), k.rng.randf_range(-0.4, 0.4))
		if b == 0:
			off = Vector3.ZERO
		var rr := k.rng.randf_range(0.38, 0.58)
		var col := base.lightened(k.rng.randf_range(-0.04, 0.08))
		k.blob(top + off, Vector3(rr, rr * 0.82, rr), col, 0.1, 2, 0.0, true)
	return k.commit()


static func rock(p_seed: int) -> ArrayMesh:
	var k := MeshKit.new(p_seed)
	k.set_sway(0.0)
	var c := Color(0.47, 0.45, 0.42).lightened(k.rng.randf_range(-0.08, 0.05))
	k.blob(Vector3(0, 0.12, 0), Vector3(0.5, 0.36, 0.42), c, 0.22, 1, 0.07, false, Color(0.30, 0.42, 0.16, 0.75))
	return k.commit()


static func house(p_seed: int) -> ArrayMesh:
	var k := MeshKit.new(p_seed)
	k.set_sway(0.0)
	var w := k.rng.randf_range(1.5, 2.0)
	var d := k.rng.randf_range(1.1, 1.3)
	var h := k.rng.randf_range(0.8, 0.95)
	var plaster: Color = [Color(0.86, 0.80, 0.66), Color(0.82, 0.74, 0.60), Color(0.78, 0.72, 0.62)][k.rng.randi() % 3]
	var timber := Color(0.30, 0.20, 0.13)
	var stone := Color(0.46, 0.44, 0.41)
	var thatch := k.rng.randf() < 0.35
	var roof: Color
	if thatch:
		roof = Color(0.72, 0.58, 0.30)
	else:
		roof = [Color(0.60, 0.25, 0.17), Color(0.40, 0.33, 0.30), Color(0.55, 0.32, 0.20)][k.rng.randi() % 3]
	var y_floor := 0.2
	# Stone plinth with irregular blocks.
	k.box(Transform3D(Basis(), Vector3(0, 0.1, 0)), Vector3(w + 0.1, 0.22, d + 0.1), stone)
	for i in 10:
		var along := k.rng.randf_range(-0.5, 0.5)
		var side := k.rng.randi() % 4
		var p := Vector3(along * w, 0.1, (d + 0.1) * 0.5) if side < 2 else Vector3((w + 0.1) * 0.5, 0.1, along * d)
		if side % 2 == 1:
			p = -p
			p.y = 0.1
		k.box(Transform3D(Basis(), p), Vector3(0.18, 0.12, 0.18), stone.lightened(k.rng.randf_range(-0.06, 0.08)))
	# Plaster walls.
	k.box(Transform3D(Basis(), Vector3(0, y_floor + h * 0.5, 0)), Vector3(w, h, d), plaster)
	# Timber frame: corner posts, sill and top plates, mid posts and braces on the long walls.
	var t := 0.07
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			k.box(Transform3D(Basis(), Vector3(sx * w * 0.5, y_floor + h * 0.5, sz * d * 0.5)), Vector3(t, h, t), timber)
	for sz in [-1, 1]:
		var z: float = sz * (d * 0.5 + 0.01)
		k.box(Transform3D(Basis(), Vector3(0, y_floor + 0.03, z)), Vector3(w, 0.06, 0.04), timber)
		k.box(Transform3D(Basis(), Vector3(0, y_floor + h - 0.03, z)), Vector3(w, 0.06, 0.04), timber)
		k.box(Transform3D(Basis(), Vector3(0, y_floor + h * 0.5, z)), Vector3(w, 0.045, 0.035), timber)
		for px in [-0.33, 0.33]:
			k.box(Transform3D(Basis(), Vector3(px * w, y_floor + h * 0.5, z)), Vector3(0.05, h, 0.035), timber)
		for bx in [-1, 1]:
			var cx: float = bx * w * 0.415
			var brace := Basis(Vector3(0, 0, 1), bx * 0.62)
			k.box(Transform3D(brace, Vector3(cx, y_floor + h * 0.25, z)), Vector3(0.04, h * 0.6, 0.03), timber)
	# Door with frame, windows with shutters.
	var dz := d * 0.5 + 0.03
	k.box(Transform3D(Basis(), Vector3(0.0, y_floor + 0.27, dz)), Vector3(0.3, 0.54, 0.03), timber.darkened(0.2))
	k.box(Transform3D(Basis(), Vector3(0.0, y_floor + 0.56, dz)), Vector3(0.38, 0.05, 0.05), timber)
	for wx in [-0.36, 0.36]:
		var x: float = wx * w
		k.box(Transform3D(Basis(), Vector3(x, y_floor + 0.58, dz)), Vector3(0.18, 0.17, 0.02), Color(0.16, 0.14, 0.13))
		k.box(Transform3D(Basis(), Vector3(x, y_floor + 0.48, dz + 0.01)), Vector3(0.24, 0.035, 0.05), timber)
		for sx in [-1, 1]:
			k.box(Transform3D(Basis(), Vector3(x + sx * 0.14, y_floor + 0.58, dz)), Vector3(0.09, 0.19, 0.025), Color(0.26, 0.38, 0.30) if p_seed % 2 == 0 else Color(0.48, 0.22, 0.16))
	# Roof: rows of overlapping courses so it has real texture and a thick edge.
	var y0 := y_floor + h
	var rh := 0.8
	var ox := w * 0.5 + 0.16
	var oz := d * 0.5 + 0.24
	var rows := 6 if thatch else 7
	var slope_len := Vector2(oz, rh).length()
	var thick := 0.09 if thatch else 0.05
	for side in [-1, 1]:
		var tilt := atan2(rh, oz)
		for r in rows:
			var t0 := float(r) / rows
			var t1 := float(r + 1) / rows + 0.06
			var zc: float = side * oz * (1.0 - (t0 + t1) * 0.5)
			var yc: float = y0 - 0.05 + rh * (t0 + t1) * 0.5
			var len := slope_len * (t1 - t0)
			var basis := Basis(Vector3(1, 0, 0), side * tilt)
			var jitter := k.rng.randf_range(-0.04, 0.04)
			var col := roof.lightened(jitter + (0.0 if r % 2 == 0 else 0.04))
			k.box(Transform3D(basis, Vector3(0, yc + thick * 0.5, zc)), Vector3(ox * 2.0 + (0.04 if thatch else 0.0), thick, len), col)
	# Ridge cap.
	k.box(Transform3D(Basis(Vector3(0, 0, 1), 0.0), Vector3(0, y0 + rh + 0.02, 0)), Vector3(ox * 2.0 + 0.06, 0.08, 0.12), roof.darkened(0.25))
	# Gable ends in plaster, framed.
	for sx in [-1, 1]:
		var x: float = sx * (w * 0.5)
		k.tri(Vector3(x, y0, -d * 0.5), Vector3(x, y0, d * 0.5), Vector3(x, y0 + rh - 0.04, 0), plaster.darkened(0.05), Vector3(sx, 0, 0))
		k.box(Transform3D(Basis(), Vector3(x + sx * 0.012, y0 + rh * 0.42, 0)), Vector3(0.03, rh * 0.84, 0.05), timber)
	# Chimney.
	var chim_x := w * k.rng.randf_range(0.15, 0.3)
	k.box(Transform3D(Basis(), Vector3(chim_x, y0 + rh * 0.75, -d * 0.16)), Vector3(0.2, 0.75, 0.2), stone)
	k.box(Transform3D(Basis(), Vector3(chim_x, y0 + rh * 0.75 + 0.38, -d * 0.16)), Vector3(0.25, 0.06, 0.25), stone.darkened(0.1))
	# Lean-to woodpile against one wall.
	if k.rng.randf() < 0.6:
		for lg in 6:
			var lx := -w * 0.5 - 0.12
			var lz := -0.3 + (lg % 3) * 0.12
			var ly := 0.06 + (lg / 3) * 0.1
			k.cylinder(Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5), Vector3(lx, ly, lz)), 0.05, 0.05, -0.18, 0.18, 6, Color(0.46, 0.32, 0.2))
	return k.commit()


## A small soldier, ~0.62 m tall, facing +Z.
static func soldier(team: Color, trim: Color, p_seed: int, raider := false) -> ArrayMesh:
	var k := MeshKit.new(p_seed)
	k.set_sway(0.0)
	var skin := Color(0.88, 0.68, 0.54)
	var dark := Color(0.2, 0.17, 0.15)
	var steel := Color(0.62, 0.64, 0.66)
	# Legs and boots.
	for sx in [-1, 1]:
		k.box(Transform3D(Basis(), Vector3(sx * 0.045, 0.09, 0)), Vector3(0.065, 0.18, 0.08), dark)
	# Tunic (flared) and belt.
	k.cylinder(Transform3D.IDENTITY, 0.12, 0.095, 0.15, 0.40, 8, team)
	k.cylinder(Transform3D.IDENTITY, 0.105, 0.105, 0.24, 0.27, 8, Color(0.3, 0.2, 0.12), false)
	# Shoulders / arms.
	for sx in [-1, 1]:
		k.box(Transform3D(Basis(Vector3(0, 0, 1), sx * 0.25), Vector3(sx * 0.12, 0.33, 0.01)), Vector3(0.06, 0.16, 0.07), team.darkened(0.1))
	# Head and helmet.
	k.blob(Vector3(0, 0.47, 0), Vector3(0.068, 0.075, 0.068), skin, 0.0, 1)
	if raider:
		k.blob(Vector3(0, 0.50, 0), Vector3(0.078, 0.06, 0.078), steel, 0.0, 1)
		for sx in [-1, 1]:
			k.cylinder(Transform3D(Basis(Vector3(0, 0, 1), -sx * 1.0), Vector3(sx * 0.06, 0.53, 0)), 0.018, 0.0, 0.0, 0.09, 5, Color(0.9, 0.86, 0.74))
		k.blob(Vector3(0, 0.425, 0.045), Vector3(0.06, 0.045, 0.03), Color(0.62, 0.32, 0.14), 0.1, 1)
	else:
		k.cylinder(Transform3D.IDENTITY, 0.082, 0.02, 0.48, 0.6, 8, steel)
		k.cylinder(Transform3D.IDENTITY, 0.09, 0.09, 0.475, 0.49, 8, steel, false)
	# Round shield on the left arm.
	var shield_xf := Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5) * Basis(Vector3(1, 0, 0), 0.0), Vector3(-0.16, 0.3, 0.04))
	k.cylinder(Transform3D(Basis(Vector3(0, 1, 0), -0.3) * Basis(Vector3(0, 0, 1), PI * 0.5), Vector3(-0.15, 0.3, 0.05)), 0.13, 0.13, -0.015, 0.015, 10, trim)
	k.cylinder(Transform3D(Basis(Vector3(0, 1, 0), -0.3) * Basis(Vector3(0, 0, 1), PI * 0.5), Vector3(-0.165, 0.3, 0.05)), 0.035, 0.02, 0.0, 0.03, 6, steel, false)
	# Spear in the right hand.
	var spear := Transform3D(Basis(Vector3(1, 0, 0), 0.12), Vector3(0.15, 0.02, 0.02))
	k.cylinder(spear, 0.012, 0.012, 0.0, 0.95, 5, Color(0.5, 0.38, 0.25), false)
	k.cylinder(spear, 0.028, 0.0, 0.95, 1.06, 4, steel, false)
	return k.commit()


## Longboat hull lofted from cross sections, with shields, mast and sail.
static func longboat(p_seed: int) -> ArrayMesh:
	var k := MeshKit.new(p_seed)
	k.set_sway(0.0)
	var length := 5.0
	var half_w := 0.72
	var wood := Color(0.42, 0.29, 0.19)
	var wood_dark := Color(0.30, 0.20, 0.13)
	var sections := 14
	var prev := []
	for s in sections + 1:
		var t := float(s) / sections
		var z := (t - 0.5) * length
		var wf := pow(sin(PI * t), 0.55)
		var w := half_w * wf
		var rise := pow(absf(t - 0.5) * 2.0, 3.0) * 0.55   # sheer: ends sweep up
		var keel := Vector3(0, -0.28 * wf + rise * 0.6, z)
		var mid_l := Vector3(-w * 0.92, 0.0 + rise * 0.8, z)
		var top_l := Vector3(-w, 0.32 + rise, z)
		var mid_r := Vector3(w * 0.92, 0.0 + rise * 0.8, z)
		var top_r := Vector3(w, 0.32 + rise, z)
		var cur := [keel, mid_l, top_l, mid_r, top_r]
		if s > 0:
			var strake := wood if s % 2 == 0 else wood_dark
			k.quad(prev[0], cur[0], cur[1], prev[1], strake, Vector3(-1, -1, 0))
			k.quad(prev[1], cur[1], cur[2], prev[2], strake.lightened(0.06), Vector3(-1, 0, 0))
			k.quad(prev[0], prev[3], cur[3], cur[0], strake, Vector3(1, -1, 0))
			k.quad(prev[3], prev[4], cur[4], cur[3], strake.lightened(0.06), Vector3(1, 0, 0))
			# Inner deck.
			var dy := 0.08
			k.quad(prev[1] + Vector3(0, dy, 0), prev[3] + Vector3(0, dy, 0), cur[3] + Vector3(0, dy, 0), cur[1] + Vector3(0, dy, 0), wood.lightened(0.12), Vector3.UP)
			# Inner hull walls.
			k.quad(prev[1] + Vector3(0, dy, 0), prev[2], cur[2], cur[1] + Vector3(0, dy, 0), wood_dark, Vector3(1, 0, 0))
			k.quad(prev[3] + Vector3(0, dy, 0), cur[3] + Vector3(0, dy, 0), cur[4], prev[4], wood_dark, Vector3(-1, 0, 0))
		prev = cur
	# Dragon prow and stern posts.
	for sgn in [-1, 1]:
		var base := Vector3(0, 0.75, sgn * length * 0.5)
		var curl := Transform3D(Basis(Vector3(1, 0, 0), -sgn * 0.5), base)
		k.cylinder(curl, 0.07, 0.05, -0.2, 0.55, 6, wood_dark)
		if sgn == 1:
			k.blob(curl * Vector3(0, 0.62, 0.08), Vector3(0.09, 0.08, 0.16), wood_dark, 0.1, 1)
	# Shields along the gunwales.
	var shield_cols := [Color(0.75, 0.2, 0.16), Color(0.92, 0.84, 0.6), Color(0.2, 0.3, 0.45)]
	for side in [-1, 1]:
		for i in 7:
			var t := 0.2 + i * 0.1
			var z := (t - 0.5) * length
			var w := half_w * pow(sin(PI * t), 0.55)
			var xf := Transform3D(Basis(Vector3(0, 0, 1), side * PI * 0.5), Vector3(side * (w + 0.02), 0.3, z))
			k.cylinder(xf, 0.17, 0.17, -0.015, 0.015, 10, shield_cols[i % 3])
	# Mast, yard and striped sail.
	k.cylinder(Transform3D(Basis(), Vector3(0, 0, 0.2)), 0.05, 0.035, 0.0, 3.0, 6, wood_dark)
	k.cylinder(Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5), Vector3(0, 2.75, 0.24)), 0.03, 0.03, -1.25, 1.25, 5, wood_dark)
	var stripes := 6
	for s in stripes:
		var x0 := -1.15 + 2.3 * s / stripes
		var x1 := -1.15 + 2.3 * (s + 1) / stripes
		var col := Color(0.78, 0.18, 0.14) if s % 2 == 0 else Color(0.94, 0.9, 0.8)
		var bulge := 0.22
		var steps := 4
		for v in steps:
			var y0 := 2.72 - 1.7 * v / steps
			var y1 := 2.72 - 1.7 * (v + 1) / steps
			var b0 := sin(PI * float(v) / steps) * bulge
			var b1 := sin(PI * float(v + 1) / steps) * bulge
			var a := Vector3(x0, y0, 0.28 + b0 * (1.0 - absf(x0) * 0.4))
			var b := Vector3(x1, y0, 0.28 + b0 * (1.0 - absf(x1) * 0.4))
			var c := Vector3(x1, y1, 0.28 + b1 * (1.0 - absf(x1) * 0.4))
			var d := Vector3(x0, y1, 0.28 + b1 * (1.0 - absf(x0) * 0.4))
			k.quad(a, b, c, d, col, Vector3(0, 0, 1))
			k.quad(a, d, c, b, col.darkened(0.1), Vector3(0, 0, -1))
	return k.commit()


## One masonry block of the destructible tower.
static func stone_block(size: Vector3, p_seed: int) -> ArrayMesh:
	var k := MeshKit.new(p_seed)
	k.set_sway(0.0)
	var c := Color(0.55, 0.52, 0.47).lightened(k.rng.randf_range(-0.12, 0.05))
	# Slightly bevelled: inner box plus a thinner face box per axis.
	var bev := 0.025
	k.box(Transform3D.IDENTITY, size - Vector3(bev, bev, bev) * 2.0, c)
	k.box(Transform3D.IDENTITY, Vector3(size.x, size.y - bev * 2.0, size.z - bev * 2.0), c)
	k.box(Transform3D.IDENTITY, Vector3(size.x - bev * 2.0, size.y, size.z - bev * 2.0), c.lightened(0.04))
	k.box(Transform3D.IDENTITY, Vector3(size.x - bev * 2.0, size.y - bev * 2.0, size.z), c)
	return k.commit()
