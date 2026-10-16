extends SceneTree
## Prints the node tree, skeleton bones and animations of a glTF scene.
## godot --headless --path . -s tools/inspect_glb.gd -- res://path.glb

func _init() -> void:
	var path: String = OS.get_cmdline_user_args()[0]
	var scene: Node = (load(path) as PackedScene).instantiate()
	_walk(scene, 0)
	for ap in scene.find_children("*", "AnimationPlayer", true, false):
		var names: PackedStringArray = (ap as AnimationPlayer).get_animation_list()
		print("ANIMS (%d): %s" % [names.size(), ", ".join(names)])
	for sk in scene.find_children("*", "Skeleton3D", true, false):
		var s := sk as Skeleton3D
		var bones := []
		for i in s.get_bone_count():
			bones.append(s.get_bone_name(i))
		print("BONES: ", ", ".join(bones))
	for mi in scene.find_children("*", "MeshInstance3D", true, false):
		print("MESH ", mi.name, " aabb ", (mi as MeshInstance3D).get_aabb())
	quit()

func _walk(n: Node, d: int) -> void:
	if d < 4:
		print("  ".repeat(d), n.name, " [", n.get_class(), "]")
	for c in n.get_children():
		_walk(c, d + 1)
