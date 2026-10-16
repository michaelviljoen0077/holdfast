extends "res://scripts/gameplay/structure.gd"
## Raider watchtower: four log posts carrying a fighting platform where bowmen
## stand. Hack the legs and it topples, flinging the bowmen off.

const HEIGHT := 2.2

var pieces: Array[RigidBody3D] = []
var perch := Vector3.ZERO          # world position of the platform top
var garrison: Array = []           # units standing on the platform
var _mat: StandardMaterial3D


func build(p_nav, p_island, at: Vector2, p_team := 1) -> void:
	team = p_team
	label = "Watchtower"
	flammable = true
	max_hp = 40.0
	hp = max_hp
	setup_footprint(p_nav, p_island, at - Vector2(0.45, 0), at + Vector2(0.45, 0), 0.9)
	var g: float = island.height_at(at.x, at.y)
	position = Vector3(at.x, g - 0.05, at.y)
	perch = position + Vector3(0, HEIGHT + 0.08, 0)
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(0.42, 0.3, 0.2)
	_mat.roughness = 0.95
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			_piece(Vector3(sx * 0.42, HEIGHT * 0.5, sz * 0.42), Vector3(0.12, HEIGHT, 0.12),
				Basis(Vector3(sz, 0, -sx).normalized(), 0.05))
	# Cross braces.
	for k in 2:
		_piece(Vector3(0, 0.7 + k * 0.7, 0.42), Vector3(0.95, 0.07, 0.07), Basis(Vector3(0, 0, 1), 0.5 * (1 if k == 0 else -1)))
		_piece(Vector3(0, 0.7 + k * 0.7, -0.42), Vector3(0.95, 0.07, 0.07), Basis(Vector3(0, 0, 1), -0.5 * (1 if k == 0 else -1)))
	# Platform and railings.
	_piece(Vector3(0, HEIGHT, 0), Vector3(1.25, 0.1, 1.25), Basis())
	for s in [-1, 1]:
		_piece(Vector3(s * 0.6, HEIGHT + 0.25, 0), Vector3(0.06, 0.4, 1.25), Basis())
		_piece(Vector3(0, HEIGHT + 0.25, s * 0.6), Vector3(1.25, 0.4, 0.06), Basis())


func _piece(pos: Vector3, size: Vector3, basis: Basis) -> void:
	var body := RigidBody3D.new()
	body.freeze = true
	body.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	body.mass = 0.8
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat
	body.add_child(mi)
	body.transform = Transform3D(basis, pos)
	add_child(body)
	pieces.append(body)


func _on_hit(_from: Vector2) -> void:
	Sfx.play("wood_hit", global_position + Vector3(0, 0.8, 0), -5.0, 40)


func _apply_shake(amount: float) -> void:
	rotation.z = randf_range(-1, 1) * 0.02 * amount


func _on_ignite() -> void:
	if battle:
		battle.attach_fire(self, global_position + Vector3(0, HEIGHT * 0.6, 0), 0.8)


func _break_apart(from: Vector2) -> void:
	# Topple away from the attackers: posts snap, platform tips over.
	var c := global_position
	var away := Vector3(c.x - from.x, 0.0, c.z - from.y).normalized()
	for p in pieces:
		p.freeze = false
		var h := p.position.y / HEIGHT
		p.apply_impulse(away * (0.6 + h * 2.4) + Vector3(0, 0.3, 0), Vector3(0, 0.3, 0))
	if battle:
		battle.dust(c + Vector3(0, 0.5, 0), 14)
		for u in garrison:
			if u.alive():
				battle.fling_from_perch(u, away)
	garrison.clear()
	Sfx.play("crumble", c, -2.0, 0)
	get_tree().create_timer(10.0, false).timeout.connect(func():
		for p in pieces:
			if is_instance_valid(p):
				p.freeze = true
				var t := create_tween()
				t.tween_property(p, "position:y", p.position.y - 0.8, 3.0))
