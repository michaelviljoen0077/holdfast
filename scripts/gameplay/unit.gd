extends RefCounted
## One soldier: simulation state plus its visual. The visual is either a rigged,
## animated character (UnitRig) or a static mesh animated procedurally.
## Models face +Z with their origin at the feet.

const UnitRig := preload("res://scripts/gameplay/unit_rig.gd")

enum State { IDLE, MOVE, FIGHT, DEAD }

const ANIMS := {
	"shield": {"attack": ["1H_Melee_Attack_Stab", "1H_Melee_Attack_Slice_Diagonal"], "idle": "Idle", "run": "Running_A"},
	"sword": {"attack": ["2H_Melee_Attack_Chop", "2H_Melee_Attack_Slice"], "idle": "2H_Melee_Idle", "run": "Running_A"},
	"archer": {"attack": ["1H_Ranged_Shoot"], "idle": "Idle", "aim": "1H_Ranged_Aiming", "run": "Running_B"},
	"raider": {"attack": ["1H_Melee_Attack_Chop", "1H_Melee_Attack_Slice_Horizontal"], "idle": "Idle", "run": "Running_A"},
	"berserker": {"attack": ["2H_Melee_Attack_Chop", "2H_Melee_Attack_Spin"], "idle": "2H_Melee_Idle", "run": "Running_B"},
	"chieftain": {"attack": ["2H_Melee_Attack_Spin", "2H_Melee_Attack_Chop", "2H_Melee_Attack_Slice"], "idle": "2H_Melee_Idle", "run": "Running_A"},
	"draugr": {"attack": ["1H_Melee_Attack_Chop", "1H_Melee_Attack_Slice_Diagonal"], "idle": "Idle_Combat", "run": "Running_C", "walk": "Walking_D_Skeletons", "death": "Death_C_Skeletons"},
	"draugr_archer": {"attack": ["1H_Ranged_Shoot"], "idle": "Idle", "aim": "1H_Ranged_Aiming", "run": "Running_A", "walk": "Walking_D_Skeletons", "death": "Death_C_Skeletons"},
	"jarl": {"attack": ["2H_Melee_Attack_Chop", "2H_Melee_Attack_Slice"], "idle": "Idle_Combat", "run": "Running_A", "walk": "Walking_D_Skeletons"},
	"champion": {"attack": ["1H_Melee_Attack_Chop", "1H_Melee_Attack_Jump_Chop"], "idle": "Idle_Combat", "run": "Running_A", "walk": "Walking_D_Skeletons"},
}

var team := 0
var squad                     # owning squad (untyped: avoids a cyclic preload)
var kind := "shield"          # shield | sword | archer | raider | berserker
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
var charge_hits := {}          # enemies already bowled over during this charge
var upath := PackedVector2Array()   # personal detour when the goal isn't in line of walk
var upath_i := 0
var upath_goal := Vector2.INF
var upath_t := 0.0
var state := State.IDLE
var dead_t := 0.0
var walk_phase := 0.0
var fall_dir := 1.0
var node: Node3D
var body: MeshInstance3D
var rig                        # UnitRig, when the visual is an animated character
var can_rise := false          # draugr reassemble once after being cut down
var heavy := false
var counted := false           # death already tallied in battle stats             # barely moved by knockback (bosses, champions)
var special_t := 0.0           # boss: seconds until the next slam
var summon_t := 0.0            # boss: seconds until the next summoning
var risen := false


## `visual` is a Mesh (procedural soldier) or a Dictionary {scene, keep, scale}.
func setup(parent: Node3D, visual, material: Material, p_pos: Vector2, p_y: float) -> void:
	pos = p_pos
	y = p_y
	node = Node3D.new()
	if visual is Dictionary:
		rig = UnitRig.new(visual["scene"], PackedStringArray(visual["keep"]), visual["scale"], visual.get("attach", {}))
		node.add_child(rig.root)
	else:
		body = MeshInstance3D.new()
		body.mesh = visual
		body.material_override = material
		node.add_child(body)
	parent.add_child(node)
	walk_phase = randf() * TAU
	update_visual(0.0)


func alive() -> bool:
	return state != State.DEAD


func _anims() -> Dictionary:
	return ANIMS.get(kind, ANIMS["shield"])


func on_swing() -> void:
	if rig:
		var list: Array = _anims()["attack"]
		var sp := 1.6 if attack_range <= 0.0 else 1.5
		rig.once(list[randi() % list.size()], sp, 0.62)


func on_block() -> void:
	if rig and swing_t < 0.0:
		rig.once("Block_Hit", 1.5, 0.35)


func on_hop() -> void:
	if rig:
		rig.once("Jump_Full_Short", 1.35, 0.55)


func cheer() -> void:
	if rig and alive():
		rig.once("Cheer", randf_range(0.9, 1.1), 1e8)


func take_hit(amount: float, from: Vector2) -> void:
	if not alive():
		return
	hp -= amount
	flash = 1.0
	var away := (pos - from).normalized()
	knock += away * (0.25 if heavy else 1.6)
	if hp <= 0.0:
		state = State.DEAD
		dead_t = 0.0
		fall_dir = 1.0 if randf() < 0.5 else -1.0
		facing = atan2(-away.x, -away.y)
		if rig:
			var a := _anims()
			rig.die(a["death"] if a.has("death") else ("Death_A" if randf() < 0.5 else "Death_B"))
	elif rig and swing_t < 0.0 and not heavy:
		rig.once("Hit_A" if randf() < 0.5 else "Hit_B", 1.5, 0.3)


func update_visual(dt: float) -> void:
	flash = maxf(flash - dt * 5.0, 0.0)
	if rig:
		_update_rig(dt)
		return
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


func _update_rig(dt: float) -> void:
	rig.tick(dt)
	rig.set_flash(flash)
	if state == State.DEAD:
		dead_t += dt
		var sink := clampf((dead_t - 6.0) / 3.0, 0.0, 1.0) * 0.35
		node.position = Vector3(pos.x, y - sink, pos.y)
		node.rotation.y = facing
		return
	node.position = Vector3(pos.x, y, pos.y)
	node.rotation.y = facing
	if hop_t >= 0.0:
		return
	var a := _anims()
	if boarded:
		rig.loop(a["idle"])
		return
	if squad != null and squad.braced():
		rig.loop("Blocking")
		return
	var spd := vel.length()
	if spd > 1.1:
		rig.loop(a["run"], clampf(spd / 1.7, 0.75, 1.5))
	elif spd > 0.22:
		rig.loop(a.get("walk", "Walking_A"), clampf(spd / 0.55, 0.8, 1.7))
	elif target != null and a.has("aim"):
		rig.loop(a["aim"])
	else:
		rig.loop(a["idle"])


## Draugr pull themselves back together, once.
func rise() -> void:
	risen = true
	counted = false
	state = State.IDLE
	hp = max_hp * 0.5
	dead_t = 0.0
	target = null
	swing_t = -1.0
	if rig:
		rig.once("Death_C_Skeletons_Resurrect", 1.0)


func free_visual() -> void:
	if is_instance_valid(node):
		node.queue_free()
