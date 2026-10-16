extends Node3D
## Palisade build mode. Hold the left mouse button and drag to draw a wall
## along the ground; release to build it. A ghost of real stakes follows the
## stroke (green where it can stand, red where it can't) and the HUD shows the
## timber cost or the reason it won't fit. Right-click a wall to tear it down.

const Palisade := preload("res://scripts/gameplay/palisade.gd")
const SEG_LEN := 1.8
const STAKE_GAP := 0.17

signal built(palisade)
signal mode_changed(active: bool)

var battle
var nav
var island
var rig
var director
var active := false
var timber := 12.0
var drawing := false
var preview_cost := 0.0
var preview_reason := ""
var _stroke := PackedVector2Array()
var _ghost: MultiMeshInstance3D
var _ghost_ok: StandardMaterial3D
var _bad: MultiMeshInstance3D
var _hover := Vector3.INF
var _spent := {}               # palisade -> timber paid, for refunds


func setup(p_battle, p_nav, p_island, p_rig, p_timber: float) -> void:
	battle = p_battle
	nav = p_nav
	island = p_island
	rig = p_rig
	timber = p_timber
	Palisade._ensure_meshes()
	_ghost = _make_ghost(Color(0.45, 1.0, 0.55, 0.55))
	_bad = _make_ghost(Color(1.0, 0.35, 0.3, 0.6))


func _make_ghost(col: Color) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = Palisade._stake_mesh
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	m.no_depth_test = false
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = m
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visible = false
	add_child(mmi)
	return mmi


func toggle() -> void:
	set_active(not active)


func set_active(v: bool) -> void:
	active = v
	drawing = false
	_stroke = PackedVector2Array()
	_ghost.visible = false
	_bad.visible = false
	preview_cost = 0.0
	preview_reason = ""
	mode_changed.emit(active)


# Input from the commander ----------------------------------------------------

func press(g: Vector3) -> void:
	if not active or g == Vector3.INF:
		return
	drawing = true
	_stroke = PackedVector2Array([Vector2(g.x, g.z)])
	_refresh_preview()


func hover(g: Vector3) -> void:
	_hover = g
	if not active:
		return
	if drawing and g != Vector3.INF:
		var p := Vector2(g.x, g.z)
		if _stroke.is_empty() or _stroke[_stroke.size() - 1].distance_to(p) > 0.3:
			_stroke.append(p)
	_refresh_preview()


func release(g: Vector3) -> void:
	if not active or not drawing:
		return
	hover(g)
	drawing = false
	var built_any := false
	var segs := _segments()
	var gate_i := -1
	var ok_idx := []
	for i in segs.size():
		if segs[i]["ok"]:
			ok_idx.append(i)
	if not ok_idx.is_empty():
		gate_i = ok_idx[ok_idx.size() / 2]
	for si in segs.size():
		var seg: Dictionary = segs[si]
		if not seg["ok"]:
			continue
		var cost: float = seg["cost"]
		if cost > timber:
			break
		var wall := Palisade.new()
		wall.has_gate = si == gate_i and seg["a"].distance_to(seg["b"]) > 1.2
		battle.add_structure(wall)
		wall.build(nav, island, seg["a"], seg["b"], battle.PLAYER)
		timber -= cost
		_spent[wall] = cost
		wall.destroyed.connect(func(w): _spent.erase(w))
		built.emit(wall)
		built_any = true
	if built_any:
		var e := _stroke[_stroke.size() - 1]
		Sfx.play("wood_hit", Vector3(e.x, island.height_at(e.x, e.y), e.y), -2.0, 0)
	else:
		Sfx.play_ui("click", -4.0)
	_stroke = PackedVector2Array()
	_refresh_preview()


## Right-click in build mode: tear down one of your walls for a refund.
func dismantle_at(collider: Object) -> bool:
	var st = battle.structure_at_collider(collider) if collider != null else null
	if st == null or st.team != battle.PLAYER or not _spent.has(st):
		return false
	var paid: float = _spent[st]
	var refund: float = paid if (director == null or director.wave_i == 0) else floorf(paid * 0.5)
	timber += refund
	_spent.erase(st)
	nav.unblock(st._cells)
	battle.structures.erase(st)
	battle.dust(Vector3(st.centre().x, island.height_at(st.centre().x, st.centre().y) + 0.4, st.centre().y), 6)
	st.queue_free()
	Sfx.play_ui("coins", -6.0)
	return true


# Planning -------------------------------------------------------------------

## The stroke resampled into straight segments, each checked and priced.
func _segments() -> Array:
	var out := []
	if _stroke.size() < 2:
		return out
	# Resample the freehand stroke at even spacing.
	var pts := PackedVector2Array([_stroke[0]])
	var carry := 0.0
	for i in range(1, _stroke.size()):
		var a := _stroke[i - 1]
		var b := _stroke[i]
		var l := a.distance_to(b)
		var d := SEG_LEN - carry
		while d <= l:
			pts.append(a.lerp(b, d / l))
			d += SEG_LEN
		carry = l - (d - SEG_LEN)
	var tail := _stroke[_stroke.size() - 1]
	if pts[pts.size() - 1].distance_to(tail) > 0.5:
		pts.append(tail)
	var budget := timber
	for i in range(1, pts.size()):
		var a := pts[i - 1]
		var b := pts[i]
		var cost := ceilf(a.distance_to(b))
		var reason := _segment_problem(a, b)
		if reason == "" and cost > budget:
			reason = "Not enough timber"
		if reason == "":
			budget -= cost
		out.append({"a": a, "b": b, "cost": cost, "ok": reason == "", "reason": reason})
	return out


func _segment_problem(a: Vector2, b: Vector2) -> String:
	var len := a.distance_to(b)
	var steps := int(len / 0.2) + 1
	var h0: float = island.height_at(a.x, a.y)
	var was: bool = nav.raider_mode
	nav.raider_mode = true          # existing walls count as occupied
	for i in steps + 1:
		var p := a.lerp(b, float(i) / steps)
		var c: Vector2i = nav.cell_of(p)
		if island.height_at(p.x, p.y) < 0.05:
			nav.raider_mode = was
			return "Walls can't stand in the water"
		if not nav.is_walkable(c):
			nav.raider_mode = was
			return "Ground is blocked or too steep"
		if absf(island.height_at(p.x, p.y) - h0) > 0.6:
			nav.raider_mode = was
			return "Too steep: build along a level"
		if battle.house_near(p, 1.4) != null:
			nav.raider_mode = was
			return "Too close to a house door"
	nav.raider_mode = was
	for u in battle.units:
		if u.alive() and not u.boarded:
			var t: float = clampf((u.pos - a).dot(b - a) / maxf((b - a).length_squared(), 0.001), 0.0, 1.0)
			if a.lerp(b, t).distance_to(u.pos) < 0.3:
				return "Soldiers are in the way"
	return ""


func _refresh_preview() -> void:
	var good := []
	var bad := []
	preview_cost = 0.0
	preview_reason = ""
	if drawing:
		for seg in _segments():
			var list: Array = good if seg["ok"] else bad
			if seg["ok"]:
				preview_cost += seg["cost"]
			elif preview_reason == "":
				preview_reason = seg["reason"]
			_stakes_along(seg["a"], seg["b"], list)
	elif _hover != Vector3.INF:
		# A single stake marks where a stroke would begin.
		var p := Vector2(_hover.x, _hover.z)
		var c: Vector2i = nav.cell_of(p)
		var ok: bool = nav.is_walkable(c) and island.height_at(p.x, p.y) > 0.05
		(good if ok else bad).append(Transform3D(Basis(), Vector3(p.x, island.height_at(p.x, p.y) - 0.1, p.y)))
	_fill(_ghost, good)
	_fill(_bad, bad)


func _stakes_along(a: Vector2, b: Vector2, into: Array) -> void:
	var n := maxi(2, int(a.distance_to(b) / STAKE_GAP) + 1)
	for i in n:
		var p := a.lerp(b, float(i) / (n - 1))
		into.append(Transform3D(Basis(), Vector3(p.x, island.height_at(p.x, p.y) - 0.1, p.y)))


func _fill(mmi: MultiMeshInstance3D, xforms: Array) -> void:
	var mm := mmi.multimesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	mmi.visible = active and not xforms.is_empty()
