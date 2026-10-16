extends Node3D
## Look-development scene: builds a full procedural island diorama.
## Controls: WASD pan, Q/E or right-drag orbit, wheel zoom,
## Space strike the tower, N new island, F1 hide hints.

const IslandData := preload("res://scripts/world/island_data.gd")
const TerrainBuilder := preload("res://scripts/world/terrain_builder.gd")
const Scatter := preload("res://scripts/world/scatter.gd")
const Props := preload("res://scripts/world/props.gd")
const Tex := preload("res://scripts/core/tex.gd")
const CameraRig := preload("res://scripts/core/camera_rig.gd")
const Tower := preload("res://scripts/gameplay/destructible_tower.gd")
const Paths := preload("res://scripts/world/paths.gd")

static var island_seed := 7

var island
var rig
var tower
var sun: DirectionalLight3D
var noise_tex: ImageTexture
var detail_tex: ImageTexture
var prop_mat: ShaderMaterial
var foliage_mat: ShaderMaterial
var terrain_mat: ShaderMaterial
var paths
var squads: Array[Node3D] = []
var boats: Array[Node3D] = []


func _ready() -> void:
	if Capture.has("seed"):
		island_seed = int(Capture.arg("seed"))
	var t0 := Time.get_ticks_msec()
	island = IslandData.new(island_seed)
	noise_tex = Tex.noise(island_seed + 1, 512, 0.012, 5)
	detail_tex = Tex.noise(island_seed + 2, 256, 0.05, 3)
	_build_materials()
	_build_environment()
	_build_terrain()
	_build_water()
	var scatter := Scatter.new(island, island_seed)
	paths = Paths.new(island_seed)
	scatter.paths = paths
	_build_settlement(scatter)
	terrain_mat.set_shader_parameter("path_mask", paths.texture())
	terrain_mat.set_shader_parameter("path_extent", Paths.EXTENT)
	var veg := Node3D.new()
	veg.name = "Vegetation"
	add_child(veg)
	scatter.build_trees(veg, foliage_mat)
	scatter.build_rocks(veg, prop_mat)
	scatter.build_grass(veg, _grass_material(), foliage_mat)
	_build_raiders()
	_build_camera()
	print("island %d built in %d ms" % [island_seed, Time.get_ticks_msec() - t0])
	if Capture.has("pick"):
		_debug_pick.call_deferred()
	if Capture.has("collapse"):
		var at := int(Capture.arg("collapse"))
		_strike_after_frames(at)


## Debug: --pick=x,y prints the terrain point under that screen pixel.
func _debug_pick() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	for spec in Capture.arg("pick").split(";"):
		var xy := spec.split(",")
		var px := Vector2(float(xy[0]), float(xy[1]))
		var cam: Camera3D = rig.camera
		var from := cam.project_ray_origin(px)
		var to := from + cam.project_ray_normal(px) * 500.0
		var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, to))
		print("pick %s -> %s" % [px, hit.get("position", "none")])


func _strike_after_frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
	_strike_tower()


func _build_materials() -> void:
	prop_mat = ShaderMaterial.new()
	prop_mat.shader = preload("res://shaders/prop.gdshader")
	prop_mat.set_shader_parameter("noise_tex", noise_tex)
	prop_mat.set_shader_parameter("wind_strength", 0.0)
	foliage_mat = ShaderMaterial.new()
	foliage_mat.shader = preload("res://shaders/prop.gdshader")
	foliage_mat.set_shader_parameter("noise_tex", noise_tex)
	foliage_mat.set_shader_parameter("wind_strength", 0.05)
	foliage_mat.set_shader_parameter("roughness", 0.9)
	foliage_mat.set_shader_parameter("translucency", 0.15)


func _grass_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = preload("res://shaders/grass.gdshader")
	m.set_shader_parameter("noise_tex", noise_tex)
	return m


func _build_environment() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.32, 0.52, 0.78)
	sky_mat.sky_horizon_color = Color(0.74, 0.82, 0.88)
	sky_mat.ground_horizon_color = Color(0.74, 0.82, 0.88)
	sky_mat.ground_bottom_color = Color(0.2, 0.36, 0.48)
	sky_mat.sun_angle_max = 20.0
	sky_mat.sun_curve = 0.1
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.65
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	env.ssao_enabled = true
	env.ssao_radius = 1.4
	env.ssao_intensity = 2.2
	env.ssao_power = 1.6
	env.ssao_detail = 0.6
	env.ssil_enabled = not Capture.has("nossil")
	env.ssil_radius = 4.0
	env.ssil_intensity = 0.6
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.fog_enabled = true
	env.fog_light_color = Color(0.72, 0.8, 0.86)
	env.fog_density = 0.0016
	env.fog_sky_affect = 0.0
	env.fog_aerial_perspective = 0.15
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.18
	env.adjustment_contrast = 1.06
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-38.0), deg_to_rad(-62.0), 0.0)
	sun.light_color = Color(1.0, 0.92, 0.80)
	sun.light_energy = 2.1
	sun.shadow_enabled = true
	sun.shadow_blur = 1.2
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 140.0
	sun.directional_shadow_blend_splits = true
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 1.2
	add_child(sun)


func _build_terrain() -> void:
	var mi := MeshInstance3D.new()
	mi.name = "Terrain"
	mi.mesh = TerrainBuilder.build_mesh(island)
	var m := ShaderMaterial.new()
	terrain_mat = m
	m.shader = preload("res://shaders/terrain.gdshader")
	m.set_shader_parameter("noise_tex", noise_tex)
	m.set_shader_parameter("detail_tex", detail_tex)
	m.set_shader_parameter("beach_h", island.BEACH_H)
	m.set_shader_parameter("level_h", island.LEVEL_H)
	mi.material_override = m
	add_child(mi)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = TerrainBuilder.build_collision(island, 2)
	body.add_child(cs)
	add_child(body)


func _build_water() -> void:
	var mi := MeshInstance3D.new()
	mi.name = "Water"
	var plane := PlaneMesh.new()
	plane.size = Vector2(900, 900)
	plane.subdivide_width = 200
	plane.subdivide_depth = 200
	mi.mesh = plane
	var m := ShaderMaterial.new()
	m.shader = preload("res://shaders/water.gdshader")
	m.set_shader_parameter("normal_a", Tex.normal_map(island_seed + 5, 256, 0.04, 6.0))
	m.set_shader_parameter("normal_b", Tex.normal_map(island_seed + 6, 256, 0.025, 4.0))
	m.set_shader_parameter("foam_noise", detail_tex)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	# Seabed beyond the generated field so deep water never shows a seam.
	var bed := MeshInstance3D.new()
	var bp := PlaneMesh.new()
	bp.size = Vector2(900, 900)
	bed.mesh = bp
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.32, 0.36, 0.34)
	bm.roughness = 1.0
	bed.material_override = bm
	bed.position.y = island.SEA_FLOOR - 0.05
	add_child(bed)


## Finds the flattest, highest plateau spots and places a small village and the tower.
func _build_settlement(scatter) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = island_seed * 31
	var candidates: Array[Vector3] = []
	for j in range(-22, 23, 1):
		for i in range(-22, 23, 1):
			var x := float(i)
			var z := float(j)
			var h: float = island.height_at(x, z)
			if h < island.BEACH_H + island.LEVEL_H * 0.6:
				continue
			if island.flatness(x, z, 1.6) > 0.08:
				continue
			candidates.append(Vector3(x, h, z))
	candidates.sort_custom(func(a: Vector3, b: Vector3) -> bool:
		return a.y - Vector2(a.x, a.z).length() * 0.02 > b.y - Vector2(b.x, b.z).length() * 0.02)
	if candidates.is_empty():
		return
	# Tower on the best spot.
	var tp := candidates[0]
	tower = Tower.new()
	tower.name = "Tower"
	add_child(tower)
	tower.position = Vector3(tp.x, tp.y - 0.04, tp.z)
	tower.build(prop_mat, island_seed)
	scatter.block(tp.x, tp.z, 1.9)

	# Houses near the tower on the same terrace.
	var houses := 0
	var placed: Array[Vector3] = [tp]
	for c in candidates:
		if houses >= 7:
			break
		if absf(c.y - tp.y) > 0.3 or Vector2(c.x - tp.x, c.z - tp.z).length() > 11.0:
			continue
		var ok := true
		for p in placed:
			if Vector2(c.x - p.x, c.z - p.z).length() < 3.0:
				ok = false
				break
		if not ok:
			continue
		placed.append(c)
		var mi := MeshInstance3D.new()
		mi.mesh = Props.house(rng.randi())
		mi.material_override = prop_mat
		# Face roughly toward the tower, like a square.
		var to_tower := Vector2(tp.x - c.x, tp.z - c.z)
		mi.rotation.y = atan2(to_tower.x, to_tower.y) + rng.randf_range(-0.3, 0.3)
		mi.position = Vector3(c.x, c.y - 0.06, c.z)
		add_child(mi)
		scatter.block(c.x, c.z, 1.5)
		var door := Vector2(c.x, c.z) + Vector2(sin(mi.rotation.y), cos(mi.rotation.y)) * 0.95
		paths.segment(Vector2(tp.x, tp.z), door)
		paths.blob(door, 0.5)
		houses += 1
	paths.blob(Vector2(tp.x, tp.z), 2.3)

	# Defenders: two squads holding the village.
	var blue := Color(0.20, 0.33, 0.62)
	var gold := Color(0.92, 0.80, 0.42)
	var soldier_mesh := Props.soldier(blue, gold, 3)
	var spawned := 0
	for attempt in 40:
		if spawned >= 2:
			break
		var ang := rng.randf() * TAU
		var centre := Vector2(tp.x, tp.z) + Vector2(cos(ang), sin(ang)) * rng.randf_range(2.8, 5.0)
		var clear: bool = absf(island.height_at(centre.x, centre.y) - tp.y) < 0.15 and island.flatness(centre.x, centre.y, 0.8) < 0.1
		for p in placed.slice(1) + squads.map(func(q: Node3D) -> Vector3: return q.get_meta("centre")):
			if Vector2(centre.x - p.x, centre.y - p.z).length() < 2.4:
				clear = false
		if not clear:
			continue
		# Face outward, toward the threat.
		var squad := _spawn_squad(soldier_mesh, centre, atan2(centre.x - tp.x, centre.y - tp.z), 9)
		squad.set_meta("centre", Vector3(centre.x, 0, centre.y))
		squads.append(squad)
		scatter.block(centre.x, centre.y, 1.2)
		spawned += 1


func _spawn_squad(mesh: Mesh, centre: Vector2, facing: float, count: int) -> Node3D:
	var squad := Node3D.new()
	add_child(squad)
	var cols := 3
	for i in count:
		var r := i / cols
		var c := i % cols
		var local := Vector2((c - 1) * 0.42, (r - 1) * 0.42).rotated(-facing)
		var p := centre + local + Vector2(randf_range(-0.05, 0.05), randf_range(-0.05, 0.05))
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = prop_mat
		mi.position = Vector3(p.x, island.height_at(p.x, p.y), p.y)
		mi.rotation.y = facing + randf_range(-0.15, 0.15)
		squad.add_child(mi)
	return squad


## Two longboats running in toward the most exposed beach.
func _build_raiders() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = island_seed * 7 + 3
	var red := Color(0.62, 0.16, 0.12)
	var bone := Color(0.9, 0.84, 0.7)
	var raider := Props.soldier(red, bone, 9, true)
	var boat_mesh := Props.longboat(island_seed)
	var base_ang := rng.randf() * TAU
	for b in 2:
		var ang := base_ang + (b - 0.5) * 0.45
		var dir := Vector2(cos(ang), sin(ang))
		# March inward from open sea until the water gets shallow.
		var dist := 34.0
		while dist > 10.0 and island.height_at(dir.x * dist, dir.y * dist) < -1.6:
			dist -= 0.5
		dist += 3.5 + b * 2.0
		var pos := dir * dist
		var boat := Node3D.new()
		boat.name = "Longboat%d" % b
		add_child(boat)
		boat.position = Vector3(pos.x, 0.02, pos.y)
		boat.rotation.y = atan2(-dir.x, -dir.y)
		var hull := MeshInstance3D.new()
		hull.mesh = boat_mesh
		hull.material_override = prop_mat
		boat.add_child(hull)
		for i in 8:
			var row := i / 2
			var side := (i % 2) * 2 - 1
			var mi := MeshInstance3D.new()
			mi.mesh = raider
			mi.material_override = prop_mat
			mi.position = Vector3(side * 0.28, 0.08, -1.3 + row * 0.62)
			mi.rotation.y = randf_range(-0.3, 0.3)
			boat.add_child(mi)
		boats.append(boat)
		_add_wake(boat)


func _add_wake(boat: Node3D) -> void:
	var p := GPUParticles3D.new()
	p.amount = 120
	p.lifetime = 5.0
	p.local_coords = false
	p.position = Vector3(0, 0.05, -2.2)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.5, 0.0, 0.2)
	pm.direction = Vector3(0, 0, -1)
	pm.spread = 25.0
	pm.initial_velocity_min = 0.2
	pm.initial_velocity_max = 0.5
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.6
	pm.scale_max = 1.2
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.4))
	sc.add_point(Vector2(1, 1.8))
	var sct := CurveTexture.new()
	sct.curve = sc
	pm.scale_curve = sct
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.75))
	g.set_color(1, Color(1, 1, 1, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.5, 0.5)
	q.orientation = PlaneMesh.FACE_Y
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = Tex.radial_soft(64)
	q.material = m
	p.draw_pass_1 = q
	boat.add_child(p)


func _build_camera() -> void:
	rig = CameraRig.new()
	rig.name = "CameraRig"
	add_child(rig)
	var focus := Vector3(0, 1.5, 0)
	match Capture.arg("cam", "wide"):
		"wide":
			rig.set_view(35.0, -42.0, 54.0, focus)
		"close":
			var tp: Vector3 = tower.position if tower else Vector3.ZERO
			rig.set_view(20.0, -30.0, 22.0, tp + Vector3(0, 1.0, 0))
		"boats":
			var bp: Vector3 = boats[0].position if not boats.is_empty() else Vector3.ZERO
			rig.set_view(rad_to_deg(boats[0].rotation.y) + 150.0, -28.0, 20.0, bp.lerp(Vector3.ZERO, 0.35))
		"top":
			rig.set_view(0.0, -80.0, 75.0, Vector3.ZERO)
		"custom":
			# --view=yaw,pitch,dist,x,y,z
			var v := Capture.arg("view", "35,-40,30,0,1,0").split(",")
			rig.set_view(float(v[0]), float(v[1]), float(v[2]), Vector3(float(v[3]), float(v[4]), float(v[5])))


func _process(dt: float) -> void:
	for b in boats:
		b.position += -b.global_transform.basis.z * 0.0 * dt
		var t := Time.get_ticks_msec() * 0.001 + b.position.x
		b.rotation.x = sin(t * 1.1) * 0.025
		b.rotation.z = sin(t * 0.8) * 0.035


func _strike_tower() -> void:
	if tower == null or tower.collapsed:
		return
	var p: Vector3 = tower.global_position + Vector3(randf_range(-0.6, 0.6), 0.9, 1.0)
	tower.collapse(p, 10.0)
	rig.add_shake(0.8)


func _unhandled_input(event: InputEvent) -> void:
	if Capture.has("capture"):
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_SPACE:
				_strike_tower()
			KEY_N:
				island_seed += 1
				get_tree().reload_current_scene()
			KEY_F12:
				var img := get_viewport().get_texture().get_image()
				img.save_png("res://shots/manual_%d.png" % Time.get_ticks_msec())
