extends CanvasLayer
## Esc menu: pause, settings, restart, leave. Works while the tree is paused.

const UI := preload("res://scripts/ui/ui_theme.gd")

signal resumed

var _root: Control
var _main_box: VBoxContainer
var _settings_box: VBoxContainer
var allow_restart := true
var settings_only := false     # opened from the title: just the settings page


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.theme = UI.theme()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.02, 0.03, 0.62)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(shade)

	_main_box = _column()
	_main_box.add_child(_title("Paused"))
	_button(_main_box, "Resume", close)
	_button(_main_box, "Settings", func(): _show(_settings_box))
	if allow_restart and not Campaign.active:
		_button(_main_box, "Restart island", func():
			_unpause()
			get_tree().reload_current_scene())
	_button(_main_box, "Abandon campaign" if Campaign.active else "Return to title", func():
		_unpause()
		Campaign.active = false
		Fader.go("res://scenes/title.tscn"))

	_settings_box = _column()
	_settings_box.add_child(_title("Settings"))
	_slider(_settings_box, "Master volume", Settings.master, func(v): Settings.master = v)
	_slider(_settings_box, "Effects", Settings.effects, func(v): Settings.effects = v)
	_slider(_settings_box, "Ambience", Settings.ambience, func(v): Settings.ambience = v)
	_slider(_settings_box, "Music", Settings.music, func(v): Settings.music = v)
	_toggle(_settings_box, "Fullscreen", Settings.fullscreen, func(v): Settings.fullscreen = v)
	_toggle(_settings_box, "High quality shadows", Settings.shadows_high, func(v): Settings.shadows_high = v)
	_toggle(_settings_box, "Screen shake", Settings.screen_shake, func(v): Settings.screen_shake = v)
	_button(_settings_box, "Back", func():
		Settings.save()
		if settings_only:
			close()
		else:
			_show(_main_box))
	_show(_settings_box if settings_only else _main_box)
	if not settings_only:
		get_tree().paused = true


func _column() -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(460, 0)
	panel.position = Vector2(-230, -230)
	_root.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)
	return v


func _show(box: VBoxContainer) -> void:
	_main_box.get_parent().visible = box == _main_box
	_settings_box.get_parent().visible = box == _settings_box


func _title(text: String) -> Label:
	var l := UI.heading(text, 36)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


func _button(parent: Control, text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 50)
	b.pressed.connect(func():
		Sfx.play_ui("click", -8.0)
		cb.call())
	parent.add_child(b)


func _slider(parent: Control, text: String, value: float, setter: Callable) -> void:
	var row := HBoxContainer.new()
	var l := UI.label(text, 18)
	l.custom_minimum_size = Vector2(170, 0)
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.value = value
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.value_changed.connect(func(v: float):
		setter.call(v)
		Settings.apply())
	row.add_child(s)
	parent.add_child(row)


func _toggle(parent: Control, text: String, value: bool, setter: Callable) -> void:
	var c := CheckButton.new()
	c.text = text
	c.button_pressed = value
	c.toggled.connect(func(v: bool):
		setter.call(v)
		Settings.apply())
	parent.add_child(c)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
		if _settings_box.get_parent().visible and not settings_only:
			Settings.save()
			_show(_main_box)
		else:
			close()
		get_viewport().set_input_as_handled()


func close() -> void:
	Settings.save()
	_unpause()
	resumed.emit()
	queue_free()


func _unpause() -> void:
	get_tree().paused = false
