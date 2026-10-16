extends "res://scripts/gameplay/structure.gd"
## A raider longhouse: a long timber hall with a curved turf roof and carved
## gable posts. Built from frozen rigid panels so it can be hacked apart or
## burnt down, and collapses physically when destroyed.

var panels: Array[RigidBody3D] = []
var yaw := 0.0
var length := 4.6
var width := 2.2
var ground := 0.0

static var _plank: StandardMaterial3D
static var _dark: StandardMaterial3D
static var _roof: StandardMaterial3D


func build(p_nav, p_island, at: Vector2, p_yaw: float, p_team := 1) -> void:
	team = p_team
	label = "Longhouse"
	flammable = true
	max_hp = 70.0
	hp = max_hp
	yaw = p_yaw
	var dir := Vector2(sin(yaw), cos(yaw))
	setup_footprint(p_nav, p_island, at - dir * length * 0.45, at + dir * length * 0.45, width)
	ground = island.height_at(at.x, at.y)
	position = Vector3(at.x, ground - 0.05, at.y)
	rotation.y = yaw
	_materials()
	var wall_h := 0.85
	var segs := 7
	# Side walls: vertical board panels, slightly bowed like a ship's hull.
	for side in [-1, 1]:
		for i in segs:
			var t := (i + 0.5) / segs
			var z := (t - 0.5) * length
			var bow := sin(t * PI) * 0.12
			var x: float = side * (width * 0.5 + bow)
			_panel(Vector3(x, wall_h * 0.5, z), Vector3(0.1, wall_h, length / segs * 1.02), Basis(), _plank if i % 2 == 0 else _dark)
	# Gable ends with a door on the front.
	for e in [-1, 1]:
		var z: float = e * length * 0.5
		for k in 4:
			var x := (k - 1.5) * width / 4.0
			if e == 1 and (k == 1 or k == 2):
				continue
			_panel(Vector3(x, wall_h * 0.5, z), Vector3(width / 4.0, wall_h, 0.1), Basis(), _plank)
		# Crossed, carved gable posts.
		for s in [-1, 1]:
			var post := Basis(Vector3(0, 0, 1), s * 0.55)
			_panel(Vector3(s * 0.32, wall_h + 0.55, z), Vector3(0.09, 1.4, 0.09), post, _dark)
	# Door lintel.
	_panel(Vector3(0, wall_h - 0.08, length * 0.5), Vector3(width * 0.5, 0.16, 0.12), Basis(), _dark)
	# Roof: overlapping turf-covered panels on each side.
	var roof_segs := 5
	for side in [-1, 1]:
		for i in roof_segs:
			var t := (i + 0.5) / roof_segs
			var z := (t - 0.5) * (length + 0.4)
			var b := Basis(Vector3(0, 0, 1), side * -0.72)
			_panel(Vector3(side * width * 0.3, wall_h + 0.42, z), Vector3(width * 0.72, 0.12, (length + 0.4) / roof_segs * 1.04), b, _roof)
	# Ridge beam.
	_panel(Vector3(0, wall_h + 0.78, 0), Vector3(0.14, 0.14, length + 0.6), Basis(), _dark)


func _materials() -> void:
	if _plank != null:
		return
	_plank = StandardMaterial3D.new()
	_plank.albedo_color = Color(0.5, 0.36, 0.23)
	_plank.roughness = 0.95
	_dark = StandardMaterial3D.new()
	_dark.albedo_color = Color(0.3, 0.2, 0.13)
	_dark.roughness = 0.95
	_roof = StandardMaterial3D.new()
	_roof.albedo_color = Color(0.36, 0.42, 0.2)
	_roof.roughness = 1.0


func _panel(pos: Vector3, size: Vector3, basis: Basis, mat: Material) -> void:
	var body := RigidBody3D.new()
	body.freeze = true
	body.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	body.mass = maxf(size.x * size.y * size.z * 3.0, 0.3)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	body.add_child(mi)
	body.transform = Transform3D(basis, pos)
	add_child(body)
	panels.append(body)


func _apply_shake(amount: float) -> void:
	position.x += randf_range(-1, 1) * 0.01 * amount
	position.z += randf_range(-1, 1) * 0.01 * amount


func _on_hit(_from: Vector2) -> void:
	Sfx.play("wood_hit", global_position + Vector3(0, 0.6, 0), -4.0, 40)
	# Charring creeps over the hall as it takes damage.
	var k := clampf(1.0 - hp / max_hp, 0.0, 1.0)
	_plank.albedo_color = Color(0.5, 0.36, 0.23).lerp(Color(0.12, 0.1, 0.09), k * 0.8) if burning else _plank.albedo_color


func _on_ignite() -> void:
	if battle:
		battle.attach_fire(self, global_position + Vector3(0, 1.3, 0), 1.6)


func _break_apart(from: Vector2) -> void:
	var c := global_position
	for p in panels:
		p.freeze = false
		var away := (p.global_position - Vector3(from.x, c.y, from.y)).normalized()
		p.apply_impulse(away * randf_range(0.5, 1.6) + Vector3(randf_range(-0.4, 0.4), randf_range(0.2, 1.2), randf_range(-0.4, 0.4)),
			Vector3(randf_range(-0.2, 0.2), 0.2, randf_range(-0.2, 0.2)))
	if battle:
		battle.dust(c + Vector3(0, 0.6, 0), 20)
	Sfx.play("crumble", c, 0.0, 0)
	get_tree().create_timer(10.0, false).timeout.connect(func():
		for p in panels:
			if is_instance_valid(p):
				p.freeze = true
				var t := create_tween()
				t.tween_property(p, "position:y", p.position.y - 0.9, 3.0))
