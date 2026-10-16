extends Node3D
## Build mode for palisades: click a start point, then an end point. A ghost
## wall follows the cursor, green when it fits and red when it doesn't, with
## its timber cost shown beside it.

const Palisade := preload("res://scripts/gameplay/palisade.gd")
const MIN_LEN := 0.8
const MAX_LEN := 3.6
const COST_PER_M := 1.0

signal built(palisade)
signal mode_changed(active: bool)

var battle
var nav
var island
var rig
var active := false
var timber := 12.0
var _start := Vector2.INF
var _ghost: MeshInstance3D
var _ghost_mat: StandardMaterial3D
var _valid := false
var _end := Vector2.ZERO


func setup(p_battle, p_nav, p_island, p_rig, p_timber: float) -> void:
	battle = p_battle
	nav = p_nav
	island = p_island
	rig = p_rig
	timber = p_timber
	_ghost = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.3, 0.9, 1.0)
	_ghost.mesh = bm
	_ghost_mat = StandardMaterial3D.new()
	_ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost_mat.albedo_color = Color(0.4, 1.0, 0.5, 0.45)
	_ghost.material_override = _ghost_mat
	_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ghost.visible = false
	add_child(_ghost)


func toggle() -> void:
	set_active(not active)


func set_active(v: bool) -> void:
	active = v
	_start = Vector2.INF
	_ghost.visible = false
	mode_changed.emit(active)


func cost(a: Vector2, b: Vector2) -> float:
	return ceilf(a.distance_to(b) * COST_PER_M)


## Called by the commander with the ground point under the mouse.
func hover(g: Vector3) -> void:
	if not active or g == Vector3.INF:
		_ghost.visible = false
		return
	var p := Vector2(g.x, g.z)
	if _start == Vector2.INF:
		# Before the first click: a short stub shows where the wall would begin.
		_preview(p - Vector2(0.4, 0), p + Vector2(0.4, 0))
		_valid = _point_ok(p)
	else:
		var d := p - _start
		if d.length() > MAX_LEN:
			p = _start + d.normalized() * MAX_LEN
		_end = p
		_preview(_start, p)
		_valid = _segment_ok(_start, p)
	_ghost_mat.albedo_color = Color(0.4, 1.0, 0.5, 0.45) if _valid else Color(1.0, 0.35, 0.3, 0.45)


func click(g: Vector3) -> bool:
	if not active or g == Vector3.INF:
		return false
	var p := Vector2(g.x, g.z)
	if _start == Vector2.INF:
		if _point_ok(p):
			_start = p
			Sfx.play_ui("select", -8.0)
		return true
	if not _valid:
		Sfx.play_ui("click", -4.0)
		return true
	var c := cost(_start, _end)
	var wall := Palisade.new()
	battle.add_structure(wall)
	wall.build(nav, island, _start, _end, battle.PLAYER)
	timber -= c
	Sfx.play("wood_hit", Vector3(_end.x, island.height_at(_end.x, _end.y), _end.y), -2.0, 0)
	built.emit(wall)
	# Chain walls: the next segment starts where this one ended.
	_start = _end
	return true


func _preview(a: Vector2, b: Vector2) -> void:
	var mid := (a + b) * 0.5
	var len := maxf(a.distance_to(b), 0.05)
	var h: float = maxf(island.height_at(mid.x, mid.y), 0.0)
	var yaw := atan2(b.x - a.x, b.y - a.y)
	_ghost.transform = Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(1, 1, len)), Vector3(mid.x, h + 0.45, mid.y))
	_ghost.visible = true


func _point_ok(p: Vector2) -> bool:
	var c: Vector2i = nav.cell_of(p)
	return nav.is_walkable(c) and island.height_at(p.x, p.y) > 0.05 and battle.house_near(p, 1.4) == null


func _segment_ok(a: Vector2, b: Vector2) -> bool:
	var len := a.distance_to(b)
	if len < MIN_LEN or cost(a, b) > timber:
		return false
	var steps := int(len / 0.25) + 1
	var h0: float = island.height_at(a.x, a.y)
	for i in steps + 1:
		var p := a.lerp(b, float(i) / steps)
		if not _point_ok(p):
			return false
		# Walls stand on fairly level ground, not across cliff lips.
		if absf(island.height_at(p.x, p.y) - h0) > 0.6:
			return false
		for u in battle.units:
			if u.alive() and not u.boarded and u.pos.distance_to(p) < 0.3:
				return false
	return true


func ghost_label_pos() -> Vector3:
	return _ghost.global_position + Vector3(0, 0.8, 0)


func pending_cost() -> float:
	return cost(_start, _end) if _start != Vector2.INF else 0.0
