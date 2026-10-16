extends Control
## Title screen. A live, self-playing battle runs behind the menu.

const UI := preload("res://scripts/ui/ui_theme.gd")
const GAME_TITLE := "HOLDFAST"   # working title

var _backdrop: Node


func _ready() -> void:
	theme = UI.theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var Main := load("res://scripts/main.gd")
	Main.attract = true
	_backdrop = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(_backdrop)

	# Soft vignette so the menu reads over the scene.
	var shade := TextureRect.new()
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0.0))
	g.set_color(1, Color(0, 0, 0, 0.62))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0.75, 0.5)
	gt.fill_to = Vector2(0.0, 0.5)
	shade.texture = gt
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)

	var col := VBoxContainer.new()
	col.position = Vector2(120, 300)
	col.custom_minimum_size = Vector2(520, 0)
	col.add_theme_constant_override("separation", 14)
	add_child(col)
	var title := UI.heading(GAME_TITLE, 96, UI.INK)
	title.add_theme_constant_override("shadow_outline_size", 12)
	col.add_child(title)
	col.add_child(UI.label("Raiders are coming. Hold the isles.", 26, UI.INK_DIM))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 40)
	col.add_child(gap)
	if Campaign.has_save():
		_button(col, "Continue Campaign", func():
			if Campaign.load_game():
				# Mid-island saves drop you straight back into that battle.
				_leave("res://scenes/main.tscn" if not Campaign.current.is_empty() else "res://scenes/camp.tscn"))
	_button(col, "New Campaign", func():
		Campaign.new_campaign()
		_leave("res://scenes/camp.tscn"))
	_button(col, "Quick Battle", func():
		Campaign.active = false
		_leave("res://scenes/main.tscn"))
	_button(col, "Settings", func():
		var pm := preload("res://scripts/ui/pause_menu.gd").new()
		pm.allow_restart = false
		pm.settings_only = true
		add_child(pm))
	_button(col, "Quit", func(): get_tree().quit())
	var foot := UI.label("Characters: KayKit (CC0)  ·  Fonts: Cinzel, Alegreya Sans (OFL)", 14, Color(UI.INK_DIM, 0.7))
	foot.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	foot.position = Vector2(24, -40)
	add_child(foot)


func _button(parent: Control, text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(360, 58)
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.add_theme_font_override("font", UI.title())
	b.add_theme_font_size_override("font_size", 24)
	b.pressed.connect(func():
		Sfx.play_ui("click", -6.0)
		cb.call())
	parent.add_child(b)


func _leave(scene: String) -> void:
	var Main := load("res://scripts/main.gd")
	Main.attract = false
	Engine.time_scale = 1.0
	Fader.go(scene)


func _exit_tree() -> void:
	# The backdrop lives under the root; take it down with the title.
	if is_instance_valid(_backdrop):
		_backdrop.queue_free()
