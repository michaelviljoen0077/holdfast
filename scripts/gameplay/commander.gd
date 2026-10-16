extends Node3D
## Player command layer: squad selection, move orders, path preview,
## slow-motion while issuing orders, and the tower topple ability.

const Squad := preload("res://scripts/gameplay/squad.gd")

signal selection_changed(squad)
signal ability_state(armed: bool)
signal formation_changed(squad)

var battle
var nav
var island
var rig
var selected = null
var hovered = null
var topple_armed := false
var ability_armed := false      # selected squad's targeted ability awaits a click
var builder                     # palisade build mode (optional)
var _rmb_down := Vector3.INF    # ground point where a right-drag order began
var _rmb_screen := Vector2.ZERO
var _rmb_target = null          # enemy structure under the cursor at press
var _drag_face := INF

var _ring: Decal
var _hover_ring: Decal
var _dest: Decal
var _dest_t := 0.0
var _path_mesh: ImmediateMesh
var _path_node: MeshInstance3D
var _path_mat: StandardMaterial3D
var _preview := PackedVector2Array()
var _preview_t := 0.0
var _mouse := Vector2.ZERO
var _time_target := 1.0
var base_speed := 1.0         # overall game speed (debug fast-forward)
var _hitstop := 0.0           # real seconds of near-freeze left
var _dramatic := 0.0          # real seconds of slow motion left

const TERRAIN_LAYER := 2


func setup(p_battle, p_nav, p_island, p_rig) -> void:
	battle = p_battle
	nav = p_nav
	island = p_island
	rig = p_rig
	_ring = _make_decal(_ring_texture(0.78, 0.92, Color(1, 1, 1, 1)), 2.4)
	_hover_ring = _make_decal(_ring_texture(0.82, 0.9, Color(1, 1, 1, 0.55)), 2.4)
	_dest = _make_decal(_ring_texture(0.55, 0.9, Color(1, 1, 1, 1)), 1.2)
	_path_mesh = ImmediateMesh.new()
	_path_node = MeshInstance3D.new()
	_path_node.mesh = _path_mesh
	_path_mat = StandardMaterial3D.new()
	_path_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_path_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_path_mat.vertex_color_use_as_albedo = true
	_path_mat.no_depth_test = false
	_path_node.material_override = _path_mat
	_path_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_path_node)


func _make_decal(tex: Texture2D, size: float) -> Decal:
	var d := Decal.new()
	d.texture_albedo = tex
	d.size = Vector3(size, 4.0, size)
	d.cull_mask = 1 << (TERRAIN_LAYER - 1)
	d.upper_fade = 0.2
	d.lower_fade = 0.2
	d.visible = false
	add_child(d)
	return d


func _ring_texture(inner: float, outer: float, col: Color) -> ImageTexture:
	var size := 128
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var r := Vector2(x + 0.5 - size * 0.5, y + 0.5 - size * 0.5).length() / (size * 0.5)
			var a := smoothstep(inner - 0.04, inner, r) * (1.0 - smoothstep(outer, outer + 0.04, r))
			# Subtle dashes so it reads as UI, not a painted circle.
			var ang := atan2(y - size * 0.5, x - size * 0.5)
			a *= 1.0 if sin(ang * 12.0) > 0.0 else 0.75
			img.set_pixel(x, y, Color(col.r, col.g, col.b, col.a * a))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func select(s) -> void:
	ability_armed = false
	if selected != null:
		selected.selected = false
	selected = s
	if s != null:
		s.selected = true
		Sfx.play_ui("select", -6.0)
	topple_armed = false
	ability_state.emit(false)
	selection_changed.emit(s)


## F: brace fires immediately; charge and volley wait for a ground click.
func trigger_ability(squad = null) -> void:
	var s = squad if squad != null else selected
	if s == null or not s.ability_ready():
		return
	if s.ability_info()["targeted"]:
		if selected != s:
			select(s)
		ability_armed = true
		ability_state.emit(false)
	else:
		battle.use_ability(s)
		select(null)


func arm_topple() -> void:
	if battle.tower == null or battle.tower.collapsed:
		return
	select(null)
	topple_armed = true
	ability_state.emit(true)


func _unhandled_input(event: InputEvent) -> void:
	if Capture.has("capture"):
		return
	if event is InputEventMouseMotion:
		_mouse = event.position
		if builder and builder.active:
			builder.hover(_ground_at(_mouse))
		if _rmb_down != Vector3.INF and _mouse.distance_to(_rmb_screen) > 24.0:
			var g := _ground_at(_mouse)
			if g != Vector3.INF:
				_drag_face = atan2(g.x - _rmb_down.x, g.z - _rmb_down.z)
	elif event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_RIGHT and _rmb_down != Vector3.INF:
		_finish_order()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT and builder and builder.drawing:
		builder.release(_ground_at(event.position))
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if builder and builder.active and mb.button_index == MOUSE_BUTTON_LEFT:
			builder.press(_ground_at(mb.position))
			get_viewport().set_input_as_handled()
		elif builder and builder.active and mb.button_index == MOUSE_BUTTON_RIGHT:
			# Right-click a wall to take it down; anywhere else leaves build mode.
			if not builder.dismantle_at(_collider_at(mb.position)):
				builder.set_active(false)
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if ability_armed and selected != null:
				var g0 := _ground_at(mb.position)
				if g0 != Vector3.INF:
					var s0 = selected
					if battle.use_ability(s0, Vector2(g0.x, g0.z)):
						_flash_dest(g0, Color(1.0, 0.8, 0.4))
				ability_armed = false
				select(null)
			elif topple_armed:
				var g := _ground_at(mb.position)
				if g != Vector3.INF:
					var tp: Vector3 = battle.tower.global_position
					battle.topple_tower(Vector2(g.x - tp.x, g.z - tp.z))
					rig.add_shake(1.0)
				topple_armed = false
				ability_state.emit(false)
			else:
				select(_pick_squad(mb.position))
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and selected != null:
			# Press marks the destination; dragging sets the facing; release orders.
			_rmb_down = _ground_at(mb.position)
			_rmb_screen = mb.position
			_rmb_target = _structure_at(mb.position)
			_drag_face = INF
			get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		var k: int = event.physical_keycode
		if k >= KEY_1 and k <= KEY_9:
			var mine := _player_squads()
			var i := k - KEY_1
			if i < mine.size():
				select(mine[i])
		elif k == KEY_T:
			arm_topple()
		elif k == KEY_M:
			call_militia()
		elif k == KEY_H:
			sound_horn()
		elif k == KEY_B and builder:
			select(null)
			builder.toggle()
		elif k == KEY_G and selected != null:
			selected.cycle_formation()
			selected.assign_slots(nav, true)
			Sfx.play_ui("select", -8.0)
			formation_changed.emit(selected)
		elif k == KEY_F or k == KEY_SPACE:
			trigger_ability()
		elif k == KEY_ESCAPE:
			if builder and builder.active:
				builder.set_active(false)
				get_viewport().set_input_as_handled()
			elif selected != null or topple_armed or ability_armed:
				select(null)
				topple_armed = false
				ability_state.emit(false)
				get_viewport().set_input_as_handled()


func _player_squads() -> Array:
	return battle.squads.filter(func(s): return s.team == battle.PLAYER and not s.is_dead())


func _pick_squad(screen: Vector2):
	var cam: Camera3D = rig.camera
	var best = null
	var best_d := 60.0
	for s in _player_squads():
		var c: Vector2 = battle._centroid(s)
		var w := Vector3(c.x, island.height_at(c.x, c.y) + 0.4, c.y)
		if cam.is_position_behind(w):
			continue
		var d := cam.unproject_position(w).distance_to(screen)
		var b: Vector3 = s.banner.global_position
		d = minf(d, cam.unproject_position(b).distance_to(screen))
		if d < best_d:
			best_d = d
			best = s
	return best


func _ground_at(screen: Vector2) -> Vector3:
	var cam: Camera3D = rig.camera
	var from := cam.project_ray_origin(screen)
	var dir := cam.project_ray_normal(screen)
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 600.0)
	q.collision_mask = 1
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		# Fall back to the water plane.
		if absf(dir.y) < 1e-4:
			return Vector3.INF
		var t := -from.y / dir.y
		return from + dir * t if t > 0.0 else Vector3.INF
	return hit["position"]


func _order_move(screen: Vector2) -> void:
	var g := _ground_at(screen)
	if g == Vector3.INF:
		return
	var path: PackedVector2Array = nav.find_path(selected.anchor, Vector2(g.x, g.z))
	if path.is_empty():
		_flash_dest(g, Color(1.0, 0.35, 0.3))
		return
	selected.set_path(path, false)
	Sfx.play_ui("order", -9.0)
	var end := path[path.size() - 1]
	_flash_dest(Vector3(end.x, island.height_at(end.x, end.y), end.y), Color(0.95, 0.92, 0.75))
	select(null)


func _flash_dest(at: Vector3, col: Color) -> void:
	_dest.position = at
	_dest.modulate = col
	_dest.visible = true
	_dest_t = 1.0


func _process(dt: float) -> void:
	# Slow time while a squad is selected or the tower ability is armed.
	_time_target = (0.22 if (selected != null or topple_armed) else 1.0) * base_speed
	var real_dt := dt / maxf(Engine.time_scale, 0.01)
	if _dramatic > 0.0:
		_dramatic -= real_dt
		_time_target = minf(_time_target, 0.25 * base_speed)
	if _hitstop > 0.0:
		# Freeze snaps in instantly and releases instantly: a punch, not a blur.
		_hitstop -= real_dt
		Engine.time_scale = 0.06 * base_speed
	else:
		Engine.time_scale = lerpf(Engine.time_scale, _time_target, clampf(real_dt * 8.0, 0.0, 1.0))
	if selected != null and selected.is_dead():
		select(null)

	if selected != null:
		var c: Vector2 = battle._centroid(selected)
		_ring.position = Vector3(c.x, island.height_at(c.x, c.y), c.y)
		_ring.modulate = Color(0.55, 0.75, 1.0)
		_ring.visible = true
		var pulse := 1.0 + sin(Time.get_ticks_msec() * 0.008) * 0.04
		_ring.scale = Vector3(pulse, 1.0, pulse)
	else:
		_ring.visible = false

	hovered = null if selected != null else _pick_squad(_mouse)
	if hovered != null:
		var hc: Vector2 = battle._centroid(hovered)
		_hover_ring.position = Vector3(hc.x, island.height_at(hc.x, hc.y), hc.y)
		_hover_ring.modulate = Color(0.8, 0.9, 1.0)
		_hover_ring.visible = true
	else:
		_hover_ring.visible = false

	if _dest_t > 0.0:
		_dest_t -= real_dt * 1.2
		_dest.modulate.a = clampf(_dest_t, 0.0, 1.0)
		var sc := 1.0 + (1.0 - _dest_t) * 0.6
		_dest.scale = Vector3(sc, 1.0, sc)
		if _dest_t <= 0.0:
			_dest.visible = false

	_preview_t -= real_dt
	if selected != null and _preview_t <= 0.0:
		_preview_t = 0.08
		var g := _ground_at(_mouse)
		_preview = nav.find_path(selected.anchor, Vector2(g.x, g.z)) if g != Vector3.INF else PackedVector2Array()
		if ability_armed and selected.ability == "volley":
			_preview = PackedVector2Array()
			if g != Vector3.INF:
				_dest.position = g
				_dest.modulate = Color(1.0, 0.75, 0.35, 0.9)
				_dest.scale = Vector3(2.4, 1.0, 2.4)
				_dest.visible = true
				_dest_t = 0.15
	elif selected == null:
		_preview = PackedVector2Array()
	_draw_path()
	if _drag_face != INF and _rmb_down != Vector3.INF:
		_draw_facing(_rmb_down, _drag_face)


## Dotted path from the selected squad to the cursor, hugging the terrain.
func _draw_path() -> void:
	_path_mesh.clear_surfaces()
	if _preview.size() < 2:
		return
	_path_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var spacing := 0.32
	var carry := 0.0
	var total := 0.0
	var anim := fmod(Time.get_ticks_msec() * 0.0012, spacing)
	for i in range(1, _preview.size()):
		var a := _preview[i - 1]
		var b := _preview[i]
		var seg := a.distance_to(b)
		var dirv := (b - a) / maxf(seg, 0.001)
		var d := spacing - carry + anim
		while d < seg:
			var p := a + dirv * d
			var h := maxf(island.height_at(p.x, p.y), 0.0) + 0.06
			var fade := clampf(total / 1.5, 0.0, 1.0)
			var dot_col := Color(1.0, 0.72, 0.3, 0.9 * fade) if ability_armed else Color(1.0, 0.97, 0.85, 0.85 * fade)
			_dot(Vector3(p.x, h, p.y), 0.055, dot_col)
			d += spacing
		carry = seg - (d - spacing)
		total += seg
		anim = 0.0
	var e := _preview[_preview.size() - 1]
	_dot(Vector3(e.x, maxf(island.height_at(e.x, e.y), 0.0) + 0.07, e.y), 0.14, Color(1.0, 0.97, 0.85, 0.95))
	_path_mesh.surface_end()


func _dot(c: Vector3, r: float, col: Color) -> void:
	var segs := 8
	for s in segs:
		var a0 := TAU * s / segs
		var a1 := TAU * (s + 1) / segs
		_path_mesh.surface_set_color(col)
		_path_mesh.surface_add_vertex(c)
		_path_mesh.surface_set_color(col)
		_path_mesh.surface_add_vertex(c + Vector3(cos(a1), 0, sin(a1)) * r)
		_path_mesh.surface_set_color(col)
		_path_mesh.surface_add_vertex(c + Vector3(cos(a0), 0, sin(a0)) * r)


func impact(strength: float, _at: Vector3) -> void:
	_hitstop = maxf(_hitstop, 0.035 + strength * 0.05)
	rig.add_shake(strength * 0.5)


func dramatic(seconds: float) -> void:
	_dramatic = seconds


func _structure_at(screen: Vector2):
	var cam: Camera3D = rig.camera
	var from := cam.project_ray_origin(screen)
	var q := PhysicsRayQueryParameters3D.create(from, from + cam.project_ray_normal(screen) * 600.0)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return null
	var st = battle.structure_at_collider(hit["collider"])
	if st != null and st.team != battle.PLAYER:
		return st
	return null


func _finish_order() -> void:
	var s = selected
	var dest := _rmb_down
	var target = _rmb_target
	var face := _drag_face
	_rmb_down = Vector3.INF
	_rmb_target = null
	_drag_face = INF
	if s == null:
		return
	if target != null and not target.dead:
		order_siege(s, target)
		select(null)
		return
	if dest == Vector3.INF:
		return
	var path: PackedVector2Array = nav.find_path(s.anchor, Vector2(dest.x, dest.z))
	if path.is_empty():
		_flash_dest(dest, Color(1.0, 0.35, 0.3))
		return
	s.siege = null
	s.set_path(path, false)
	s.end_facing = face
	Sfx.play_ui("order", -9.0)
	var end := path[path.size() - 1]
	_flash_dest(Vector3(end.x, island.height_at(end.x, end.y), end.y), Color(0.95, 0.92, 0.75))
	select(null)


func order_siege(s, st) -> bool:
	var found: Array = st.reachable_approach(s.anchor)
	if found.is_empty():
		var c: Vector2 = st.centre()
		_flash_dest(Vector3(c.x, island.height_at(c.x, c.y), c.y), Color(1.0, 0.35, 0.3))
		return false
	var near: Vector2 = found[0]
	var path: PackedVector2Array = found[1]
	s.siege = st
	s.set_path(path, true)
	s.end_facing = INF
	Sfx.play_ui("order", -6.0)
	_flash_dest(Vector3(near.x, island.height_at(near.x, near.y), near.y), Color(1.0, 0.55, 0.25))
	return true


func _draw_facing(at: Vector3, face: float) -> void:
	if _path_mesh.get_surface_count() == 0:
		_path_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	else:
		_path_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var dir := Vector3(sin(face), 0, cos(face))
	var side := Vector3(dir.z, 0, -dir.x)
	var col := Color(1.0, 0.85, 0.45, 0.9)
	for k in 6:
		var p := at + dir * (0.25 + k * 0.28)
		p.y = maxf(island.height_at(p.x, p.z), 0.0) + 0.07
		_dot(p, 0.06, col)
	var tip := at + dir * 2.1
	tip.y = maxf(island.height_at(tip.x, tip.z), 0.0) + 0.08
	for v in [tip, tip - dir * 0.45 + side * 0.3, tip - dir * 0.45 - side * 0.3]:
		_path_mesh.surface_set_color(col)
		_path_mesh.surface_add_vertex(v)
	_path_mesh.surface_end()


func call_militia() -> void:
	if battle.tower == null:
		return
	var tp: Vector3 = battle.tower.global_position
	var c: Vector2i = nav.nearest_walkable(Vector2(tp.x + 2.0, tp.z + 1.0), 8)
	if c.x < 0:
		return
	var s = battle.call_militia(nav.cell_centre(c.x, c.y), 0.0)
	if s != null:
		select(s)


func _collider_at(screen: Vector2) -> Object:
	var cam: Camera3D = rig.camera
	var from := cam.project_ray_origin(screen)
	var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + cam.project_ray_normal(screen) * 600.0))
	return hit.get("collider")


## Bring the next wave now, for gold.
func sound_horn() -> void:
	var director = get_parent().director
	var gold: int = director.call_early()
	if gold > 0:
		Sfx.play_ui("horn", -4.0)
		battle.message.emit("You sound the horn: they come now  (+%d gold)" % gold)
