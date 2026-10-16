extends SceneTree
## Prints which BoneAttachment3D each mesh hangs from.
func _init() -> void:
	var scene: Node = (load(OS.get_cmdline_user_args()[0]) as PackedScene).instantiate()
	for mi in scene.find_children("*", "MeshInstance3D", true, false):
		print(mi.name, " <- ", mi.get_parent().name)
	quit()
