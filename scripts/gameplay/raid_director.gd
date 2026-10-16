extends Node3D
## Runs the raid: schedules waves, sails longboats to landing sites, unloads
## raiders into the shallows and steers raider squads toward the village.

const Squad := preload("res://scripts/gameplay/squad.gd")
const Tex := preload("res://scripts/core/tex.gd")

signal wave_started(index: int, total: int, boats: int)
signal victory
signal defeat

var battle
var island
var nav
var boat_mesh: Mesh
var raider_visual
var berserker_visual
var boat_material: Material
var rng := RandomNumberGenerator.new()

var waves := [
	{"delay": 7.0, "boats": 2},
	{"delay": 40.0, "boats": 3},
	{"delay": 45.0, "boats": 3},
]
var wave_i := 0
var wave_clock := 0.0
var boats: Array = []      # {node, from, to, t, dur, squad, seats, state, unload_t, wade, wait}
var finished := false
var _ai_t := 0.0

const SEATS := [Vector3(-0.28, 0.08, -1.3), Vector3(0.28, 0.08, -1.3), Vector3(-0.28, 0.08, -0.68), Vector3(0.28, 0.08, -0.68),
	Vector3(-0.28, 0.08, -0.06), Vector3(0.28, 0.08, -0.06), Vector3(-0.28, 0.08, 0.56), Vector3(0.28, 0.08, 0.56)]


func setup(p_battle, p_island, p_nav, p_boat_mesh: Mesh, p_raider_visual, p_berserker_visual, p_mat: Material, p_seed: int) -> void:
	battle = p_battle
	island = p_island
	nav = p_nav
	boat_mesh = p_boat_mesh
	raider_visual = p_raider_visual
	berserker_visual = p_berserker_visual
	boat_material = p_mat
	rng.seed = p_seed


func time_to_next_wave() -> float:
	if wave_i >= waves.size():
		return -1.0
	return maxf(waves[wave_i]["delay"] - wave_clock, 0.0)


func _physics_process(dt: float) -> void:
	if finished:
		return
	wave_clock += dt
	if wave_i < waves.size() and wave_clock >= waves[wave_i]["delay"]:
		_launch_wave(waves[wave_i]["boats"])
		wave_i += 1
		wave_clock = 0.0
		wave_started.emit(wave_i, waves.size(), waves[wave_i - 1]["boats"])
		if Capture.has("capture"):
			var alive := 0
			for sq in battle.squads:
				if sq.team == battle.PLAYER:
					alive += sq.alive_count()
			print("WAVE %d launched: player_alive=%d houses=%d raiders_left=%d" % [wave_i, alive, battle.intact_houses().size(), raiders_alive()])
	for b in boats:
		_update_boat(b, dt)
	_ai_t -= dt
	if _ai_t <= 0.0:
		_ai_t = 0.5
		_think()
	_check_end()


# Landing sites -------------------------------------------------------------

func _find_landing(angle: float) -> Dictionary:
	var dir := Vector2(cos(angle), sin(angle))
	var r := 44.0
	while r > 4.0 and island.height_at(dir.x * r, dir.y * r) < -1.15:
		r -= 0.25
	if r <= 4.0:
		return {}
	var boat_to := dir * (r + 2.4)
	var wr := r
	while wr > 2.0:
		var p := dir * wr
		var c: Vector2i = nav.cell_of(p)
		if nav.is_walkable(c) and island.height_at(p.x, p.y) > -0.32:
			break
		wr -= 0.25
	var wade := dir * wr
	# The landing must actually reach the village.
	var houses: Array = battle.intact_houses()
	if houses.is_empty():
		return {}
	var path: PackedVector2Array = nav.find_path(wade, houses[0]["door"])
	if path.is_empty():
		return {}
	return {"boat_to": boat_to, "wade": wade, "dir": dir}


func _launch_wave(count: int) -> void:
	var base := rng.randf() * TAU
	var used: Array[Vector2] = []
	var launched := 0
	for attempt in 60:
		if launched >= count:
			break
		var ang := base + rng.randf_range(-1.3, 1.3) + (attempt / 20) * 2.1
		var site := _find_landing(ang)
		if site.is_empty():
			continue
		var clash := false
		for u in used:
			if u.distance_to(site["wade"]) < 5.0:
				clash = true
				break
		if clash:
			continue
		used.append(site["wade"])
		_spawn_boat(site, launched)
		launched += 1


func _spawn_boat(site: Dictionary, index: int) -> void:
	var dir: Vector2 = site["dir"]
	var to: Vector2 = site["boat_to"]
	var from := to + dir * (26.0 + index * 4.0)
	var node := Node3D.new()
	var hull := MeshInstance3D.new()
	hull.mesh = boat_mesh
	hull.material_override = boat_material
	node.add_child(hull)
	node.add_child(_wake())
	add_child(node)
	node.position = Vector3(from.x, 0.02, from.y)
	node.rotation.y = atan2(-dir.x, -dir.y)

	# Later waves bring more berserkers.
	var every := 4 if wave_i < 2 else 3
	var squad = battle.spawn_squad(battle.RAIDERS, "raider", "Raiders", raider_visual, site["wade"], SEATS.size(), atan2(-dir.x, -dir.y),
		{"kind": "berserker", "visual": berserker_visual, "every": every})
	squad.engage_radius = 4.5
	squad.leash = 6.0
	for i in squad.units.size():
		var u = squad.units[i]
		u.boarded = true
	var b := {"node": node, "from": from, "to": to, "t": 0.0, "dur": from.distance_to(to) / 3.2,
		"squad": squad, "state": "sail", "unload_t": 0.0, "next": 0, "wade": site["wade"], "wait": 0.0}
	boats.append(b)
	_place_crew(b)


func _wake() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 140
	p.lifetime = 4.0
	p.local_coords = false
	p.position = Vector3(0, 0.05, -2.3)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.45, 0.0, 0.15)
	pm.direction = Vector3(0, 0, -1)
	pm.spread = 30.0
	pm.initial_velocity_min = 0.1
	pm.initial_velocity_max = 0.4
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.6
	pm.scale_max = 1.2
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.4))
	sc.add_point(Vector2(1, 2.2))
	var sct := CurveTexture.new()
	sct.curve = sc
	pm.scale_curve = sct
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.8))
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
	return p


func _place_crew(b: Dictionary) -> void:
	var node: Node3D = b["node"]
	var xf := node.global_transform
	var squad = b["squad"]
	for i in squad.units.size():
		var u = squad.units[i]
		if not u.boarded:
			continue
		var w: Vector3 = xf * SEATS[i]
		u.pos = Vector2(w.x, w.z)
		u.y = w.y
		u.facing = node.rotation.y
		u.vel = Vector2.ZERO


func _update_boat(b: Dictionary, dt: float) -> void:
	var node: Node3D = b["node"]
	var t := Time.get_ticks_msec() * 0.001 + node.position.x
	match b["state"]:
		"sail":
			b["t"] += dt / b["dur"]
			var k: float = minf(b["t"], 1.0)
			# Ease out: the boat glides in and runs up onto the shallows.
			var e := 1.0 - pow(1.0 - k, 2.2)
			var p: Vector2 = (b["from"] as Vector2).lerp(b["to"], e)
			node.position = Vector3(p.x, 0.02, p.y)
			if k >= 1.0:
				b["state"] = "unload"
				b["unload_t"] = 0.6
		"unload":
			b["unload_t"] -= dt
			if b["unload_t"] <= 0.0:
				var squad = b["squad"]
				var i: int = b["next"]
				if i < squad.units.size():
					var u = squad.units[i]
					var seat: Vector3 = node.global_transform * SEATS[i]
					u.boarded = false
					u.hop_t = 0.0
					u.on_hop()
					u.hop_from = seat
					var off := Vector2(rng.randf_range(-0.9, 0.9), rng.randf_range(-0.9, 0.9))
					var land: Vector2 = b["wade"] + off
					var lc: Vector2i = nav.nearest_walkable(land, 4)
					u.hop_to = nav.cell_centre(lc.x, lc.y) if lc.x >= 0 else b["wade"]
					b["next"] = i + 1
					b["unload_t"] = 0.16
				else:
					b["state"] = "beached"
					squad.anchor = b["wade"]
		"beached":
			b["wait"] += dt
			# Shove off once the crew is ashore and fighting.
			if b["wait"] > 6.0:
				b["state"] = "leave"
				b["t"] = 0.0
		"leave":
			b["t"] += dt / 14.0
			var to: Vector2 = b["to"]
			var away: Vector2 = to + (to - (b["wade"] as Vector2)).normalized() * 30.0
			var p: Vector2 = to.lerp(away, b["t"] * b["t"])
			node.position = Vector3(p.x, 0.02, p.y)
			if b["t"] >= 1.0:
				node.visible = false
	node.rotation.x = sin(t * 1.1) * 0.025
	node.rotation.z = sin(t * 0.8) * 0.035
	if b["state"] in ["sail", "unload"]:
		_place_crew(b)


# Raider AI -------------------------------------------------------------------

func _think() -> void:
	for b in boats:
		var squad = b["squad"]
		if b["state"] != "beached" and b["state"] != "leave":
			continue
		if squad.is_dead():
			continue
		var still_hopping := false
		for u in squad.units:
			if u.alive() and (u.boarded or u.hop_t >= 0.0):
				still_hopping = true
		if still_hopping:
			continue
		var centre: Vector2 = battle._centroid(squad)
		var goal = squad.goal_house
		if goal == null or goal["destroyed"]:
			goal = _nearest_house(centre)
			squad.goal_house = goal
			squad.path = PackedVector2Array()
		var dest := Vector2.INF
		if goal != null:
			dest = goal["door"]
		else:
			var prey = _nearest_player_squad(centre)
			if prey == null:
				continue
			dest = battle._centroid(prey)
		if squad.order == Squad.Order.HOLD and centre.distance_to(dest) < 1.6:
			continue
		if squad.path.is_empty() or squad.destination().distance_to(dest) > 1.5 or squad.order == Squad.Order.HOLD:
			var p: PackedVector2Array = nav.find_path(squad.anchor, dest)
			if not p.is_empty():
				squad.set_path(p, true)


func _nearest_house(p: Vector2):
	var best = null
	var best_d := INF
	for h in battle.intact_houses():
		var d: float = p.distance_to(h["pos"])
		if d < best_d:
			best_d = d
			best = h
	return best


func _nearest_player_squad(p: Vector2):
	var best = null
	var best_d := INF
	for s in battle.squads:
		if s.team != battle.PLAYER or s.is_dead():
			continue
		var d: float = p.distance_to(battle._centroid(s))
		if d < best_d:
			best_d = d
			best = s
	return best


func raiders_alive() -> int:
	var n := 0
	for s in battle.squads:
		if s.team == battle.RAIDERS:
			n += s.alive_count()
	return n


func _check_end() -> void:
	var player_alive := 0
	for s in battle.squads:
		if s.team == battle.PLAYER:
			player_alive += s.alive_count()
	# Burnt houses cost you the island's reward; only losing the army loses the battle.
	if player_alive == 0:
		finished = true
		print("RESULT defeat houses=%d player_alive=%d wave=%d" % [battle.intact_houses().size(), player_alive, wave_i])
		defeat.emit()
		return
	if wave_i >= waves.size() and raiders_alive() == 0:
		var any_sailing := false
		for b in boats:
			if b["state"] == "sail" or b["state"] == "unload":
				any_sailing = true
		if not any_sailing:
			finished = true
			print("RESULT victory houses=%d player_alive=%d wave=%d" % [battle.intact_houses().size(), player_alive, wave_i])
			victory.emit()
