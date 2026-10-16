extends "res://scripts/gameplay/structure.gd"
## A wooden palisade: sharpened stakes lashed to two rails. Each stake is its
## own frozen rigid body, so hacking the wall loosens individual stakes and
## breaking it sends the logs tumbling.

const STAKE_GAP := 0.2
const HEIGHT := 0.95

static var _stake_mesh: ArrayMesh
static var _rail_mesh: ArrayMesh
static var _wood: StandardMaterial3D

var stakes: Array[RigidBody3D] = []
var rails: Array[MeshInstance3D] = []
var _rest: Array[Transform3D] = []


func build(p_nav, p_island, p_a: Vector2, p_b: Vector2, p_team := 0) -> void:
	team = p_team
	label = "Palisade"
	flammable = true
	var length := p_a.distance_to(p_b)
	max_hp = 18.0 + length * 8.0
	hp = max_hp
	setup_footprint(p_nav, p_island, p_a, p_b, 0.34)
	_ensure_meshes()
	var dir := (p_b - p_a) / maxf(length, 0.001)
	var yaw := atan2(dir.x, dir.y)
	var count := maxi(2, int(length / STAKE_GAP) + 1)
	var shape := CylinderShape3D.new()
	shape.radius = 0.075
	shape.height = HEIGHT
	var rng := RandomNumberGenerator.new()
	rng.seed = int(p_a.x * 1000.0 + p_b.y * 77.0)
	for i in count:
		var p := p_a.lerp(p_b, float(i) / (count - 1))
		var gy: float = island.height_at(p.x, p.y)
		var body := RigidBody3D.new()
		body.freeze = true
		body.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
		body.mass = 0.6
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.position.y = HEIGHT * 0.5
		body.add_child(cs)
		var mi := MeshInstance3D.new()
		mi.mesh = _stake_mesh
		mi.material_override = _wood
		var h := rng.randf_range(0.88, 1.08)
		mi.scale = Vector3(1.0, h, 1.0)
		body.add_child(mi)
		# Stakes lean a touch outward, never in perfect rows.
		var lean := Basis(Vector3(cos(yaw), 0, -sin(yaw)), rng.randf_range(-0.06, 0.06)) * Basis(Vector3.UP, rng.randf() * TAU)
		body.transform = Transform3D(lean, Vector3(p.x, gy - 0.12, p.y))
		add_child(body)
		stakes.append(body)
		_rest.append(body.transform)
	# Two lashing rails along the inside face.
	for k in 2:
		var rail := MeshInstance3D.new()
		rail.mesh = _rail_mesh
		rail.material_override = _wood
		var mid := (p_a + p_b) * 0.5
		var gy2: float = (island.height_at(p_a.x, p_a.y) + island.height_at(p_b.x, p_b.y)) * 0.5
		rail.transform = Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(1, 1, length)), Vector3(mid.x, gy2 + 0.3 + k * 0.38, mid.y))
		add_child(rail)
		rails.append(rail)


static func _ensure_meshes() -> void:
	if _stake_mesh != null:
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	var sides := 6
	var r := 0.07
	for s in sides:
		var a0 := TAU * s / sides
		var a1 := TAU * (s + 1) / sides
		var p0 := Vector3(cos(a0) * r, 0, sin(a0) * r)
		var p1 := Vector3(cos(a1) * r, 0, sin(a1) * r)
		var top := Vector3(0, HEIGHT, 0)
		var shoulder0 := p0 + Vector3(0, HEIGHT - 0.16, 0)
		var shoulder1 := p1 + Vector3(0, HEIGHT - 0.16, 0)
		# Side quad then the sharpened tip.
		for v in [p0, shoulder1, p1, p0, shoulder0, shoulder1, shoulder0, top, shoulder1]:
			st.add_vertex(v)
	st.generate_normals()
	_stake_mesh = st.commit()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.05, 0.07, 1.0)
	_rail_mesh = bm
	_wood = StandardMaterial3D.new()
	_wood.albedo_color = Color(0.46, 0.33, 0.22)
	_wood.roughness = 0.95


func _apply_shake(amount: float) -> void:
	for i in stakes.size():
		var s := stakes[i]
		if s.freeze:
			var j := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * 0.025 * amount
			s.transform = Transform3D(_rest[i].basis, _rest[i].origin + j)


func _on_hit(from: Vector2) -> void:
	# Every blow has a chance to knock a stake loose so damage is visible.
	if stakes.is_empty():
		return
	var frac := 1.0 - hp / max_hp
	var loose := int(frac * stakes.size() * 0.45)
	var loosened := 0
	for s in stakes:
		if not s.freeze:
			loosened += 1
	if loosened < loose:
		for s in stakes:
			if s.freeze and randf() < 0.3:
				_release(s, from, 1.2)
				break
	Sfx.play("wood_hit", Vector3(centre().x, island.height_at(centre().x, centre().y) + 0.5, centre().y), -6.0, 40)


func _release(s: RigidBody3D, from: Vector2, power: float) -> void:
	s.freeze = false
	var c := s.global_position
	var away := Vector3(c.x - from.x, 0.0, c.z - from.y).normalized()
	s.apply_impulse(away * power + Vector3(0, 0.6, 0), Vector3(0, 0.7, 0))


func _break_apart(from: Vector2) -> void:
	for s in stakes:
		if s.freeze:
			_release(s, from, randf_range(1.5, 3.0))
	for r in rails:
		var t := create_tween()
		t.tween_property(r, "position:y", r.position.y - 0.4, 0.4)
		t.tween_callback(r.queue_free)
	Sfx.play("stone", Vector3(centre().x, island.height_at(centre().x, centre().y), centre().y), -2.0, 0)
	# Fallen logs settle, then sink away.
	get_tree().create_timer(9.0, false).timeout.connect(func():
		for s in stakes:
			if is_instance_valid(s):
				s.freeze = true
				var t2 := create_tween()
				t2.tween_property(s, "position:y", s.position.y - 0.6, 2.0)))


func _on_ignite() -> void:
	if battle:
		battle.attach_fire(self, Vector3(centre().x, island.height_at(centre().x, centre().y) + 0.6, centre().y), 0.6)
