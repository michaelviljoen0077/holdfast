extends Node3D
## Real-time battle simulation: squads, melee and ranged combat, projectiles,
## burning houses and impact effects. Purely data-driven; visuals are thin.

const Unit := preload("res://scripts/gameplay/unit.gd")
const Squad := preload("res://scripts/gameplay/squad.gd")
const Tex := preload("res://scripts/core/tex.gd")

signal squad_changed(squad)
signal house_lost(house)
signal message(text: String)
signal squad_refitted(squad)
signal ability_used(squad)
signal impact(strength: float, at: Vector3)

var REFIT_TIME := 3.0
var REFIT_COOLDOWN := 25.0

const PLAYER := 0
const RAIDERS := 1

var island
var nav
var unit_material: ShaderMaterial
var squads: Array = []
var units: Array = []
var houses: Array = []          # {pos, node, hp, max_hp, burning, fx, destroyed, door}
var arrows: Array = []          # {node, from, to, t, dur, arc, target, dmg, stuck_t}
var tower                       # destructible tower node (may be null)
var crush_t := 0.0              # seconds left of tower-debris crush checks

var _grid := {}
var _puffs: GPUParticles3D
var _sparks: GPUParticles3D
var _arrow_mesh: Mesh
var _arrow_mat: StandardMaterial3D


func boon(id: String) -> bool:
	return Campaign.has_boon(id)


func setup(p_island, p_nav, p_unit_material: ShaderMaterial) -> void:
	if boon("second_wind"):
		REFIT_TIME = 1.5
		REFIT_COOLDOWN = 12.0
	island = p_island
	nav = p_nav
	unit_material = p_unit_material
	_build_fx()
	var am := BoxMesh.new()
	am.size = Vector3(0.02, 0.02, 0.3)
	_arrow_mesh = am
	_arrow_mat = StandardMaterial3D.new()
	_arrow_mat.albedo_color = Color(0.35, 0.26, 0.18)
	_arrow_mat.roughness = 0.9


# --------------------------------------------------------------------------
# Spawning

## `visual` is a Mesh or a character spec {scene, keep, scale}. `alt` optionally
## swaps every Nth unit for a variant: {kind, visual, every}.
func spawn_squad(team: int, kind: String, squad_name: String, visual, at: Vector2, count: int, facing := 0.0, alt := {}, level := 1) -> Squad:
	var s := Squad.new()
	s.level = level
	s.team = team
	s.kind = kind
	s.name = squad_name
	s.anchor = at
	s.facing = facing
	s.color = Color(0.25, 0.42, 0.85) if team == PLAYER else Color(0.8, 0.22, 0.16)
	if kind.begins_with("draugr"):
		s.color = Color(0.18, 0.58, 0.52)
	if kind == "archer":
		s.spacing = 0.55
		s.engage_radius = 11.0
		s.leash = 1.0
		s.cols = 4
	for i in count:
		var u := Unit.new()
		u.team = team
		u.kind = kind
		u.squad = s
		var vis = visual
		if not alt.is_empty() and i % int(alt["every"]) == int(alt["every"]) - 1:
			u.kind = alt["kind"]
			vis = alt["visual"]
		_apply_stats(u)
		var jitter := Vector2(randf_range(-0.3, 0.3), randf_range(-0.3, 0.3))
		u.setup(self, vis, unit_material, at + jitter, island.height_at(at.x + jitter.x, at.y + jitter.y))
		u.facing = facing
		s.units.append(u)
		units.append(u)
	s.speed = s.units[0].speed * 0.95
	s.visual = visual
	match kind:
		"shield":
			s.ability = "brace"
		"sword":
			s.ability = "charge"
		"archer":
			s.ability = "volley"
	s.assign_slots(nav, true)
	for u in s.units:
		u.pos = u.slot
	squads.append(s)
	_make_banner(s)
	return s


func _apply_stats(u: Unit) -> void:
	match u.kind:
		"shield":
			u.max_hp = 5.0
			u.speed = 2.1
			u.reach = 0.6
			u.damage = 1.0
			u.cooldown = 0.95
		"sword":
			u.max_hp = 4.0
			u.speed = 2.35
			u.reach = 0.72
			u.damage = 2.0
			u.cooldown = 1.25
		"archer":
			u.max_hp = 2.0
			u.speed = 2.4
			u.reach = 0.5
			u.damage = 2.0
			u.cooldown = 2.1
			u.attack_range = 11.0
		"militia":
			u.max_hp = 2.0
			u.speed = 2.5
			u.reach = 0.55
			u.damage = 1.0
			u.cooldown = 0.8
		"raider":
			u.max_hp = 3.0
			u.speed = 2.1
			u.reach = 0.6
			u.damage = 1.0
			u.cooldown = 1.0
		"berserker":
			u.max_hp = 4.0
			u.speed = 2.45
			u.reach = 0.72
			u.damage = 2.0
			u.cooldown = 1.35
		"chieftain":
			u.heavy = true
			u.max_hp = 16.0
			u.speed = 2.2
			u.reach = 0.95
			u.damage = 3.0
			u.cooldown = 1.4
		"draugr":
			u.max_hp = 2.0
			u.speed = 1.9
			u.reach = 0.6
			u.damage = 1.0
			u.cooldown = 1.35
			u.can_rise = true
		"draugr_archer":
			u.max_hp = 2.0
			u.speed = 2.0
			u.reach = 0.5
			u.damage = 1.0
			u.cooldown = 3.0
			u.attack_range = 8.0
			u.can_rise = true
		"jarl":
			u.max_hp = 70.0
			u.speed = 1.8
			u.reach = 1.25
			u.damage = 4.0
			u.cooldown = 1.6
			u.heavy = true
			u.special_t = 6.0
			u.summon_t = 10.0
		"champion":
			u.heavy = true
			u.max_hp = 10.0
			u.speed = 1.9
			u.reach = 0.85
			u.damage = 2.0
			u.cooldown = 1.3
	if u.team == PLAYER:
		if boon("drillmaster"):
			u.max_hp *= 1.2
		if boon("swift_march"):
			u.speed *= 1.15
	if u.kind == "militia" and boon("militia_drill"):
		u.max_hp *= 1.6
		u.damage *= 1.3
	if u.team == RAIDERS and boon("hallowed"):
		u.can_rise = false
	if u.team == RAIDERS:
		u.max_hp *= Campaign.enemy_toughness()
		if isle_trait == "veterans":
			u.max_hp *= 1.25
		if isle_trait == "haunted" and u.can_rise:
			u.rises_left = 2
	# Rain dampens bowstrings and blinds the aim.
	if weather == "storm" and u.attack_range > 0.0:
		u.attack_range *= 0.75
	# Veteran squads: tougher and harder-hitting per level.
	var lvl: int = u.squad.level if u.squad != null else 1
	u.max_hp *= 1.0 + 0.3 * (lvl - 1)
	u.damage *= 1.0 + 0.25 * (lvl - 1)
	u.hp = u.max_hp
	u.attack_t = randf() * u.cooldown


func _make_banner(s: Squad) -> void:
	var b := Node3D.new()
	var pin := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.05, 0.05)
	pin.mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.no_depth_test = true
	m.fixed_size = true
	m.render_priority = 2
	m.albedo_texture = _banner_texture(s.color, s.kind)
	pin.material_override = m
	pin.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	b.add_child(pin)
	add_child(b)
	s.banner = b


func _banner_texture(col: Color, kind: String) -> ImageTexture:
	var size := 64
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := Vector2(size * 0.5, size * 0.42)
	for y in size:
		for x in size:
			var p := Vector2(x + 0.5, y + 0.5)
			# Shield-shaped badge: circle on top, point at the bottom.
			var d := p.distance_to(c)
			var in_tip := y > c.y and absf(x + 0.5 - c.x) < (size * 0.86 - y) * 0.75
			var r := size * 0.34
			var inside := d < r or in_tip
			var edge := d < r + 3.0 or (y > c.y and absf(x + 0.5 - c.x) < (size * 0.86 - y) * 0.75 + 3.0 and y < size * 0.9)
			if inside:
				var fill := col
				# Simple glyph: vertical bar (spear) or chevron (archer) or cross (raider).
				var lx := x + 0.5 - c.x
				var ly := y + 0.5 - c.y
				var glyph := false
				match kind:
					"shield":
						glyph = absf(lx) < 3.0 and absf(ly) < 13.0
					"sword":
						glyph = (absf(lx) < 3.0 and absf(ly) < 13.0) or (absf(ly + 3.0) < 2.6 and absf(lx) < 9.0)
					"archer", "draugr_archer":
						glyph = absf(absf(lx) - (ly + 10.0) * 0.6) < 2.6 and ly > -10.0 and ly < 8.0
					"draugr":
						# Skull: a pale dome with two dark eyes.
						var dome := Vector2(lx, ly * 1.2 + 2.0).length() < 12.0
						var eyes := Vector2(absf(lx) - 5.0, ly + 1.0).length() < 3.4
						glyph = dome and not eyes
					_:
						glyph = (absf(lx - ly) < 3.2 or absf(lx + ly) < 3.2) and absf(lx) < 10.0
				img.set_pixel(x, y, Color(1, 0.97, 0.9) if glyph else fill)
			elif edge:
				img.set_pixel(x, y, Color(0.08, 0.07, 0.06, 0.9))
			else:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func register_house(pos: Vector2, node: MeshInstance3D, door: Vector2) -> void:
	houses.append({"pos": pos, "node": node, "hp": 22.0, "max_hp": 22.0, "burning": false,
		"fx": null, "destroyed": false, "door": door})


func intact_houses() -> Array:
	return houses.filter(func(h): return not h["destroyed"])


# --------------------------------------------------------------------------
# Simulation

var _chieftains: Array = []


var visuals := {}               # enemy kind -> character spec, for summoning
var _slams: Array = []          # pending telegraphed slams {at, t, unit, decal}
signal boss_spawned(unit)


func _physics_process(dt: float) -> void:
	_rebuild_grid()
	_update_slams(dt)
	_chieftains = units.filter(func(x): return x.kind == "chieftain" and x.alive() and not x.boarded)
	for s in squads:
		_update_squad(s, dt)
	for u in units:
		_update_unit(u, dt)
	_update_arrows(dt)
	_update_houses(dt)
	if crush_t > 0.0:
		crush_t -= dt
		_crush_check()


var _step_t := {}
var isle_trait := ""                 # island isle_trait id
var weather := "clear"
var structures: Array = []
signal structure_destroyed(structure)
var stats := {"slain": 0, "lost": 0}


func _process(dt: float) -> void:
	for u in units:
		u.update_visual(dt)
		if not u.alive() and not u.counted:
			u.counted = true
			stats["lost" if u.team == PLAYER else "slain"] += 1
	# Marching squads: soft footfalls.
	for s in squads:
		if s.is_dead() or s.order == Squad.Order.HOLD:
			continue
		_step_t[s] = _step_t.get(s, 0.0) - dt
		if _step_t[s] <= 0.0:
			_step_t[s] = 0.28
			var c := _centroid(s)
			Sfx.play("step", Vector3(c.x, island.height_at(c.x, c.y), c.y), -13.0, 0)
	for s in squads:
		if s.banner:
			var alive: int = s.alive_count()
			s.banner.visible = alive > 0 and not get_parent().get("attract")
			if alive > 0:
				var c := _centroid(s)
				var target := Vector3(c.x, island.height_at(c.x, c.y) + 1.25, c.y)
				s.banner.position = s.banner.position.lerp(target, clampf(dt * 10.0, 0.0, 1.0)) if s.banner.position != Vector3.ZERO else target
				var sc := 1.35 if s.selected else 1.0
				s.banner.scale = s.banner.scale.lerp(Vector3.ONE * sc, clampf(dt * 12.0, 0.0, 1.0))
	# Remove long-dead bodies.
	for i in range(units.size() - 1, -1, -1):
		var u: Unit = units[i]
		if u.state == Unit.State.DEAD and u.dead_t > 9.0 and (not u.can_rise or u.risen):
			u.free_visual()
			units.remove_at(i)


func _centroid(s: Squad) -> Vector2:
	var c := Vector2.ZERO
	var n := 0
	for u in s.units:
		if u.alive() and not u.boarded:
			c += u.pos
			n += 1
	return c / n if n > 0 else s.anchor


func _update_squad(s: Squad, dt: float) -> void:
	if s.is_dead():
		return
	s.ability_cd = maxf(s.ability_cd - dt, 0.0)
	s.ability_t = maxf(s.ability_t - dt, 0.0)
	var before: int = s.order
	var engaged := false
	if s.order != Squad.Order.MOVE:
		engaged = _nearest_enemy(s.anchor, s.team, s.engage_radius) != null
	s.in_combat = engaged
	# Attack-moving squads stop to fight; plain moves push through.
	if s.braced():
		pass
	elif not (s.order == Squad.Order.ATTACK_MOVE and engaged):
		var base := s.speed
		s.speed = base * s.formation_speed()
		if s.charging():
			s.speed = base * 1.9
		s.advance(dt, nav)
		s.speed = base
	s.assign_slots(nav, before != s.order)
	if s.team == PLAYER:
		_update_refit(s, dt)


func _update_unit(u: Unit, dt: float) -> void:
	if u.state == Unit.State.DEAD:
		if u.can_rise and not u.risen and u.dead_t > 4.5:
			u.rise()
			_puff(Vector3(u.pos.x, u.y + 0.1, u.pos.y), 6, Color(0.55, 0.75, 0.7, 0.8))
			Sfx.play("crumble", Vector3(u.pos.x, u.y, u.pos.y), -16.0, 200)
		return
	if u.boarded:
		return
	if u.hop_t >= 0.0:
		_update_hop(u, dt)
		return
	var s: Squad = u.squad
	u.attack_t -= dt
	if u.kind == "jarl":
		_boss_think(u, dt)
	# A chieftain's war cry quickens every raider near him.
	if u.team == RAIDERS and u.kind != "chieftain":
		for c in _chieftains:
			if c.pos.distance_squared_to(u.pos) < 16.0:
				u.attack_t -= dt * 0.6
				break

	# Target selection.
	if u.target != null and (not u.target.alive() or u.target.boarded):
		u.target = null
	var hold_ground: bool = s.order == Squad.Order.MOVE and s.team == PLAYER
	if u.attack_range > 0.0:
		var rng_now := u.attack_range * (1.25 if u.y > 1.0 + (0.0 if u.target == null else u.target.y) else 1.0)
		if u.target == null or u.pos.distance_to(u.target.pos) > rng_now or randf() < 0.01:
			u.target = _nearest_enemy(u.pos, u.team, rng_now)
	elif hold_ground:
		u.target = _nearest_enemy(u.pos, u.team, 0.75)
	else:
		if u.target != null and u.target.pos.distance_to(u.slot) > s.leash + 1.0:
			u.target = null
		if u.target == null or randf() < 0.04:
			var t = _nearest_enemy(u.pos, u.team, 2.6)
			if t == null:
				t = _nearest_enemy(u.slot, u.team, s.engage_radius)
			if t != null and t.pos.distance_to(u.slot) <= s.leash:
				u.target = t

	# Sieging squads hack at their structure whenever no enemy is close.
	var siege = s.siege
	if siege != null and (siege.dead or not is_instance_valid(siege)):
		s.siege = null
		siege = null
	if siege != null and u.target != null and u.attack_range <= 0.0 and u.target.pos.distance_to(u.pos) > 1.6:
		u.target = null

	# Desired position.
	var goal := u.slot
	var fighting := false
	if siege != null and u.target == null and u.attack_range > 0.0 and boon("fire_bolts") and s.order != Squad.Order.MOVE:
		if siege.distance_to(u.pos) <= u.attack_range and u.swing_t < 0.0 and u.attack_t <= 0.0:
			u.swing_t = 0.0
			u.swing_target = null
			u.attack_t = u.cooldown
			u.on_swing()
			var sc: Vector2 = siege.centre()
			u.facing = atan2(sc.x - u.pos.x, sc.y - u.pos.y)
			_fire_bolt_at_structure(u, siege)
	if siege != null and u.target == null and u.attack_range <= 0.0 and not s.charging() and s.order != Squad.Order.MOVE:
		goal = siege.nearest_point(u.pos, 0.28)
		if siege.distance_to(u.pos) <= u.reach + 0.12:
			goal = u.pos
			fighting = true
			if u.swing_t < 0.0 and u.attack_t <= 0.0:
				u.swing_t = 0.0
				u.swing_target = siege
				u.attack_t = u.cooldown * randf_range(0.85, 1.2)
				u.on_swing()
				var c := siege.centre() as Vector2
				u.facing = atan2(c.x - u.pos.x, c.y - u.pos.y)
	if s.braced():
		u.target = _nearest_enemy(u.pos, u.team, u.reach * 1.1)
		goal = u.pos
	elif s.charging():
		u.target = null
		_trample(u)
	if u.target != null:
		var to: Vector2 = u.target.pos - u.pos
		var dist := to.length()
		if u.attack_range > 0.0:
			fighting = true
		else:
			fighting = true
			if dist > u.reach * 0.85:
				goal = u.target.pos - to.normalized() * u.reach * 0.8
			else:
				goal = u.pos
		if u.swing_t < 0.0 and u.attack_t <= 0.0:
			var in_range := dist <= (u.attack_range * 1.3 if u.attack_range > 0.0 else u.reach)
			if in_range:
				u.swing_t = 0.0
				u.swing_target = u.target
				u.attack_t = u.cooldown * randf_range(0.85, 1.2)
				u.on_swing()

	# Attack animation and hit timing.
	if u.swing_t >= 0.0:
		var prev := u.swing_t
		u.swing_t += dt
		var strike := 0.24 if u.attack_range <= 0.0 else 0.32
		if prev < strike and u.swing_t >= strike:
			_resolve_attack(u)
		if u.swing_t > 0.6:
			u.swing_t = -1.0

	goal = _detour(u, goal, dt)

	# Steering.
	var to_goal := goal - u.pos
	var d := to_goal.length()
	var want := Vector2.ZERO
	if d > 0.04:
		var spd := u.speed * clampf(d / 0.6, 0.15, 1.0)
		if u.swing_t >= 0.0:
			spd *= 0.2
		if s.charging():
			spd *= 1.9
		want = to_goal / d * spd
	want += _separation(u) * 2.2
	u.vel = u.vel.lerp(want, clampf(dt * 9.0, 0.0, 1.0))
	var step := (u.vel + u.knock) * dt
	u.knock = u.knock.lerp(Vector2.ZERO, clampf(dt * 7.0, 0.0, 1.0))
	if u.perched:
		u.vel = Vector2.ZERO
		u.knock = Vector2.ZERO
		u.y = u.perch_y
	else:
		_move(u, step)
		u.y = maxf(island.height_at(u.pos.x, u.pos.y), -0.42)

	# Facing.
	var face_dir := Vector2.ZERO
	if u.target != null and (fighting or u.swing_t >= 0.0):
		face_dir = u.target.pos - u.pos
	elif u.vel.length() > 0.25:
		face_dir = u.vel
	if face_dir.length() > 0.01:
		u.facing = lerp_angle(u.facing, atan2(face_dir.x, face_dir.y), clampf(dt * 10.0, 0.0, 1.0))
	elif u.vel.length() < 0.1:
		var rest_face := s.facing
		if s.formation == "ring" and u.pos.distance_to(s.anchor) > 0.15:
			rest_face = atan2(u.pos.x - s.anchor.x, u.pos.y - s.anchor.y)
		u.facing = lerp_angle(u.facing, rest_face, clampf(dt * 3.0, 0.0, 1.0))


func _move(u: Unit, step: Vector2) -> void:
	if step.length_squared() < 1e-8:
		return
	var from_c: Vector2i = nav.cell_of(u.pos)
	var to_p := u.pos + step
	var to_c: Vector2i = nav.cell_of(to_p)
	if to_c == from_c or nav.linked(from_c, to_c):
		u.pos = to_p
		return
	# Slide along cliffs and shorelines.
	var px := u.pos + Vector2(step.x, 0.0)
	if nav.linked(from_c, nav.cell_of(px)) or nav.cell_of(px) == from_c:
		u.pos = px
		return
	var pz := u.pos + Vector2(0.0, step.y)
	if nav.linked(from_c, nav.cell_of(pz)) or nav.cell_of(pz) == from_c:
		u.pos = pz


func _separation(u: Unit) -> Vector2:
	var push := Vector2.ZERO
	for o in _query(u.pos, 0.42):
		if o == u or not o.alive() or o.boarded:
			continue
		var d: Vector2 = u.pos - o.pos
		var l := d.length()
		if l < 0.001:
			d = Vector2(randf() - 0.5, randf() - 0.5)
			l = 0.01
		if l < 0.36:
			push += d / l * (0.36 - l) / 0.36
	return push


func _resolve_attack(u: Unit) -> void:
	var t = u.swing_target
	if t != null and t.has_method("take_damage"):
		_hit_structure(u, t)
		return
	if t == null or not t.alive():
		return
	if u.attack_range > 0.0:
		_fire_arrow(u, t)
		return
	var dist: float = u.pos.distance_to(t.pos)
	if dist > u.reach * 1.4:
		return
	var hit_pos := Vector3(t.pos.x, t.y + 0.3, t.pos.y)
	# Defenders with shields block some blows, especially from the front.
	var block_chance := 0.0
	var frontal := Vector2(sin(t.facing), cos(t.facing)).dot((u.pos - t.pos).normalized()) > 0.3
	if t.squad != null and t.squad.formation == "ring":
		frontal = true
	match t.kind:
		"shield":
			block_chance = 0.6 if frontal else 0.15
			if t.squad.braced():
				block_chance = 1.0 if frontal else 0.55
		"raider":
			block_chance = 0.22 if frontal else 0.05
		"draugr":
			block_chance = 0.15 if frontal else 0.0
		"champion":
			block_chance = 0.45 if frontal else 0.1
		"sword":
			block_chance = 0.08
	if randf() < block_chance:
		if not t.squad.braced():
			t.knock += (t.pos - u.pos).normalized() * 0.7
		else:
			# A braced wall throws attackers back.
			u.knock += (u.pos - t.pos).normalized() * 1.2
		if t.kind == "shield" and t.team == PLAYER and boon("shield_bash"):
			u.knock += (u.pos - t.pos).normalized() * 2.2
			u.attack_t += 0.7
			u.take_hit(0.5, t.pos)
		t.on_block()
		_spark(hit_pos)
		Sfx.play("clash", hit_pos, -4.0)
		return
	t.take_hit(u.damage * _damage_mult(u, t), u.pos)
	Sfx.play("slash", hit_pos, -9.0, 60)
	if u.damage >= 2.0:
		Sfx.play("heavy", hit_pos, -4.0, 50)
	if u.kind == "jarl":
		_cleave(u, t)
	_puff(hit_pos, 3, Color(0.85, 0.8, 0.7, 0.8))
	Sfx.play("thud", hit_pos, -3.0)
	if u.damage >= 3.0:
		impact.emit(0.7, hit_pos)
	if not t.alive():
		_puff(Vector3(t.pos.x, t.y + 0.1, t.pos.y), 6, Color(0.75, 0.68, 0.55, 0.8))
		Sfx.play("death", hit_pos, -6.0, 80)


func _nearest_enemy(p: Vector2, team: int, radius: float):
	var best = null
	var best_d := radius * radius
	for o in _query(p, radius):
		if o.team == team or not o.alive() or o.boarded or o.hop_t >= 0.0:
			continue
		var d: float = p.distance_squared_to(o.pos)
		if d < best_d:
			best_d = d
			best = o
	return best


# Spatial hash ------------------------------------------------------------

func _rebuild_grid() -> void:
	_grid.clear()
	for u in units:
		if not u.alive():
			continue
		var k := Vector2i(floori(u.pos.x / 2.0), floori(u.pos.y / 2.0))
		if _grid.has(k):
			_grid[k].append(u)
		else:
			_grid[k] = [u]


func _query(p: Vector2, r: float) -> Array:
	var out := []
	var x0 := floori((p.x - r) / 2.0)
	var x1 := floori((p.x + r) / 2.0)
	var z0 := floori((p.y - r) / 2.0)
	var z1 := floori((p.y + r) / 2.0)
	for gz in range(z0, z1 + 1):
		for gx in range(x0, x1 + 1):
			var k := Vector2i(gx, gz)
			if _grid.has(k):
				out.append_array(_grid[k])
	return out


# Boats -------------------------------------------------------------------

func board(u: Unit) -> void:
	u.boarded = true


func _update_hop(u: Unit, dt: float) -> void:
	u.hop_t += dt / 0.55
	var t := clampf(u.hop_t, 0.0, 1.0)
	var land_y := maxf(island.height_at(u.hop_to.x, u.hop_to.y), -0.42)
	var p := Vector2(u.hop_from.x, u.hop_from.z).lerp(u.hop_to, t)
	u.pos = p
	u.y = lerpf(u.hop_from.y, land_y, t) + sin(t * PI) * 0.45
	u.vel = (u.hop_to - Vector2(u.hop_from.x, u.hop_from.z)) * 0.5
	if t >= 1.0:
		u.hop_t = -1.0
		u.y = land_y
		u.vel = Vector2.ZERO
		_splash(Vector3(u.pos.x, 0.02, u.pos.y))
		Sfx.play("splash", Vector3(u.pos.x, 0.0, u.pos.y), -8.0, 70)


# Arrows ------------------------------------------------------------------

func _fire_arrow(u: Unit, t) -> void:
	var dist: float = u.pos.distance_to(t.pos)
	var dur := 0.3 + dist * 0.035
	# Lead the target, with some scatter.
	var aim: Vector2 = t.pos + t.vel * dur * 0.9 + Vector2(randf_range(-0.3, 0.3), randf_range(-0.3, 0.3))
	var node := MeshInstance3D.new()
	node.mesh = _arrow_mesh
	node.material_override = _arrow_mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	var from := Vector3(u.pos.x, u.y + 0.35, u.pos.y) + Vector3(sin(u.facing), 0.0, cos(u.facing)) * 0.15
	Sfx.play("bow", from, -8.0, 60)
	var to := Vector3(aim.x, maxf(island.height_at(aim.x, aim.y), 0.0) + 0.25, aim.y)
	arrows.append({"node": node, "from": from, "to": to, "t": 0.0, "dur": dur,
		"arc": 0.2 + dist * 0.05, "target": t, "dmg": u.damage, "stuck_t": -1.0, "aim": aim, "shooter": u})


func _update_arrows(dt: float) -> void:
	for i in range(arrows.size() - 1, -1, -1):
		var a: Dictionary = arrows[i]
		var node: MeshInstance3D = a["node"]
		if a["stuck_t"] >= 0.0:
			a["stuck_t"] += dt
			if a["stuck_t"] > 4.0:
				node.queue_free()
				arrows.remove_at(i)
			continue
		a["t"] += dt / a["dur"]
		if a["t"] < 0.0:
			continue
		if not node.visible:
			node.visible = true
			Sfx.play("bow", a["from"], -10.0, 30)
		var t: float = minf(a["t"], 1.0)
		var p: Vector3 = (a["from"] as Vector3).lerp(a["to"], t)
		p.y += sin(t * PI) * a["arc"]
		var t2: float = minf(t + 0.02, 1.0)
		var p2: Vector3 = (a["from"] as Vector3).lerp(a["to"], t2)
		p2.y += sin(t2 * PI) * a["arc"]
		node.position = p
		if t < 1.0 and p2.distance_squared_to(p) > 1e-8:
			node.look_at(p + (p2 - p).normalized(), Vector3.UP)
		if a["t"] >= 1.0:
			var tgt = a["target"]
			var aim: Vector2 = a["aim"]
			var hit_st = a.get("structure")
			if hit_st != null:
				if is_instance_valid(hit_st) and not hit_st.dead:
					hit_st.take_damage(a["dmg"], aim)
					hit_st.ignite()
				node.queue_free()
				arrows.remove_at(i)
				continue
			if tgt == null:
				tgt = _nearest_enemy(aim, a.get("team", PLAYER), 0.5)
			var from3: Vector3 = a["from"]
			if tgt != null and tgt.alive() and tgt.pos.distance_to(aim) < 0.5 and _blocks_missile(tgt, Vector2(from3.x, from3.z)):
				_spark(Vector3(tgt.pos.x, tgt.y + 0.35, tgt.pos.y))
				Sfx.play("clash", p, -12.0, 60)
				node.queue_free()
				arrows.remove_at(i)
				continue
			if tgt != null and tgt.alive() and tgt.pos.distance_to(aim) < 0.5:
				var shooter = a.get("shooter")
				var mult := 1.0
				if shooter != null:
					mult = _damage_mult(shooter, tgt)
				tgt.take_hit(a["dmg"] * mult, Vector2((a["from"] as Vector3).x, (a["from"] as Vector3).z))
				_puff(Vector3(tgt.pos.x, tgt.y + 0.3, tgt.pos.y), 3, Color(0.85, 0.8, 0.7, 0.8))
				Sfx.play("arrow_hit", p, -5.0)
				if not tgt.alive():
					Sfx.play("death", p, -6.0, 80)
				node.queue_free()
				arrows.remove_at(i)
			else:
				# Missed: stick into the ground at an angle.
				a["stuck_t"] = 0.0
				node.position.y -= 0.12
				Sfx.play("arrow_ground", p, -12.0, 50)
				if p.y < 0.0:
					_splash(Vector3(p.x, 0.02, p.z))
					node.queue_free()
					arrows.remove_at(i)


# Houses ------------------------------------------------------------------

func _update_houses(dt: float) -> void:
	for h in houses:
		if h["destroyed"]:
			continue
		var raiders := 0
		for o in _query(h["pos"], 1.9):
			if o.team == RAIDERS and o.alive() and o.target == null and o.pos.distance_to(h["pos"]) < 1.9:
				raiders += 1
		if raiders > 0:
			h["hp"] -= dt * (0.35 + raiders * 0.15) * (0.6 if weather == "storm" else 1.0)
			if not h["burning"]:
				h["burning"] = true
				h["fx"] = _make_fire(h)
				message.emit("A house is burning!")
		var node: MeshInstance3D = h["node"]
		var burnt: float = 1.0 - h["hp"] / h["max_hp"]
		node.set_instance_shader_parameter("charred", clampf(burnt * 1.1, 0.0, 1.0) if h["burning"] else 0.0)
		if h["hp"] <= 0.0:
			h["destroyed"] = true
			node.set_instance_shader_parameter("charred", 1.0)
			# Roof caves in: squash the building.
			var tw := create_tween()
			tw.tween_property(node, "scale", Vector3(1.0, 0.45, 1.0), 0.8).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
			_puff(Vector3(h["pos"].x, node.position.y + 0.8, h["pos"].y), 14, Color(0.3, 0.28, 0.26, 0.9))
			house_lost.emit(h)


func _make_fire(h: Dictionary) -> Node3D:
	var node: MeshInstance3D = h["node"]
	return _fire_root(node.position + Vector3(0, 1.2, 0), 1.0)


func _fire_root(at: Vector3, scale: float) -> Node3D:
	var root := Node3D.new()
	root.position = at
	root.scale = Vector3.ONE * scale
	add_child(root)
	var flames := GPUParticles3D.new()
	flames.amount = 70
	flames.lifetime = 0.9
	flames.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.7, 0.3, 0.45)
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 12.0
	pm.initial_velocity_min = 0.8
	pm.initial_velocity_max = 1.6
	pm.gravity = Vector3(0, 0.6, 0)
	pm.scale_min = 0.5
	pm.scale_max = 1.0
	var sc := Curve.new()
	sc.add_point(Vector2(0, 1.0))
	sc.add_point(Vector2(1, 0.1))
	var sct := CurveTexture.new()
	sct.curve = sc
	pm.scale_curve = sct
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.9, 0.5, 1.0))
	g.add_point(0.4, Color(1.0, 0.45, 0.1, 0.9))
	g.set_color(g.get_point_count() - 1, Color(0.6, 0.12, 0.02, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	flames.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.45, 0.6)
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fm.vertex_color_use_as_albedo = true
	fm.albedo_texture = Tex.radial_soft(64)
	fm.emission_enabled = true
	fm.emission = Color(1.0, 0.5, 0.15)
	fm.emission_energy_multiplier = 2.0
	q.material = fm
	flames.draw_pass_1 = q
	root.add_child(flames)

	var smoke := GPUParticles3D.new()
	smoke.amount = 40
	smoke.lifetime = 5.0
	smoke.local_coords = false
	smoke.visibility_aabb = AABB(Vector3(-6, -1, -6), Vector3(12, 14, 12))
	var sp := ParticleProcessMaterial.new()
	sp.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	sp.emission_box_extents = Vector3(0.5, 0.2, 0.4)
	sp.direction = Vector3(0.3, 1, 0.1)
	sp.spread = 15.0
	sp.initial_velocity_min = 0.6
	sp.initial_velocity_max = 1.0
	sp.gravity = Vector3(0.25, 0.15, 0.05)
	sp.scale_min = 1.0
	sp.scale_max = 1.6
	var ssc := Curve.new()
	ssc.add_point(Vector2(0, 0.4))
	ssc.add_point(Vector2(1, 2.4))
	var ssct := CurveTexture.new()
	ssct.curve = ssc
	sp.scale_curve = ssct
	var sg := Gradient.new()
	sg.set_color(0, Color(0.25, 0.22, 0.2, 0.0))
	sg.add_point(0.1, Color(0.22, 0.2, 0.19, 0.55))
	sg.set_color(sg.get_point_count() - 1, Color(0.5, 0.5, 0.52, 0.0))
	var sgt := GradientTexture1D.new()
	sgt.gradient = sg
	sp.color_ramp = sgt
	smoke.process_material = sp
	var sq := QuadMesh.new()
	sq.size = Vector2(1.0, 1.0)
	var sm := StandardMaterial3D.new()
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.vertex_color_use_as_albedo = true
	sm.albedo_texture = Tex.radial_soft(64)
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	sq.material = sm
	smoke.draw_pass_1 = sq
	root.add_child(smoke)

	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.55, 0.2)
	light.light_energy = 2.5
	light.omni_range = 5.0
	light.shadow_enabled = false
	light.set_script(preload("res://scripts/gameplay/flicker.gd"))
	root.add_child(light)
	root.add_child(Sfx.fire_loop())
	return root


# Tower crush --------------------------------------------------------------

func topple_tower(direction: Vector2) -> bool:
	if tower == null or tower.collapsed:
		return false
	var d := direction.normalized()
	var base: Vector3 = tower.global_position
	var hit := base + Vector3(-d.x * 1.2, 0.9, -d.y * 1.2)
	tower.collapse(hit, 14.0)
	Sfx.play("crumble", base + Vector3(0, 1.5, 0), 4.0, 0)
	# Masonry clatter as the courses come down.
	for k in 14:
		var delay := 0.15 + randf() * 2.2
		get_tree().create_timer(delay, false).timeout.connect(func():
			Sfx.play("stone", base + Vector3(randf_range(-3, 3) + d.x * 2.0, 0.5, randf_range(-3, 3) + d.y * 2.0), -6.0, 0))
	# Give the upper courses a shove so the whole tower leans out and falls.
	for b in tower.blocks:
		var h: float = b.position.y
		b.apply_impulse(Vector3(d.x, 0.0, d.y) * h * 1.6)
	crush_t = 4.0
	return true


func _crush_check() -> void:
	for b in tower.blocks:
		var v: float = b.linear_velocity.length()
		if v < 2.2:
			continue
		var p: Vector3 = b.global_position
		for u in _query(Vector2(p.x, p.z), 0.6):
			if not u.alive():
				continue
			if absf(u.y + 0.3 - p.y) < 0.6 and u.pos.distance_to(Vector2(p.x, p.z)) < 0.5:
				u.take_hit(10.0, Vector2(p.x, p.z) - Vector2(b.linear_velocity.x, b.linear_velocity.z).normalized())
				impact.emit(0.5, p)
				_puff(Vector3(u.pos.x, u.y + 0.2, u.pos.y), 5, Color(0.75, 0.68, 0.55, 0.8))


# FX ----------------------------------------------------------------------

func _build_fx() -> void:
	_puffs = _burst_system(Color(1, 1, 1), 0.35, 0.9, 1.5, false)
	_sparks = _burst_system(Color(1.0, 0.85, 0.5), 0.08, 0.35, 3.0, true)


func _burst_system(col: Color, size: float, life: float, speed: float, additive: bool) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 256
	p.lifetime = life
	p.local_coords = false
	p.emitting = true
	p.amount_ratio = 0.0
	p.visibility_aabb = AABB(Vector3(-40, -5, -40), Vector3(80, 20, 80))
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 80.0
	pm.initial_velocity_min = speed * 0.4
	pm.initial_velocity_max = speed
	pm.gravity = Vector3(0, -2.0 if additive else 0.4, 0)
	pm.damping_min = 2.0
	pm.damping_max = 4.0
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.5))
	sc.add_point(Vector2(1, 1.3 if not additive else 0.0))
	var sct := CurveTexture.new()
	sct.curve = sc
	pm.scale_curve = sct
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var m := StandardMaterial3D.new()
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = Tex.radial_soft(32)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if additive else BaseMaterial3D.SHADING_MODE_PER_VERTEX
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	q.material = m
	p.draw_pass_1 = q
	add_child(p)
	return p


func _emit(sys: GPUParticles3D, at: Vector3, count: int, col: Color, spread_v: float) -> void:
	for i in count:
		var v := Vector3(randf_range(-1, 1), randf_range(0.3, 1.2), randf_range(-1, 1)) * spread_v
		sys.emit_particle(Transform3D(Basis(), at), v, col, Color(), GPUParticles3D.EMIT_FLAG_POSITION | GPUParticles3D.EMIT_FLAG_VELOCITY | GPUParticles3D.EMIT_FLAG_COLOR)


func _puff(at: Vector3, count: int, col: Color) -> void:
	_emit(_puffs, at, count, col, 0.8)


func _spark(at: Vector3) -> void:
	_emit(_sparks, at, 6, Color(1.0, 0.85, 0.5), 2.0)


func _splash(at: Vector3) -> void:
	_emit(_puffs, at, 5, Color(0.9, 0.97, 1.0, 0.85), 1.0)


func cheer(team: int) -> void:
	for u in units:
		if u.team == team and u.alive():
			u.cheer()


## Player squads resting at an intact house door recover their fallen and wounds.
func _update_refit(s: Squad, dt: float) -> void:
	s.refit_cooldown = maxf(s.refit_cooldown - dt, 0.0)
	var wounded := s.alive_count() < s.units.size()
	if not wounded:
		for u in s.units:
			if u.alive() and u.hp < u.max_hp:
				wounded = true
				break
	var house = house_near(s.anchor, 1.6)
	if not wounded or s.in_combat or s.order != Squad.Order.HOLD or house == null or s.refit_cooldown > 0.0:
		s.refit_t = 0.0
		return
	s.refit_t += dt
	if s.refit_t < REFIT_TIME:
		return
	s.refit_t = 0.0
	s.refit_cooldown = REFIT_COOLDOWN
	var door: Vector2 = house["door"]
	for i in s.units.size():
		var u: Unit = s.units[i]
		if u.alive():
			u.hp = u.max_hp
			continue
		# Fresh recruit steps out of the house.
		var fresh := Unit.new()
		fresh.team = s.team
		fresh.kind = u.kind
		fresh.squad = s
		_apply_stats(fresh)
		fresh.setup(self, s.visual, unit_material, door, island.height_at(door.x, door.y))
		fresh.facing = s.facing
		s.units[i] = fresh
		units.append(fresh)
		_puff(Vector3(door.x, island.height_at(door.x, door.y) + 0.3, door.y), 4, Color(0.9, 0.88, 0.8, 0.7))
	s.assign_slots(nav, true)
	squad_refitted.emit(s)


func house_near(p: Vector2, r: float):
	for h in houses:
		if not h["destroyed"] and (h["door"] as Vector2).distance_to(p) < r:
			return h
	return null


## Progress 0..1 of the current refit, for UI.
func refit_progress(s: Squad) -> float:
	return clampf(s.refit_t / REFIT_TIME, 0.0, 1.0)


## Units steer straight at their goal when they can walk there in a line;
## otherwise they follow a personal nav path around cliffs and water.
func _detour(u: Unit, goal: Vector2, dt: float) -> Vector2:
	u.upath_t -= dt
	if u.pos.distance_to(goal) < 0.3 or nav.clear_line(u.pos, goal):
		u.upath = PackedVector2Array()
		return goal
	if u.upath.is_empty() or u.upath_t <= 0.0 or u.upath_goal.distance_to(goal) > 1.2:
		u.upath = nav.find_path(u.pos, goal)
		u.upath_i = 1
		u.upath_goal = goal
		u.upath_t = 1.0 + randf() * 0.3
		if u.upath.is_empty():
			# Unreachable: give up on that enemy rather than grinding a cliff face.
			u.target = null
			return goal
	while u.upath_i < u.upath.size() - 1 and u.pos.distance_to(u.upath[u.upath_i]) < 0.3:
		u.upath_i += 1
	return u.upath[mini(u.upath_i, u.upath.size() - 1)]


# Abilities -----------------------------------------------------------------

## Activates a squad ability. `at` is the ground target for targeted abilities.
func use_ability(s: Squad, at := Vector2.INF) -> bool:
	if not s.ability_ready():
		return false
	var info := s.ability_info()
	match s.ability:
		"brace":
			s.set_path(PackedVector2Array())
			s.order = Squad.Order.HOLD
			for u in s.units:
				if u.alive():
					_puff(Vector3(u.pos.x, u.y + 0.05, u.pos.y), 1, Color(0.85, 0.8, 0.7, 0.6))
			Sfx.play("clash", Vector3(s.anchor.x, island.height_at(s.anchor.x, s.anchor.y) + 0.3, s.anchor.y), -2.0, 0)
		"charge":
			var path: PackedVector2Array = nav.find_path(s.anchor, at)
			if path.is_empty():
				return false
			s.set_path(path, false)
			for u in s.units:
				u.charge_hits = {}
			Sfx.play_ui("horn", -14.0)
		"volley":
			var shooters := 0
			for u in s.units:
				if not u.alive() or u.pos.distance_to(at) > u.attack_range * 1.4:
					continue
				shooters += 1
				var spot := at + Vector2.from_angle(randf() * TAU) * sqrt(randf()) * 1.4
				_fire_volley_bolt(u, spot, randf() * 0.35)
				u.facing = atan2(at.x - u.pos.x, at.y - u.pos.y)
				u.on_swing()
			if shooters == 0:
				return false
	s.ability_t = info["duration"]
	if s.ability == "brace" and boon("iron_brace"):
		s.ability_t = 10.0
	s.ability_cd = info["cooldown"] * (0.7 if boon("war_horn") else 1.0)
	ability_used.emit(s)
	return true


func _fire_volley_bolt(u: Unit, spot: Vector2, delay: float) -> void:
	var dist := u.pos.distance_to(spot)
	var node := MeshInstance3D.new()
	node.mesh = _arrow_mesh
	node.material_override = _arrow_mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.visible = false
	add_child(node)
	var from := Vector3(u.pos.x, u.y + 0.35, u.pos.y)
	var to := Vector3(spot.x, maxf(island.height_at(spot.x, spot.y), 0.0) + 0.2, spot.y)
	# Negative t delays the shot so the volley ripples instead of firing as one.
	arrows.append({"node": node, "from": from, "to": to, "t": -delay / (0.5 + dist * 0.04), "dur": 0.5 + dist * 0.04,
		"arc": 1.2 + dist * 0.12, "target": null, "dmg": u.damage, "stuck_t": -1.0, "aim": spot, "team": u.team})


func _trample(u: Unit) -> void:
	for o in _query(u.pos, 0.6):
		if o.team == u.team or not o.alive() or o.boarded or u.charge_hits.has(o):
			continue
		if o.pos.distance_to(u.pos) > 0.55:
			continue
		u.charge_hits[o] = true
		o.take_hit(2.0 if u.squad.formation == "wedge" else 1.0, u.pos)
		impact.emit(0.35, Vector3(o.pos.x, o.y, o.pos.y))
		o.knock += (o.pos - u.pos).normalized() * 3.0
		_puff(Vector3(o.pos.x, o.y + 0.2, o.pos.y), 3, Color(0.85, 0.8, 0.7, 0.8))
		Sfx.play("thud", Vector3(o.pos.x, o.y, o.pos.y), -2.0)


## Shields stop missiles coming from the front.
func _blocks_missile(t, from: Vector2) -> bool:
	var frontal := Vector2(sin(t.facing), cos(t.facing)).dot((from - t.pos).normalized()) > 0.2
	match t.kind:
		"shield":
			if t.squad.braced():
				return frontal or randf() < 0.5
			return frontal and randf() < 0.7
		"champion":
			return frontal and randf() < 0.6
		"raider", "draugr":
			return frontal and randf() < 0.25
	return false


# The Drowned Jarl ----------------------------------------------------------

func _cleave(u: Unit, main_target) -> void:
	var fwd := Vector2(sin(u.facing), cos(u.facing))
	for o in _query(u.pos, u.reach * 1.2):
		if o == main_target or o.team == u.team or not o.alive() or o.boarded:
			continue
		var to: Vector2 = o.pos - u.pos
		if to.length() < u.reach * 1.15 and fwd.dot(to.normalized()) > 0.25:
			o.take_hit(u.damage * 0.6, u.pos)
	impact.emit(0.6, Vector3(u.pos.x, u.y, u.pos.y))


func _boss_think(u: Unit, dt: float) -> void:
	u.special_t -= dt
	u.summon_t -= dt
	var near := 0
	for o in _query(u.pos, 2.4):
		if o.team != u.team and o.alive():
			near += 1
	if u.special_t <= 0.0 and near >= 2 and u.swing_t < 0.0:
		u.special_t = 11.0
		u.attack_t = 2.0
		if u.rig:
			u.rig.once("1H_Melee_Attack_Jump_Chop", 0.8, 1.3)
		var d := Decal.new()
		d.texture_albedo = _ring_tex()
		d.size = Vector3(5.4, 6.0, 5.4)
		d.cull_mask = 1 << 1
		d.modulate = Color(1.0, 0.25, 0.15, 0.0)
		d.position = Vector3(u.pos.x, u.y, u.pos.y)
		add_child(d)
		_slams.append({"at": u.pos, "y": u.y, "t": 1.15, "unit": u, "decal": d})
	elif u.summon_t <= 0.0 and u.target != null:
		u.summon_t = 17.0
		if u.rig:
			u.rig.once("Spellcast_Summon", 1.0, 1.4)
		message.emit("The Jarl calls the drowned dead")
		for k in 4:
			var at := u.pos + Vector2.from_angle(TAU * k / 4.0 + randf() * 0.5) * randf_range(1.2, 2.0)
			var c: Vector2i = nav.nearest_walkable(at, 4)
			if c.x < 0:
				continue
			_raise_draugr(u.squad, nav.cell_centre(c.x, c.y))


func _raise_draugr(s: Squad, at: Vector2) -> void:
	if not visuals.has("draugr"):
		return
	var fresh := Unit.new()
	fresh.team = s.team
	fresh.kind = "draugr"
	fresh.squad = s
	_apply_stats(fresh)
	fresh.risen = true
	fresh.setup(self, visuals["draugr"], unit_material, at, island.height_at(at.x, at.y))
	fresh.facing = randf() * TAU
	if fresh.rig:
		fresh.rig.once("Spawn_Ground_Skeletons", 1.0)
	fresh.attack_t = 1.5
	s.units.append(fresh)
	units.append(fresh)
	_puff(Vector3(at.x, island.height_at(at.x, at.y) + 0.1, at.y), 8, Color(0.4, 0.55, 0.5, 0.85))


func _update_slams(dt: float) -> void:
	for i in range(_slams.size() - 1, -1, -1):
		var sl: Dictionary = _slams[i]
		sl["t"] -= dt
		var d: Decal = sl["decal"]
		var k := clampf(1.0 - sl["t"] / 1.15, 0.0, 1.0)
		d.modulate.a = 0.35 + 0.6 * k
		d.scale = Vector3(0.35 + 0.65 * k, 1.0, 0.35 + 0.65 * k)
		if sl["t"] > 0.0:
			continue
		var u: Unit = sl["unit"]
		var at: Vector2 = sl["at"]
		if u.alive():
			for o in _query(at, 2.8):
				if o.team == u.team or not o.alive() or o.boarded:
					continue
				var dist: float = o.pos.distance_to(at)
				if dist < 2.7:
					o.take_hit(2.0, at)
					o.knock += (o.pos - at).normalized() * (4.5 - dist)
			var c3 := Vector3(at.x, sl["y"] + 0.1, at.y)
			for k2 in 10:
				_puff(c3 + Vector3(cos(k2 * TAU / 10.0), 0.0, sin(k2 * TAU / 10.0)) * 1.6, 2, Color(0.75, 0.68, 0.55, 0.85))
			impact.emit(1.0, c3)
			Sfx.play("crumble", c3, -2.0, 0)
		d.queue_free()
		_slams.remove_at(i)


var _ring_cache: ImageTexture


func _ring_tex() -> ImageTexture:
	if _ring_cache:
		return _ring_cache
	var size := 128
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var r := Vector2(x + 0.5 - size * 0.5, y + 0.5 - size * 0.5).length() / (size * 0.5)
			var a: float = smoothstep(0.82, 0.9, r) * (1.0 - smoothstep(0.95, 1.0, r)) + 0.22 * (1.0 - smoothstep(0.0, 0.9, r)) * (1.0 if r < 0.92 else 0.0)
			img.set_pixel(x, y, Color(1, 1, 1, clampf(a, 0.0, 1.0)))
	img.generate_mipmaps()
	_ring_cache = ImageTexture.create_from_image(img)
	return _ring_cache


# Structures -----------------------------------------------------------------

func add_structure(st) -> void:
	st.battle = self
	add_child(st)
	structures.append(st)
	st.destroyed.connect(func(x):
		structures.erase(x)
		structure_destroyed.emit(x))


func _hit_structure(u: Unit, st) -> void:
	if st.dead or st.distance_to(u.pos) > u.reach + 0.4:
		return
	var mult := 1.0
	match u.kind:
		"berserker", "chieftain", "sword":
			mult = 2.0
		"jarl", "champion":
			mult = 3.0
	st.take_damage(u.damage * mult, u.pos)
	var c: Vector2 = st.nearest_point(u.pos, 0.0)
	_puff(Vector3(c.x, island.height_at(c.x, c.y) + 0.5, c.y), 2, Color(0.6, 0.48, 0.34, 0.8))
	# Player soldiers carry torches to enemy timber.
	if u.team == PLAYER and st.flammable and st.team != PLAYER:
		st.ignite()


## Generic fire effect for structures (flames, smoke, light, crackle).
func attach_fire(parent: Node3D, at: Vector3, scale: float) -> void:
	var root := _fire_root(at, scale)
	root.reparent(parent)


func dust(at: Vector3, count: int) -> void:
	_puff(at, count, Color(0.72, 0.66, 0.56, 0.85))


func fling_from_perch(u: Unit, away: Vector3) -> void:
	u.perched = false
	u.knock += Vector2(away.x, away.z) * 4.0
	u.take_hit(2.0, u.pos - Vector2(away.x, away.z))


func structure_at_collider(collider: Object):
	var n := collider as Node
	while n != null:
		if n.has_method("take_damage") and structures.has(n):
			return n
		n = n.get_parent()
	return null


## Damage multipliers: fighting downhill, and boons.
func _damage_mult(u, t) -> float:
	var m := 1.0
	if u.y - t.y > 0.6:
		m *= 1.5 if (u.team == PLAYER and boon("eagle_perch")) else 1.25
	if u.team == PLAYER and t.heavy and boon("giant_slayer"):
		m *= 1.6
	return m


# Militia ---------------------------------------------------------------------

var militia_called := false
var freed := 0
signal captives_freed(squad)
signal militia_raised(squad)


func militia_size() -> int:
	var n := intact_houses().size()
	var size := clampi(n, 0, 7)
	if boon("militia_drill"):
		size *= 2
	return size


## The villagers take up knives and pitchforks. Once per battle.
func call_militia(at: Vector2, facing: float):
	if militia_called or militia_size() <= 0 or not visuals.has("militia"):
		return null
	militia_called = true
	var s := spawn_squad(PLAYER, "militia", "Militia", visuals["militia"], at, militia_size(), facing)
	s.cols = 4
	for u in s.units:
		_puff(Vector3(u.pos.x, u.y + 0.2, u.pos.y), 2, Color(0.9, 0.86, 0.75, 0.7))
	Sfx.play_ui("horn", -8.0)
	message.emit("The village takes up arms")
	militia_raised.emit(s)
	return s


func _fire_bolt_at_structure(u: Unit, st) -> void:
	var c: Vector2 = st.centre()
	var dist := u.pos.distance_to(c)
	var node := MeshInstance3D.new()
	node.mesh = _arrow_mesh
	var fm := StandardMaterial3D.new()
	fm.emission_enabled = true
	fm.emission = Color(1.0, 0.5, 0.15)
	fm.emission_energy_multiplier = 3.0
	fm.albedo_color = Color(1.0, 0.6, 0.2)
	node.material_override = fm
	add_child(node)
	var from := Vector3(u.pos.x, u.y + 0.35, u.pos.y)
	var to := Vector3(c.x, maxf(island.height_at(c.x, c.y), 0.0) + 0.6, c.y)
	Sfx.play("bow", from, -8.0, 60)
	arrows.append({"node": node, "from": from, "to": to, "t": 0.0, "dur": 0.4 + dist * 0.04, "arc": 0.6 + dist * 0.06,
		"target": null, "dmg": u.damage, "stuck_t": -1.0, "aim": c, "team": u.team, "structure": st})


func free_captives(pen) -> void:
	if not visuals.has("militia"):
		return
	var c: Vector2 = pen.centre()
	var s := spawn_squad(PLAYER, "militia", "Freed Thralls", visuals["militia"], c, pen.captives, randf() * TAU)
	s.cols = 4
	freed += pen.captives
	message.emit("Captives freed: they take up arms with you")
	Sfx.play_ui("cleared", -4.0)
	captives_freed.emit(s)
