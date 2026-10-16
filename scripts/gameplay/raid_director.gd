extends Node3D
## Runs the raid: schedules waves, sails longboats to landing sites, unloads
## raiders into the shallows and steers raider squads toward the village.

const Squad := preload("res://scripts/gameplay/squad.gd")
const BeachedBoat := preload("res://scripts/gameplay/beached_boat.gd")
const Tex := preload("res://scripts/core/tex.gd")

signal wave_started(index: int, total: int, boats: int)
signal victory
signal wave_cleared(index: int)
signal defeat

var battle
var island
var nav
var boat_mesh: Mesh
var visuals := {}           # kind -> character spec
var _announced := {}

## Boat crews. Every `alt_every`-th seat takes the `alt` kind instead.
const CREWS := {
	"raiders": {"kind": "raider", "name": "Raiders", "alt": "berserker", "alt_every": 4},
	"berserkers": {"kind": "berserker", "name": "Berserkers", "alt": "raider", "alt_every": 3},
	"draugr": {"kind": "draugr", "name": "The Drowned", "alt": "champion", "alt_every": 8},
	"bowmen": {"kind": "draugr_archer", "name": "Drowned bowmen", "alt": "", "alt_every": 0},
	"chieftain": {"kind": "raider", "name": "Chieftain's guard", "alt": "chieftain", "alt_every": 8},
	"jarl": {"kind": "draugr", "name": "The Drowned Jarl", "alt": "jarl", "alt_every": 8},
	"torchbearers": {"kind": "raider", "name": "Torchbearers", "alt": "torch", "alt_every": 2},
}
var boat_material: Material
var rng := RandomNumberGenerator.new()

var waves := [
	{"delay": 7.0, "boats": ["raiders", "raiders"]},
	{"delay": 40.0, "boats": ["torchbearers", "berserkers", "draugr", "bowmen"]},
	{"delay": 45.0, "boats": ["chieftain", "raiders", "draugr", "berserkers", "bowmen"]},
]
var wave_i := 0
var wave_clock := 0.0
var boats: Array = []      # {node, from, to, t, dur, squad, seats, state, unload_t, wade, wait}
var finished := false
var won := false
var mode := "defend"           # defend | assault
var isle_trait := ""
var objectives: Array = []     # assault: longhouses that must burn
var garrison: Array = []       # assault: defending squads
var _alarm := false
var _ai_t := 0.0
var _cleared_wave := 0

const SEATS := [Vector3(-0.28, 0.08, -1.3), Vector3(0.28, 0.08, -1.3), Vector3(-0.28, 0.08, -0.68), Vector3(0.28, 0.08, -0.68),
	Vector3(-0.28, 0.08, -0.06), Vector3(0.28, 0.08, -0.06), Vector3(-0.28, 0.08, 0.56), Vector3(0.28, 0.08, 0.56)]


func setup(p_battle, p_island, p_nav, p_boat_mesh: Mesh, p_visuals: Dictionary, p_mat: Material, p_seed: int) -> void:
	battle = p_battle
	island = p_island
	nav = p_nav
	boat_mesh = p_boat_mesh
	visuals = p_visuals
	boat_material = p_mat
	rng.seed = p_seed


## Sound the horn: bring the next wave now. Returns the gold earned for haste.
func call_early() -> int:
	if wave_i >= waves.size() or raiders_alive() > 0:
		return 0
	var left := time_to_next_wave()
	if left < 2.0:
		return 0
	var bonus := int(left * 0.6)
	battle.stats["haste_gold"] = battle.stats.get("haste_gold", 0) + bonus
	wave_clock = waves[wave_i]["delay"]
	return bonus


func time_to_next_wave() -> float:
	if wave_i >= waves.size():
		return -1.0
	return maxf(waves[wave_i]["delay"] - wave_clock, 0.0)


var _elapsed := 0.0


func _physics_process(dt: float) -> void:
	if finished:
		return
	_elapsed += dt
	# Test safety net: a battle this long means something is stuck.
	if Capture.has("capture") and _elapsed > 420.0:
		finished = true
		print("STALL mode=%s wave=%d raiders=%d burned=%d/%d" % [mode, wave_i, raiders_alive(), burned(), objectives.size()])
		get_tree().quit()
		return
	# The next wave holds back while the shore is still crowded, so waves
	# pressure the player without stacking into an unwinnable pile.
	wave_clock += dt * (1.0 if raiders_alive() < 6 else 0.35)
	if wave_i < waves.size() and wave_clock >= waves[wave_i]["delay"]:
		var crews: Array = (waves[wave_i]["boats"] as Array).duplicate()
		if isle_trait == "haunted" and not crews.has("draugr"):
			crews.append("draugr")
		_launch_wave(crews)
		wave_i += 1
		wave_clock = 0.0
		wave_started.emit(wave_i, waves.size(), (waves[wave_i - 1]["boats"] as Array).size())
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
	_check_cleared()
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


func _launch_wave(crews: Array) -> void:
	if Settings.difficulty == 0 and crews.size() > 1:
		crews = crews.slice(0, crews.size() - 1)
	var count := crews.size()
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
		_spawn_boat(site, launched, crews[launched])
		launched += 1


func _spawn_boat(site: Dictionary, index: int, crew_type := "raiders") -> void:
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

	var crew: Dictionary = CREWS.get(crew_type, CREWS["raiders"])
	var alt := {}
	if crew["alt"] != "":
		alt = {"kind": crew["alt"], "visual": visuals[crew["alt"]], "every": crew["alt_every"]}
	var squad = battle.spawn_squad(battle.RAIDERS, crew["kind"], crew["name"], visuals[crew["kind"]], site["wade"], SEATS.size(), atan2(-dir.x, -dir.y), alt)
	if crew["kind"] == "draugr_archer":
		# Bowmen stop at range and loose bolts rather than charging in.
		squad.engage_radius = 9.0
		squad.leash = 1.5
	else:
		squad.engage_radius = 4.5
		squad.leash = 6.0
	_announce(crew_type)
	for i in squad.units.size():
		var u = squad.units[i]
		u.boarded = true
	var b := {"node": node, "from": from, "to": to, "t": 0.0, "dur": from.distance_to(to) / (2.0 if isle_trait == "fair_winds" else 3.2),
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
					var dir: Vector2 = ((b["wade"] as Vector2) - (b["to"] as Vector2)).normalized()
					var st := BeachedBoat.new()
					battle.add_structure(st)
					st.setup(nav, island, node, b["to"] + dir * 2.2, b["to"] - dir * 2.2)
					b["structure"] = st
		"beached":
			b["wait"] += dt
			var st = b.get("structure")
			if st != null and st.dead:
				b["state"] = "sunk"
			# The boat waits a while, then rows home: burn it before it escapes.
			elif b["wait"] > 24.0 and (st == null or not st.burning):
				b["state"] = "leave"
				b["t"] = 0.0
				if st != null:
					battle.structures.erase(st)
					st.queue_free()
					b["structure"] = null
		"sunk":
			return
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
	nav.raider_mode = true
	_think_raiders()
	nav.raider_mode = false


func _think_raiders() -> void:
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
		if squad.role == "":
			_assign_role(squad)
		# Hunters go for the warband's archers and priests.
		if squad.role == "hunter":
			var prey = squad.prey
			if prey == null or prey.is_dead():
				prey = _soft_target(centre)
				squad.prey = prey
			if prey != null:
				var pd: Vector2 = battle._centroid(prey)
				if squad.order == Squad.Order.HOLD or squad.destination().distance_to(pd) > 2.0:
					var hp: PackedVector2Array = nav.find_path(squad.anchor, pd)
					if not hp.is_empty():
						squad.set_path(hp, true)
				continue
			squad.role = "burner"
		var goal = squad.goal_house
		squad.replan_t -= 0.5
		# Re-plan when the target gets guarded: slip past the defence.
		if goal != null and not goal["destroyed"] and squad.replan_t <= 0.0 and not squad.in_combat:
			squad.replan_t = 4.0
			if _guards(goal) >= 4:
				var alt = _nearest_house(centre, goal)
				if alt != null and _guards(alt) < 3:
					goal = alt
					squad.goal_house = alt
					squad.path = PackedVector2Array()
		if goal == null or goal["destroyed"]:
			goal = _nearest_house(centre)
			squad.goal_house = goal
			squad.path = PackedVector2Array()
		var dest := Vector2.INF
		if goal != null:
			dest = goal["door"]
			# Flankers swing wide around the village before closing in.
			if squad.role == "flanker" and centre.distance_to(dest) > 7.0:
				var side := (dest - centre).orthogonal().normalized() * (5.0 if squad.units.size() % 2 == 0 else -5.0)
				var wp: Vector2 = centre.lerp(dest, 0.55) + side
				var wc: Vector2i = nav.nearest_walkable(wp, 6)
				if wc.x >= 0:
					dest = nav.cell_centre(wc.x, wc.y)
		else:
			var prey = _nearest_player_squad(centre)
			if prey == null:
				continue
			dest = battle._centroid(prey)
		if squad.order == Squad.Order.HOLD and centre.distance_to(dest) < 1.6:
			continue
		# Walls in the way: hack through the one barring the road, unless the
		# detour around it is short.
		if squad.siege != null and not squad.siege.dead:
			continue
		var wall = _blocking_wall(squad, centre, dest)
		if wall != null:
			var found: Array = wall.reachable_approach(squad.anchor)
			if not found.is_empty():
				squad.siege = wall
				squad.set_path(found[1], true)
				continue
		if squad.path.is_empty() or squad.destination().distance_to(dest) > 1.5 or squad.order == Squad.Order.HOLD:
			var p: PackedVector2Array = nav.find_path(squad.anchor, dest)
			if not p.is_empty():
				squad.set_path(p, true)


## Raiders weigh distance against how well a house is guarded, so they drift
## toward the weak side of the village instead of always the nearest door.
func _guards(h) -> int:
	var n := 0
	for u in battle.units:
		if u.team == battle.PLAYER and u.alive() and (u.pos as Vector2).distance_to(h["pos"]) < 4.5:
			n += 1
	return n


func _nearest_house(p: Vector2, exclude = null):
	var best = null
	var best_score := INF
	for h in battle.intact_houses():
		if h == exclude:
			continue
		var score: float = p.distance_to(h["pos"]) + _guards(h) * 2.5 + rng.randf() * 2.0
		if h["burning"]:
			score -= 2.0
		if score < best_score:
			best_score = score
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
	if mode == "assault":
		_assault_think()
		if player_alive == 0:
			finished = true
			print("RESULT defeat assault burned=%d/%d" % [burned(), objectives.size()])
			defeat.emit()
		elif burned() == objectives.size():
			finished = true
			won = true
			print("RESULT victory assault burned=%d/%d player_alive=%d freed=%d" % [burned(), objectives.size(), player_alive, battle.freed])
			victory.emit()
		return
	# Burnt houses cost you the island's reward; only losing the army loses the battle.
	if player_alive == 0:
		finished = true
		print("RESULT defeat houses=%d player_alive=%d wave=%d boats_burned=%d" % [battle.intact_houses().size(), player_alive, wave_i, battle.stats.get("boats", 0)])
		defeat.emit()
		return
	if wave_i >= waves.size() and raiders_alive() == 0:
		var any_sailing := false
		for b in boats:
			if b["state"] == "sail" or b["state"] == "unload":
				any_sailing = true
		if not any_sailing:
			finished = true
			won = true
			print("RESULT victory houses=%d player_alive=%d wave=%d boats_burned=%d" % [battle.intact_houses().size(), player_alive, wave_i, battle.stats.get("boats", 0)])
			victory.emit()


func _announce(crew_type: String) -> void:
	if _announced.has(crew_type):
		return
	_announced[crew_type] = true
	match crew_type:
		"draugr", "bowmen":
			if not _announced.has("_drowned"):
				_announced["_drowned"] = true
				battle.message.emit("The Drowned rise from the sea")
		"torchbearers":
			battle.message.emit("Torchbearers! Douse burning houses by standing at the door")
		"chieftain":
			battle.message.emit("A raider chieftain comes ashore")
			Sfx.play_ui("horn", -2.0)
		"jarl":
			battle.message.emit("Haldor, the Drowned Jarl, rises from the deep")
			Sfx.play_ui("thunder", 0.0)
			Sfx.play_ui("horn", -2.0)


func _check_cleared() -> void:
	if wave_i == 0 or _cleared_wave == wave_i or raiders_alive() > 0:
		return
	for b in boats:
		if b["state"] == "sail" or b["state"] == "unload":
			return
	_cleared_wave = wave_i
	wave_cleared.emit(wave_i)


func _path_len(p: PackedVector2Array) -> float:
	var l := 0.0
	for i in range(1, p.size()):
		l += p[i - 1].distance_to(p[i])
	return l


## The player palisade a raider squad should break through, if any.
func _blocking_wall(squad, from: Vector2, to: Vector2):
	if squad.kind == "draugr_archer":
		return null
	var walls: Array = battle.structures.filter(func(s): return s.team == battle.PLAYER and not s.dead)
	if walls.is_empty():
		return null
	var path: PackedVector2Array = nav.find_path(squad.anchor, to)
	var direct := from.distance_to(to)
	if not path.is_empty() and _path_len(path) < direct * 1.5 + 6.0:
		return null
	# The wall closest to the straight line toward the goal.
	var best = null
	var best_d := 6.0
	for w in walls:
		var c: Vector2 = w.centre()
		var ab := to - from
		var t := clampf((c - from).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
		var d := (from + ab * t).distance_to(c)
		if d < best_d:
			best_d = d
			best = w
	return best


func burned() -> int:
	return objectives.filter(func(o): return o.dead).size()


## Garrison AI: hold the camp until something stirs, then hunt the intruders.
func _assault_think() -> void:
	nav.raider_mode = true
	_assault_think_inner()
	nav.raider_mode = false


func _assault_think_inner() -> void:
	if not _alarm:
		for o in objectives:
			if o.hp < o.max_hp:
				_alarm = true
		for g in garrison:
			if g.in_combat:
				_alarm = true
		if _alarm:
			battle.message.emit("The camp is roused")
			Sfx.play_ui("horn", -6.0)
	if not _alarm or _ai_t > 0.45:
		return
	for g in garrison:
		if g.is_dead() or g.kind == "draugr_archer" or g.in_combat:
			continue
		var c: Vector2 = battle._centroid(g)
		var prey = _nearest_player_squad(c)
		if prey == null:
			continue
		var dest: Vector2 = battle._centroid(prey)
		if g.order == Squad.Order.HOLD or g.destination().distance_to(dest) > 2.5:
			var p: PackedVector2Array = nav.find_path(g.anchor, dest)
			if not p.is_empty():
				g.set_path(p, true)


## Crews pick a plan as they land: berserkers and chieftains hunt soft
## targets, every third ordinary crew flanks, the rest go for the houses.
func _assign_role(squad) -> void:
	var heavy := false
	for u in squad.units:
		if u.kind in ["berserker", "chieftain"]:
			heavy = true
	if squad.kind == "berserker" or (heavy and rng.randf() < 0.5):
		squad.role = "hunter"
	elif rng.randf() < 0.35:
		squad.role = "flanker"
	else:
		squad.role = "burner"


func _soft_target(p: Vector2):
	var best = null
	var best_d := 22.0
	for s in battle.squads:
		if s.team != battle.PLAYER or s.is_dead() or not (s.kind in ["archer", "priest"]):
			continue
		var d: float = p.distance_to(battle._centroid(s))
		if d < best_d:
			best_d = d
			best = s
	return best
