extends RefCounted
## One soldier: simulation state plus its procedurally animated visual.
## The mesh origin sits at the feet and the model faces +Z.

enum State { IDLE, MOVE, FIGHT, DEAD }

var team := 0
var squad                     # owning squad (untyped: avoids a cyclic preload)
var kind := "spear"           # spear | archer | raider
var pos := Vector2.ZERO
var y := 0.0
var vel := Vector2.ZERO
var facing := 0.0
var hp := 3.0
var max_hp := 3.0
var speed := 2.2
var reach := 0.62
var damage := 1.0
var cooldown := 0.9
var attack_range := 0.0       # > 0 for ranged units
var attack_t := 0.0           # time until the next attack may start
var swing_t := -1.0           # >= 0 while an attack animation plays
var swing_target              # who the current swing will hit
var flash := 0.0
var knock := Vector2.ZERO
var target                    # current enemy
var slot := Vector2.ZERO      # formation position this unit is holding
var slot_i := -1
var boarded := false          # riding a boat; position driven by the boat
var hop_t := -1.0             # >= 0 while jumping from a boat into the shallows
var hop_from := Vector3.ZERO
var hop_to := Vector2.ZERO
var state := State.IDLE
var dead_t := 0.0
var walk_phase := 0.0
var fall_dir := 1.0
var node: Node3D
var body: MeshInstance3D


func setup(parent: Node3D, mesh: Mesh, material: Material, p_pos: Vector2, p_y: float) -> void:
	pos = p_pos
	y = p_y
	node = Node3D.new()
	body = MeshInstance3D.new()
	body.mesh = mesh
	body.material_override = material
	node.add_child(body)
	parent.add_child(node)
	walk_phase = randf() * TAU
	update_visual(0.0)


func alive() -> bool:
	return state != State.DEAD


func take_hit(amount: float, from: Vector2) -> void:
	if not alive():
		return
	hp -= amount
	flash = 1.0
	var away := (pos - from).normalized()
	knock += away * 1.6
	if hp <= 0.0:
		state = State.DEAD
		dead_t = 0.0
		fall_dir = 1.0 if randf() < 0.5 else -1.0
		facing = atan2(-away.x, -away.y)


func update_visual(dt: float) -> void:
	flash = maxf(flash - dt * 5.0, 0.0)
	body.set_instance_shader_parameter("flash", flash)
	if state == State.DEAD:
		dead_t += dt
		# Topple backwards away from the killing blow, then sink into the ground.
		var f := clampf(dead_t / 0.38, 0.0, 1.0)
		var fall := 1.0 - pow(1.0 - f, 3.0)
		body.rotation = Vector3(-fall * PI * 0.47, 0.0, fall * 0.25 * fall_dir)
		var bounce := sin(clampf((dead_t - 0.38) / 0.18, 0.0, 1.0) * PI) * 0.03
		var sink := clampf((dead_t - 6.0) / 3.0, 0.0, 1.0) * 0.5
		node.position = Vector3(pos.x, y + bounce - sink, pos.y)
		node.rotation.y = facing
		return
	var spd := vel.length()
	var moving := clampf(spd / maxf(speed, 0.01), 0.0, 1.0)
	walk_phase += dt * (4.0 + spd * 7.0)
	var bob := absf(sin(walk_phase)) * 0.045 * moving
	node.position = Vector3(pos.x, y + bob, pos.y)
	node.rotation.y = facing
	# Attack: wind back, then thrust forward.
	var thrust := 0.0
	var wind := 0.0
	if swing_t >= 0.0:
		var t := swing_t
		if t < 0.18:
			wind = t / 0.18
		elif t < 0.28:
			thrust = (t - 0.18) / 0.1
			wind = 1.0 - thrust
		else:
			thrust = 1.0 - clampf((t - 0.28) / 0.3, 0.0, 1.0)
	var idle_breath := sin(walk_phase * 0.35) * 0.012 * (1.0 - moving)
	body.position = Vector3(0.0, idle_breath, thrust * 0.16 - wind * 0.06)
	body.rotation = Vector3(moving * 0.12 + thrust * 0.28 - wind * 0.12, 0.0, sin(walk_phase) * 0.07 * moving)


func free_visual() -> void:
	if is_instance_valid(node):
		node.queue_free()
