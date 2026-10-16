extends CanvasLayer
## Fades to black between scenes and back in once the new scene is ready.

var _rect: ColorRect
var _busy := false
var _queued := ""


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rect = ColorRect.new()
	_rect.color = Color(0.03, 0.03, 0.04, 0.0)
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rect)


func go(scene_path: String, out_time := 0.35, in_time := 0.6) -> void:
	if _busy:
		# A request mid-fade is remembered and honoured once the fade settles.
		_queued = scene_path
		return
	_busy = true
	_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	var tw := create_tween()
	tw.tween_property(_rect, "color:a", 1.0, out_time)
	await tw.finished
	get_tree().paused = false
	Engine.time_scale = 1.0
	get_tree().change_scene_to_file(scene_path)
	# Give the new scene a couple of frames to build before revealing it.
	await get_tree().process_frame
	await get_tree().process_frame
	var tw2 := create_tween()
	tw2.tween_property(_rect, "color:a", 0.0, in_time)
	await tw2.finished
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_busy = false
	if _queued != "":
		var next := _queued
		_queued = ""
		go(next)
