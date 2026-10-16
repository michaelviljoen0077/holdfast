extends Node
## Player settings, persisted to user://settings.cfg and applied on change.

signal changed

const PATH := "user://settings.cfg"

var master := 0.85
var effects := 0.9
var ambience := 0.75
var fullscreen := false
var shadows_high := true
var screen_shake := true
var tutorial_done := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for bus_name in ["Effects", "Ambience"]:
		if AudioServer.get_bus_index(bus_name) < 0:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, bus_name)
			AudioServer.set_bus_send(i, "Master")
	_load()
	apply()


func _load() -> void:
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return
	master = cf.get_value("audio", "master", master)
	effects = cf.get_value("audio", "effects", effects)
	ambience = cf.get_value("audio", "ambience", ambience)
	fullscreen = cf.get_value("video", "fullscreen", fullscreen)
	shadows_high = cf.get_value("video", "shadows_high", shadows_high)
	screen_shake = cf.get_value("game", "screen_shake", screen_shake)
	tutorial_done = cf.get_value("game", "tutorial_done", tutorial_done)


func save() -> void:
	var cf := ConfigFile.new()
	cf.set_value("audio", "master", master)
	cf.set_value("audio", "effects", effects)
	cf.set_value("audio", "ambience", ambience)
	cf.set_value("video", "fullscreen", fullscreen)
	cf.set_value("video", "shadows_high", shadows_high)
	cf.set_value("game", "screen_shake", screen_shake)
	cf.set_value("game", "tutorial_done", tutorial_done)
	cf.save(PATH)


func apply() -> void:
	_set_bus("Master", master)
	_set_bus("Effects", effects)
	_set_bus("Ambience", ambience)
	if not Capture.has("capture"):
		var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != mode:
			DisplayServer.window_set_mode(mode)
	RenderingServer.directional_shadow_atlas_set_size(8192 if shadows_high else 2048, true)
	RenderingServer.directional_soft_shadow_filter_set_quality(
		RenderingServer.SHADOW_QUALITY_SOFT_HIGH if shadows_high else RenderingServer.SHADOW_QUALITY_SOFT_LOW)
	changed.emit()


func _set_bus(bus_name: String, linear: float) -> void:
	var i := AudioServer.get_bus_index(bus_name)
	if i >= 0:
		AudioServer.set_bus_volume_db(i, linear_to_db(maxf(linear, 0.0001)))
		AudioServer.set_bus_mute(i, linear <= 0.001)
