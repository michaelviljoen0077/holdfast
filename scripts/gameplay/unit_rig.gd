extends RefCounted
## Animated character visual built from a rigged glTF (KayKit Adventurers).
## Strips accessories the loadout doesn't use and drives the AnimationPlayer
## from simple high-level requests (locomotion, attack, hit, death...).

const LOOPING := ["Idle", "Walking_A", "Walking_B", "Walking_C", "Running_A", "Running_B",
	"2H_Melee_Idle", "Unarmed_Idle", "Blocking", "Cheer", "1H_Ranged_Aiming", "2H_Ranged_Aiming",
	"Sit_Floor_Idle", "Jump_Idle"]
const FLASH_SHADER := preload("res://shaders/hit_flash.gdshader")

static var _flash_mat: ShaderMaterial
static var _prepared := {}

var root: Node3D
var anim: AnimationPlayer
var meshes: Array[MeshInstance3D] = []
var current := ""
var _lock_t := 0.0          # one-shot animation playing; locomotion waits
var _flashing := false


func _init(scene: PackedScene, keep: PackedStringArray, scale: float) -> void:
	root = scene.instantiate()
	root.scale = Vector3.ONE * scale
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var parent := mi.get_parent()
		var in_hand := parent is BoneAttachment3D and String(parent.name).begins_with("handslot")
		if in_hand and not keep.has(String(mi.name)):
			parent.remove_child(mi)
			mi.free()
			continue
		var m := mi as MeshInstance3D
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		meshes.append(m)
	anim = root.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var key := scene.resource_path
	if not _prepared.has(key):
		_prepared[key] = true
		for n in LOOPING:
			if anim.has_animation(n):
				anim.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	if _flash_mat == null:
		_flash_mat = ShaderMaterial.new()
		_flash_mat.shader = FLASH_SHADER
	anim.playback_default_blend_time = 0.15
	anim.play("Idle")
	anim.seek(randf() * 1.5, true)
	current = "Idle"


## Continuous animation (idle, walk, run...). Ignored while a one-shot plays.
func loop(name: String, speed := 1.0) -> void:
	if _lock_t > 0.0:
		return
	if current != name:
		anim.play(name, 0.18)
		current = name
	anim.speed_scale = speed


## One-shot animation that blocks locomotion for `hold` seconds.
func once(name: String, speed := 1.0, hold := -1.0, blend := 0.08) -> void:
	if not anim.has_animation(name):
		return
	anim.play(name, blend)
	anim.seek(0.0, true)
	anim.speed_scale = speed
	current = name
	var length := anim.get_animation(name).length / maxf(speed, 0.01)
	_lock_t = length if hold < 0.0 else hold


## Death animation: plays once and stays on its final pose.
func die(name: String) -> void:
	_lock_t = 1e9
	anim.play(name, 0.06)
	anim.seek(0.0, true)
	anim.speed_scale = 1.1
	current = name


func tick(dt: float) -> void:
	if _lock_t > 0.0 and _lock_t < 1e8:
		_lock_t -= dt


func set_flash(v: float) -> void:
	if v > 0.01:
		if not _flashing:
			for m in meshes:
				m.material_overlay = _flash_mat
			_flashing = true
		for m in meshes:
			m.set_instance_shader_parameter("flash", v)
	elif _flashing:
		for m in meshes:
			m.material_overlay = null
		_flashing = false
