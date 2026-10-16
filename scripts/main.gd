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
const NavGrid := preload("res://scripts/world/nav_grid.gd")
const RampCarver := preload("res://scripts/world/ramp_carver.gd")
const Battle := preload("res://scripts/gameplay/battle.gd")
const Director := preload("res://scripts/gameplay/raid_director.gd")
const Commander := preload("res://scripts/gameplay/commander.gd")
const Hud := preload("res://scripts/ui/hud.gd")
const Atmosphere := preload("res://scripts/world/atmosphere.gd")
const PauseMenu := preload("res://scripts/ui/pause_menu.gd")

static var island_seed := 7
static var attract := false     # title-screen backdrop: no HUD, self-playing
var ended := false
var _attract_restart := -1.0
const CHAR_SCALE := 0.28

var island
var rig
var tower
var sun: DirectionalLight3D
var noise_tex: ImageTexture
var detail_tex: ImageTexture
var prop_mat: ShaderMaterial
var foliage_mat: ShaderMaterial
var terrain_mat: ShaderMaterial
var water_mat: ShaderMaterial
var grass_mat: ShaderMaterial
var atmosphere
var paths
var nav
var carver
var scatter
var house_records: Array = []
var defender_spots: Array = []
var battle
var director
var commander
var hud


func _ready() -> void:
	if Capture.has("campaign") and not Campaign.active:
		Campaign.new_campaign(5)
		Campaign.sail_to(0)
	if Capture.has("seed"):
		island_seed = int(Capture.arg("seed"))
	elif Campaign.active and not Campaign.current.is_empty():
		island_seed = int(Campaign.current["seed"])
	elif attract:
		island_seed = randi_range(1, 99999)
	var t0 := Time.get_ticks_msec()
	island = IslandData.new(island_seed)
	nav = NavGrid.new(island)
	carver = RampCarver.new(island, nav)
	carver.run()
	var rr := RandomNumberGenerator.new()
	rr.seed = island_seed * 13
	carver.add_shortcuts(4, rr)
	nav.build_astar()
	var t_nav := Time.get_ticks_msec()
	print("nav + %d ramps in %d ms" % [carver.ramps.size(), t_nav - t0])
	if Capture.has("navdump"):
		_dump_nav()
	noise_tex = Tex.noise(island_seed + 1, 512, 0.012, 5)
	detail_tex = Tex.noise(island_seed + 2, 256, 0.05, 3)
	_build_materials()
	atmosphere = Atmosphere.new(Atmosphere.pick(island_seed))
	add_child(atmosphere)
	_build_environment()
	_build_terrain()
	_build_water()
	scatter = Scatter.new(island, island_seed)
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
	grass_mat = _grass_material()
	scatter.build_grass(veg, grass_mat, foliage_mat)
	atmosphere.configure_materials(terrain_mat, water_mat, grass_mat, foliage_mat)
	var doors := []
	for h in house_records:
		doors.append(h["door"])
	if tower:
		atmosphere.add_lanterns(self, doors, island, tower.position + Vector3(0, tower.block_h * tower.rings, 0))
	_build_camera()
	atmosphere.start_weather(rig)
	_build_battle()
	print("island %d built in %d ms, houses=%d spots=%d" % [island_seed, Time.get_ticks_msec() - t0, house_records.size(), defender_spots.size()])
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


func _dump_nav() -> void:
	var img := Image.create(nav.n, nav.n, false, Image.FORMAT_RGB8)
	var sizes: Dictionary = nav.component_sizes()
	for k in nav.n * nav.n:
		var c: int = nav.component[k]
		var h: float = nav.heights[k]
		var col := Color(0.05, 0.1, 0.3) if h < 0.0 else Color(0.2, 0.2, 0.2)
		if c >= 0 and h >= 0.0:
			var hue := fposmod(c * 0.618, 1.0)
			col = Color.from_hsv(hue, 0.7, 0.4 + 0.5 * clampf(h / 4.0, 0.0, 1.0))
		img.set_pixel(k % nav.n, k / nav.n, col)
	for r in carver.ramps:
		for t in 20:
			var p: Vector2 = (r["start"] as Vector2).lerp(r["end"], t / 19.0)
			var c: Vector2i = nav.cell_of(p)
			img.set_pixel(c.x, c.y, Color.WHITE)
	img.resize(nav.n * 4, nav.n * 4, Image.INTERPOLATE_NEAREST)
	img.save_png("res://shots/nav.png")
	print("components: ", sizes)


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
	env.ambient_light_energy = 0.7
	env.ambient_light_color = Color(0.62, 0.58, 0.52)
	env.ambient_light_sky_contribution = 0.6
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
	# Sun is created below; atmosphere fills in the per-island look afterwards.

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
	atmosphere.configure_environment(env, sky_mat, sun)


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
	mi.layers = 1 | 2   # layer 2: receives UI decals
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
	water_mat = m
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

	# Houses around the tower. Placement relaxes in passes so every island,
	# however rugged, gets a proper village: same terrace first, then wider,
	# then any reachable flat ground.
	var tower_comp: int = nav.component[nav.idx(nav.nearest_walkable(Vector2(tp.x + 2.4, tp.z)))]
	var houses := 0
	var placed: Array[Vector3] = [tp]
	var passes := [[0.3, 11.0, 0.08], [0.3, 14.0, 0.1], [99.0, 14.0, 0.12], [99.0, 18.0, 0.16]]
	for pass_i in passes.size():
		if houses >= 6:
			break
		var max_dh: float = passes[pass_i][0]
		var max_r: float = passes[pass_i][1]
		var max_flat: float = passes[pass_i][2]
		var pool: Array[Vector3] = candidates
		if pass_i >= 2:
			pool = _loose_candidates(tp, max_r, max_flat)
		for c in pool:
			if houses >= 7:
				break
			if absf(c.y - tp.y) > max_dh or Vector2(c.x - tp.x, c.z - tp.z).length() > max_r:
				continue
			var cc: Vector2i = nav.cell_of(Vector2(c.x, c.z))
			if not nav.is_walkable(cc) or nav.component[nav.idx(cc)] != tower_comp:
				continue
			var ok := true
			for p in placed:
				if Vector2(c.x - p.x, c.z - p.z).length() < (3.6 if p != tp else 3.4):
					ok = false
					break
			if not ok:
				continue
			placed.append(c)
			_place_house(c, tp, rng, absf(c.y - tp.y) < 0.3)
			houses += 1
	paths.blob(Vector2(tp.x, tp.z), 2.3)

	# Rally points for the defending squads, around the village square.
	var tries := 0
	while defender_spots.size() < 4 and tries < 800:
		tries += 1
		var ang := rng.randf() * TAU
		var reach := 2.8 + tries * 0.012
		var centre := Vector2(tp.x, tp.z) + Vector2(cos(ang), sin(ang)) * rng.randf_range(2.8, reach + 2.0)
		var dh_limit := 0.35 if tries < 400 else 99.0
		var clear: bool = absf(island.height_at(centre.x, centre.y) - tp.y) < dh_limit and island.flatness(centre.x, centre.y, 0.8) < 0.15
		clear = clear and nav.is_walkable(nav.cell_of(centre)) and nav.component[nav.idx(nav.cell_of(centre))] == tower_comp
		for p in placed.slice(1):
			if Vector2(centre.x - p.x, centre.y - p.z).length() < 2.9:
				clear = false
		for q in defender_spots:
			if centre.distance_to(q["pos"]) < 2.6:
				clear = false
		if not clear:
			continue
		defender_spots.append({"pos": centre, "facing": atan2(centre.x - tp.x, centre.y - tp.z)})
		scatter.block(centre.x, centre.y, 1.2)


## Candidate building spots on any terrace, for rugged islands.
func _loose_candidates(tp: Vector3, max_r: float, max_flat: float) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for j in range(int(tp.z - max_r), int(tp.z + max_r) + 1):
		for i in range(int(tp.x - max_r), int(tp.x + max_r) + 1):
			var x := float(i)
			var z := float(j)
			var h: float = island.height_at(x, z)
			if h < island.BEACH_H + 0.15:
				continue
			if island.flatness(x, z, 1.6) > max_flat:
				continue
			out.append(Vector3(x, h, z))
	out.sort_custom(func(a: Vector3, b: Vector3) -> bool:
		return Vector2(a.x - tp.x, a.z - tp.z).length() < Vector2(b.x - tp.x, b.z - tp.z).length())
	return out


func _place_house(c: Vector3, tp: Vector3, rng: RandomNumberGenerator, with_path: bool) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = Props.house(rng.randi())
	mi.material_override = prop_mat
	# Face roughly toward the tower, like a square.
	var to_tower := Vector2(tp.x - c.x, tp.z - c.z)
	mi.rotation.y = atan2(to_tower.x, to_tower.y) + rng.randf_range(-0.3, 0.3)
	mi.position = Vector3(c.x, c.y - 0.06, c.z)
	add_child(mi)
	# Solid walls so tower rubble piles up against the house.
	var aabb := mi.mesh.get_aabb()
	var hb := StaticBody3D.new()
	var hs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(aabb.size.x - 0.3, aabb.size.y * 0.75, aabb.size.z - 0.45)
	hs.shape = box
	hs.position = aabb.get_center() - Vector3(0, aabb.size.y * 0.1, 0)
	hb.add_child(hs)
	mi.add_child(hb)
	scatter.block(c.x, c.z, 1.5)
	var facing := Vector2(sin(mi.rotation.y), cos(mi.rotation.y))
	var door := Vector2(c.x, c.z) + facing * 0.95
	if with_path:
		paths.segment(Vector2(tp.x, tp.z), door)
	paths.blob(door, 0.5)
	house_records.append({"pos": Vector2(c.x, c.z), "node": mi, "door": Vector2(c.x, c.z) + facing * 1.3})


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
		"top":
			rig.set_view(0.0, -80.0, 75.0, Vector3.ZERO)
		"custom":
			# --view=yaw,pitch,dist,x,y,z
			var v := Capture.arg("view", "35,-40,30,0,1,0").split(",")
			rig.set_view(float(v[0]), float(v[1]), float(v[2]), Vector3(float(v[3]), float(v[4]), float(v[5])))


func _build_battle() -> void:
	battle = Battle.new()
	battle.name = "Battle"
	add_child(battle)
	battle.setup(island, nav, prop_mat)
	battle.tower = tower
	for h in house_records:
		battle.register_house(h["pos"], h["node"], h["door"])

	var knight := preload("res://assets/kaykit/characters/Knight.glb")
	var rogue := preload("res://assets/kaykit/characters/Rogue_Hooded.glb")
	var barbarian := preload("res://assets/kaykit/characters/Barbarian.glb")
	var shield_vis := {"scene": knight, "keep": ["1H_Sword", "Rectangle_Shield"], "scale": CHAR_SCALE}
	var sword_vis := {"scene": knight, "keep": ["2H_Sword"], "scale": CHAR_SCALE}
	var xbow_vis := {"scene": rogue, "keep": ["1H_Crossbow"], "scale": CHAR_SCALE}
	var visuals := {"shield": shield_vis, "sword": sword_vis, "archer": xbow_vis}
	# Campaign: field the living roster. Quick battle: one of each, fully trained in abilities.
	var plan := []
	if Campaign.active:
		for r in Campaign.living_squads():
			plan.append({"kind": r["kind"], "name": r["name"], "level": r["level"], "ability": r["ability"], "id": r["id"]})
	else:
		plan = [{"kind": "shield", "name": "Shieldwall", "level": 1, "ability": true, "id": -1},
			{"kind": "sword", "name": "Swordsmen", "level": 1, "ability": true, "id": -1},
			{"kind": "archer", "name": "Crossbows", "level": 1, "ability": true, "id": -1}]
	for i in mini(plan.size(), defender_spots.size()):
		var spot: Dictionary = defender_spots[i]
		var p: Dictionary = plan[i]
		var size: int = Campaign.KINDS[p["kind"]]["size"]
		var sq = battle.spawn_squad(Battle.PLAYER, p["kind"], p["name"], visuals[p["kind"]], spot["pos"], size, spot["facing"], {}, p["level"])
		sq.ability_unlocked = p["ability"]
		sq.set_meta("roster_id", p["id"])

	director = Director.new()
	director.name = "RaidDirector"
	add_child(director)
	var sk := "res://assets/kaykit/skeletons/"
	var enemy_vis := {
		"raider": {"scene": barbarian, "keep": ["1H_Axe", "Barbarian_Round_Shield"], "scale": CHAR_SCALE},
		"berserker": {"scene": barbarian, "keep": ["2H_Axe"], "scale": CHAR_SCALE * 1.05},
		"chieftain": {"scene": barbarian, "keep": ["2H_Axe"], "scale": CHAR_SCALE * 1.45},
		"draugr": {"scene": load(sk + "Skeleton_Minion.glb"), "keep": [], "scale": CHAR_SCALE,
			"attach": {"handslot_r": sk + "Skeleton_Blade.gltf", "handslot_l": sk + "Skeleton_Shield_Small_A.gltf"}},
		"draugr_archer": {"scene": load(sk + "Skeleton_Rogue.glb"), "keep": [], "scale": CHAR_SCALE,
			"attach": {"handslot_r": sk + "Skeleton_Crossbow.gltf"}},
		"champion": {"scene": load(sk + "Skeleton_Warrior.glb"), "keep": [], "scale": CHAR_SCALE * 1.25,
			"attach": {"handslot_r": sk + "Skeleton_Axe.gltf", "handslot_l": sk + "Skeleton_Shield_Large_A.gltf"}},
	}
	director.setup(battle, island, nav, Props.longboat(island_seed), enemy_vis, prop_mat, island_seed * 5 + 1)
	director.victory.connect(func(): battle.cheer(Battle.PLAYER))
	director.defeat.connect(func(): battle.cheer(Battle.RAIDERS))
	if Campaign.active and not Campaign.current.is_empty():
		director.waves = Campaign.waves_for(Campaign.current)
	if Capture.has("wave"):
		director.waves[0]["delay"] = float(Capture.arg("wave"))
	director.victory.connect(_on_battle_end.bind(true))
	director.defeat.connect(_on_battle_end.bind(false))
	if attract:
		rig.set_view(rad_to_deg(rig.yaw), -34.0, 48.0, Vector3(0, 1.0, 0))
		return

	commander = Commander.new()
	commander.name = "Commander"
	add_child(commander)
	commander.setup(battle, nav, island, rig)
	battle.impact.connect(commander.impact)
	director.wave_cleared.connect(func(_i): commander.dramatic(1.4))

	hud = Hud.new()
	add_child(hud)
	hud.setup(battle, director, commander)
	hud.card_pressed.connect(commander.select)
	var threats := preload("res://scripts/ui/threat_overlay.gd").new()
	hud.get_child(0).add_child(threats)
	hud.get_child(0).move_child(threats, 0)
	threats.setup(director, battle, island, rig)
	var island_name: String = Campaign.current.get("name", "") if Campaign.active else ""
	if island_name == "":
		island_name = "Hold the island"
	hud.show_banner(island_name, "%s  ·  Raiders are coming. Keep the village standing." % atmosphere.label(), 5.0)
	hud.topple_pressed.connect(commander.arm_topple)
	if Capture.has("speed"):
		Engine.time_scale = float(Capture.arg("speed"))
		commander.base_speed = Engine.time_scale
		Engine.physics_ticks_per_second = 60
		Engine.max_physics_steps_per_frame = 16


var _auto_t := 0.0


## Debug/demo autopilot: idle defenders march on the nearest raiders.
func _autoplay(dt: float) -> void:
	_auto_t -= dt
	if _auto_t > 0.0:
		return
	_auto_t = 1.5
	for s in battle.squads:
		if s.team != battle.PLAYER or s.is_dead() or s.order != 0:
			continue
		var c: Vector2 = battle._centroid(s)
		if s.ability_ready():
			var foe := Vector2.INF
			for u in battle.units:
				if u.alive() and u.team == battle.RAIDERS and not u.boarded and u.hop_t < 0.0 and c.distance_to(u.pos) < c.distance_to(foe):
					foe = u.pos
			if foe != Vector2.INF:
				var fd := c.distance_to(foe)
				if (s.ability == "brace" and fd < 2.0) or (s.ability == "charge" and fd > 2.5 and fd < 9.0) or (s.ability == "volley" and fd < 10.0):
					battle.use_ability(s, foe)
					continue
		# Badly hurt and not fighting: go refit at the nearest house.
		if s.alive_count() * 2 < s.units.size() and not s.in_combat and s.refit_cooldown <= 0.0:
			var home = null
			for h in battle.intact_houses():
				if home == null or c.distance_to(h["door"]) < c.distance_to(home["door"]):
					home = h
			if home != null and c.distance_to(home["door"]) > 1.2:
				var hp: PackedVector2Array = nav.find_path(s.anchor, home["door"])
				if not hp.is_empty():
					s.set_path(hp, false)
				continue
			if home != null:
				continue
		# A burning house takes priority over chasing.
		var burning = null
		for h in battle.intact_houses():
			if h["burning"] and (burning == null or c.distance_to(h["pos"]) < c.distance_to(burning["pos"])):
				burning = h
		if burning != null and s.kind != "archer" and c.distance_to(burning["door"]) > 2.0:
			var bp: PackedVector2Array = nav.find_path(s.anchor, burning["door"])
			if not bp.is_empty():
				s.set_path(bp, true)
				continue
		var best := Vector2.INF
		for u in battle.units:
			if u.alive() and u.team == battle.RAIDERS and not u.boarded and u.hop_t < 0.0:
				if c.distance_to(u.pos) < c.distance_to(best):
					best = u.pos
		if best == Vector2.INF or c.distance_to(best) < (6.0 if s.kind == "archer" else 2.0):
			continue
		var goal: Vector2 = best if s.kind != "archer" else c.lerp(best, 1.0 - 7.0 / c.distance_to(best))
		var p: PackedVector2Array = nav.find_path(s.anchor, goal)
		if not p.is_empty():
			s.set_path(p, false)


func _on_battle_end(_won: bool) -> void:
	ended = true
	if Capture.has("campaign"):
		get_tree().create_timer(2.0).timeout.connect(_continue_campaign)
	if attract:
		_attract_restart = 6.0


## Campaign: record the result and return to the sea chart.
func _continue_campaign() -> void:
	var survivors := {}
	for s in battle.squads:
		if s.team == Battle.PLAYER and s.has_meta("roster_id"):
			survivors[s.get_meta("roster_id")] = s.alive_count()
	var won: bool = director.raiders_alive() == 0 and survivors.values().any(func(v): return v > 0)
	Campaign.finish_island(won, battle.intact_houses().size(), battle.houses.size(), survivors)
	Engine.time_scale = 1.0
	Fader.go("res://scenes/camp.tscn")


func _process(dt: float) -> void:
	if attract:
		rig.set_view(rad_to_deg(rig.yaw) + dt * 2.5, -34.0, 48.0, Vector3(0, 1.0, 0), false)
		if _attract_restart > 0.0:
			_attract_restart -= dt
			if _attract_restart <= 0.0:
				var fresh: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
				get_parent().add_child(fresh)
				queue_free()
				return
	if Capture.has("dumpai") and Capture.frame() == int(Capture.arg("frames")) - 2:
		for sq in battle.squads:
			if sq.is_dead():
				continue
			var lines := []
			for u in sq.units:
				if u.alive():
					lines.append("%s b=%s hop=%.1f pos=%s h=%.2f tgt=%s" % [u.kind, u.boarded, u.hop_t, u.pos, island.height_at(u.pos.x, u.pos.y), u.target != null])
			print("SQUAD team=%d order=%d anchor=%s path=%d/%d alive=%d
  %s" % [sq.team, sq.order, sq.anchor, sq.path_i, sq.path.size(), sq.alive_count(), "
  ".join(lines)])
	if battle:
		scatter.update_tree_fade(battle.units, dt)
	if (Capture.has("autoplay") or attract) and battle:
		_autoplay(dt)
	# Capture helper: keep the camera on the fighting.
	if Capture.arg("cam") == "follow" and battle:
		var c := Vector2.ZERO
		var n := 0
		for u in battle.units:
			if u.alive() and u.team == battle.RAIDERS and not u.boarded:
				c += u.pos
				n += 1
		if n > 0:
			c /= n
			rig.set_view(rad_to_deg(rig.yaw), -36.0, float(Capture.arg("dist", "24")), Vector3(c.x, island.height_at(c.x, c.y), c.y), false)


func _strike_tower() -> void:
	if battle and battle.topple_tower(Vector2(1, 0.3)):
		rig.add_shake(1.0)


func _unhandled_input(event: InputEvent) -> void:
	if Capture.has("capture") or attract:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if ended and Campaign.active and event.physical_keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
			_continue_campaign()
			return
		match event.physical_keycode:
			KEY_ESCAPE:
				if not get_tree().paused:
					Engine.time_scale = 1.0
					add_child(PauseMenu.new())
			KEY_R:
				if Campaign.active:
					return
				Engine.time_scale = 1.0
				get_tree().reload_current_scene()
			KEY_N:
				if Campaign.active:
					return
				Engine.time_scale = 1.0
				island_seed += 1
				get_tree().reload_current_scene()
			KEY_F12:
				var img := get_viewport().get_texture().get_image()
				img.save_png("res://shots/manual_%d.png" % Time.get_ticks_msec())
