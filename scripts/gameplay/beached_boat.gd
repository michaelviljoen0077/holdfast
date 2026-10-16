extends "res://scripts/gameplay/structure.gd"
## A longboat run up on the shallows. Soldiers can wade out and set it alight:
## a burnt boat never sails home and pays a bounty.

var boat: Node3D
var _sinking := false


func setup(p_nav, p_island, p_boat: Node3D, bow: Vector2, stern: Vector2) -> void:
	label = "Longboat"
	team = 1
	flammable = true
	blocks_nav = false
	max_hp = 22.0
	hp = max_hp
	boat = p_boat
	setup_footprint(p_nav, p_island, bow, stern, 1.3)


func _on_hit(_from: Vector2) -> void:
	Sfx.play("wood_hit", Vector3(centre().x, 0.4, centre().y), -6.0, 40)


func _on_ignite() -> void:
	if battle:
		battle.attach_fire(boat, boat.global_position + Vector3(0, 0.9, 0), 1.2)


func _apply_shake(amount: float) -> void:
	if is_instance_valid(boat) and not _sinking:
		boat.rotation.z = randf_range(-1, 1) * 0.04 * amount


func _break_apart(_from: Vector2) -> void:
	_sinking = true
	if not is_instance_valid(boat):
		return
	var t := boat.create_tween()
	t.set_parallel(true)
	t.tween_property(boat, "position:y", -1.6, 6.0).set_ease(Tween.EASE_IN)
	t.tween_property(boat, "rotation:z", 0.5, 6.0)
	t.tween_property(boat, "rotation:x", -0.25, 6.0)
	if battle:
		battle.dust(boat.global_position + Vector3(0, 0.3, 0), 10)
		battle.stats["boats"] = battle.stats.get("boats", 0) + 1
		battle.message.emit("A longboat burns to the waterline")
