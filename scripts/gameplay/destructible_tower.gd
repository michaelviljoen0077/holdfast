extends Node3D
## A round masonry tower built from individual rigid stone blocks.
## Blocks stay frozen (static, zero simulation cost) until the tower is struck;
## then the blast region is blown apart and unsupported masonry falls under physics.

const Props := preload("res://scripts/world/props.gd")
const Tex := preload("res://scripts/core/tex.gd")

@export var radius := 1.05
@export var rings := 12
@export var per_ring := 13
@export var block_h := 0.3

var blocks: Array[RigidBody3D] = []
var collapsed := false
var _mat: Material
var _dust: GPUParticles3D
var _rubble: GPUParticles3D


func build(prop_mat: Material, p_seed: int) -> void:
	_mat = prop_mat
	var rng := RandomNumberGenerator.new()
	rng.seed = p_seed
	var arc := TAU * radius / per_ring
	var size := Vector3(arc * 0.97, block_h * 0.96, 0.34)
	var variants: Array[ArrayMesh] = []
	for v in 5:
		variants.append(Props.stone_block(size, rng.randi()))
	var shape := BoxShape3D.new()
	shape.size = size

	for r in rings + 1:
		var crenel := r == rings
		var offset := 0.5 if r % 2 == 1 else 0.0
		for i in per_ring:
			if crenel and i % 2 == 1:
				continue
			var ang := TAU * (i + offset) / per_ring
			var pos := Vector3(cos(ang) * radius, block_h * (r + 0.5), sin(ang) * radius)
			var basis := Basis(Vector3.UP, -ang + PI * 0.5)
			_add_block(Transform3D(basis, pos), variants[rng.randi() % variants.size()], shape)

	# Dark rubble core: makes the mortar gaps between blocks read as depth.
	var core := MeshInstance3D.new()
	core.name = "Core"
	var cm := CylinderMesh.new()
	cm.top_radius = radius - 0.1
	cm.bottom_radius = radius - 0.1
	cm.height = block_h * rings
	cm.radial_segments = 24
	core.mesh = cm
	var core_mat := StandardMaterial3D.new()
	core_mat.albedo_color = Color(0.16, 0.14, 0.13)
	core_mat.roughness = 1.0
	core.material_override = core_mat
	core.position.y = block_h * rings * 0.5
	add_child(core)

	# Wooden roof deck and a banner pole: they fall with the masonry.
	var deck := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius - 0.1
	cyl.bottom_radius = radius - 0.1
	cyl.height = 0.08
	cyl.radial_segments = 16
	deck.mesh = cyl
	var deck_mat := StandardMaterial3D.new()
	deck_mat.albedo_color = Color(0.42, 0.3, 0.2)
	deck_mat.roughness = 0.9
	deck.material_override = deck_mat
	deck.position = Vector3(0, block_h * rings - 0.05, 0)
	add_child(deck)
	_build_banner(rng)
	_build_fx()


func _add_block(xf: Transform3D, mesh: ArrayMesh, shape: BoxShape3D) -> void:
	var body := RigidBody3D.new()
	body.transform = xf
	body.mass = 1.0
	body.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	body.freeze = true
	body.can_sleep = true
	var pm := PhysicsMaterial.new()
	pm.friction = 0.9
	pm.bounce = 0.05
	body.physics_material_override = pm
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat
	body.add_child(mi)
	add_child(body)
	blocks.append(body)


func _build_banner(rng: RandomNumberGenerator) -> void:
	var pole := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.025
	pm.bottom_radius = 0.03
	pm.height = 1.6
	pole.mesh = pm
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.3, 0.2, 0.13)
	pole.material_override = wood
	pole.position = Vector3(0, block_h * rings + 0.8, 0)
	add_child(pole)
	var flag := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.7, 0.42)
	q.subdivide_width = 8
	q.subdivide_depth = 4
	flag.mesh = q
	var sm := ShaderMaterial.new()
	sm.shader = preload("res://shaders/banner.gdshader")
	flag.material_override = sm
	flag.position = Vector3(0.36, block_h * rings + 1.38, 0)
	flag.name = "Banner"
	add_child(flag)


func _build_fx() -> void:
	_dust = GPUParticles3D.new()
	_dust.one_shot = true
	_dust.emitting = false
	_dust.amount = 90
	_dust.lifetime = 4.5
	_dust.explosiveness = 0.85
	_dust.local_coords = false
	_dust.visibility_aabb = AABB(Vector3(-10, -2, -10), Vector3(20, 14, 20))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 1.2
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 70.0
	pm.initial_velocity_min = 0.6
	pm.initial_velocity_max = 2.4
	pm.gravity = Vector3(0, 0.15, 0)
	pm.damping_min = 0.8
	pm.damping_max = 1.6
	pm.scale_min = 0.8
	pm.scale_max = 1.6
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.35))
	sc.add_point(Vector2(0.3, 0.85))
	sc.add_point(Vector2(1, 1.0))
	var sct := CurveTexture.new()
	sct.curve = sc
	pm.scale_curve = sct
	var g := Gradient.new()
	g.set_color(0, Color(0.82, 0.76, 0.66, 0.0))
	g.add_point(0.08, Color(0.82, 0.76, 0.66, 0.7))
	g.set_color(g.get_point_count() - 1, Color(0.78, 0.74, 0.68, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	_dust.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(1.4, 1.4)
	var dm := StandardMaterial3D.new()
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	dm.vertex_color_use_as_albedo = true
	dm.albedo_texture = Tex.radial_soft(64)
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	dm.proximity_fade_enabled = true
	dm.proximity_fade_distance = 0.6
	quad.material = dm
	_dust.draw_pass_1 = quad
	add_child(_dust)

	# Small stone chips: cheap GPU debris layered over the rigid blocks.
	_rubble = GPUParticles3D.new()
	_rubble.one_shot = true
	_rubble.emitting = false
	_rubble.amount = 160
	_rubble.lifetime = 3.0
	_rubble.explosiveness = 0.95
	_rubble.local_coords = false
	_rubble.visibility_aabb = AABB(Vector3(-10, -3, -10), Vector3(20, 14, 20))
	var rp := ParticleProcessMaterial.new()
	rp.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	rp.emission_sphere_radius = 0.6
	rp.direction = Vector3(0, 1, 0)
	rp.spread = 80.0
	rp.initial_velocity_min = 2.0
	rp.initial_velocity_max = 6.0
	rp.gravity = Vector3(0, -9.8, 0)
	rp.angular_velocity_min = -400.0
	rp.angular_velocity_max = 400.0
	rp.scale_min = 0.4
	rp.scale_max = 1.2
	rp.collision_mode = ParticleProcessMaterial.COLLISION_RIGID
	rp.collision_bounce = 0.2
	rp.collision_friction = 0.8
	_rubble.process_material = rp
	var chip := BoxMesh.new()
	chip.size = Vector3(0.07, 0.05, 0.06)
	var cm := StandardMaterial3D.new()
	cm.albedo_color = Color(0.58, 0.55, 0.5)
	cm.roughness = 0.95
	chip.material = cm
	_rubble.draw_pass_1 = chip
	add_child(_rubble)


## Strike the tower at a world-space point.
func collapse(hit_point: Vector3, power := 9.0) -> void:
	if collapsed:
		return
	collapsed = true
	var local_hit := to_local(hit_point)
	for b in blocks:
		b.freeze = false
		var d := b.position - local_hit
		var dist := d.length()
		var falloff := clampf(1.0 - dist / 2.6, 0.0, 1.0)
		if falloff > 0.0:
			var dir := (d.normalized() + Vector3(0, 0.35, 0)).normalized()
			b.apply_impulse(dir * power * falloff * falloff * randf_range(0.7, 1.2), Vector3(randf_range(-0.1, 0.1), randf_range(-0.1, 0.1), 0))
		b.apply_torque_impulse(Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.15)
	get_node("Core").queue_free()
	for child in get_children():
		if child is MeshInstance3D and child.name != "Core":
			_drop_attachment(child)
	_dust.global_position = hit_point + Vector3(0, 0.4, 0)
	_dust.restart()
	_rubble.global_position = hit_point
	_rubble.restart()
	# A second, lower dust wave when the upper masonry hits the ground.
	get_tree().create_timer(1.1).timeout.connect(func() -> void:
		_dust.global_position = global_position + Vector3(0, 0.3, 0)
		_dust.restart())


## Converts a static decoration into a falling rigid body.
func _drop_attachment(mi: MeshInstance3D) -> void:
	var body := RigidBody3D.new()
	body.mass = 0.5
	var xf := mi.global_transform
	remove_child(mi)
	add_child(body)
	body.global_transform = xf
	mi.transform = Transform3D.IDENTITY
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = mi.mesh.get_aabb().size.max(Vector3(0.05, 0.05, 0.05))
	cs.shape = shape
	body.add_child(cs)
	body.apply_impulse(Vector3(randf_range(-1, 1), 1.0, randf_range(-1, 1)))
