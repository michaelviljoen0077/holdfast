extends "res://scripts/gameplay/structure.gd"
## A stake cage holding captured villagers. Break it open and the captives
## take up arms and join the warband.

const UnitRig := preload("res://scripts/gameplay/unit_rig.gd")

var captives := 5
var _stakes: Array[RigidBody3D] = []
var _figures: Array = []          # UnitRig visuals kneeling inside
var _mat: StandardMaterial3D


func build(p_nav, p_island, at: Vector2, visual: Dictionary, count := 5) -> void:
	team = 1
	label = "Captive pen"
	flammable = false
	captives = count
	max_hp = 16.0
	hp = max_hp
	setup_footprint(p_nav, p_island, at - Vector2(0.55, 0), at + Vector2(0.55, 0), 1.1)
	var g: float = island.height_at(at.x, at.y)
	position = Vector3(at.x, g - 0.04, at.y)
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(0.38, 0.27, 0.18)
	_mat.roughness = 0.95
	var shape := CylinderShape3D.new()
	shape.radius = 0.05
	shape.height = 0.9
	var n := 14
	for i in n:
		var a := TAU * i / n
		var body := RigidBody3D.new()
		body.freeze = true
		body.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
		body.mass = 0.3
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.position.y = 0.45
		body.add_child(cs)
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.03
		cm.bottom_radius = 0.05
		cm.height = 0.9
		cm.radial_segments = 6
		mi.mesh = cm
		mi.position.y = 0.45
		mi.material_override = _mat
		body.add_child(mi)
		body.position = Vector3(cos(a) * 0.75, 0, sin(a) * 0.75)
		body.rotation = Vector3(randf_range(-0.05, 0.05), 0, randf_range(-0.05, 0.05))
		add_child(body)
		_stakes.append(body)
	# Lashing hoop around the top.
	var hoop := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.72
	tm.outer_radius = 0.79
	hoop.mesh = tm
	hoop.position.y = 0.78
	hoop.material_override = _mat
	hoop.name = "Hoop"
	add_child(hoop)
	for k in mini(count, 5):
		var rig = UnitRig.new(visual["scene"], PackedStringArray(visual["keep"]), visual["scale"], visual.get("attach", {}))
		add_child(rig.root)
		var a := TAU * k / mini(count, 5) + 0.4
		rig.root.position = Vector3(cos(a) * 0.32, 0, sin(a) * 0.32)
		rig.root.rotation.y = randf() * TAU
		rig.loop("Sit_Floor_Idle")
		_figures.append(rig)


func _process(dt: float) -> void:
	super._process(dt)
	for r in _figures:
		r.tick(dt)


func _on_hit(_from: Vector2) -> void:
	Sfx.play("wood_hit", global_position + Vector3(0, 0.5, 0), -6.0, 40)


func _apply_shake(amount: float) -> void:
	for s in _stakes:
		if s.freeze:
			s.rotation.z = randf_range(-1, 1) * 0.05 * amount


func _break_apart(from: Vector2) -> void:
	for s in _stakes:
		s.freeze = false
		var away := (s.global_position - Vector3(from.x, s.global_position.y, from.y)).normalized()
		s.apply_impulse(away * randf_range(0.8, 1.8) + Vector3(0, 0.5, 0), Vector3(0, 0.4, 0))
	if has_node("Hoop"):
		get_node("Hoop").queue_free()
	for r in _figures:
		r.root.queue_free()
	_figures.clear()
	if battle:
		battle.dust(global_position + Vector3(0, 0.4, 0), 8)
		battle.free_captives(self)
	Sfx.play("wood_hit", global_position, 0.0, 0)
