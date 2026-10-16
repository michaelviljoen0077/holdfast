extends Node
## Command-line driven screenshot capture, used for automated visual review.
##
## godot --path . -- --capture=shots/a.png --frames=120 [--seed=7] [--cam=wide] [--collapse=40]
## Arguments after the "--" separator are parsed into key/value pairs any script can query.

var _args := {}
var _frame := 0
var _target := -1
var _path := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			continue
		var kv := a.substr(2).split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else "true"
	if _args.has("capture"):
		_path = _args["capture"]
		_target = int(_args.get("frames", "120"))


func has(key: String) -> bool:
	return _args.has(key)


func arg(key: String, fallback := "") -> String:
	return str(_args.get(key, fallback))


func frame() -> int:
	return _frame


func _process(_dt: float) -> void:
	_frame += 1
	if _target > 0 and _frame == _target:
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var err := img.save_png(_path)
		print("captured %s (err %d)" % [_path, err])
		get_tree().quit()
