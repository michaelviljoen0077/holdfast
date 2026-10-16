extends CanvasLayer
## In-game HUD: squad cards, wave announcements, village status, tower ability.

signal card_pressed(squad)
signal topple_pressed

var battle
var director
var commander

var _cards := {}            # squad -> {panel, pips, name}
var _card_row: HBoxContainer
var _banner: Label
var _sub: Label
var _status: Label
var _ability: Button
var _end_panel: PanelContainer
var _end_title: Label
var _end_detail: Label
var _banner_t := 0.0
var _hint: Label
var _boss_box: VBoxContainer
var _boss_bar: ProgressBar

const INK := Color(0.96, 0.93, 0.86)
const PANEL := Color(0.08, 0.07, 0.06, 0.78)


func setup(p_battle, p_director, p_commander) -> void:
	battle = p_battle
	director = p_director
	commander = p_commander
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_card_row = HBoxContainer.new()
	_card_row.add_theme_constant_override("separation", 12)
	_card_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_card_row.anchor_left = 0.0
	_card_row.anchor_right = 1.0
	_card_row.anchor_top = 1.0
	_card_row.anchor_bottom = 1.0
	_card_row.offset_top = -112
	_card_row.offset_bottom = -44
	_card_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_card_row)

	_banner = _label(40, INK)
	_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.position = Vector2(-500, 54)
	_banner.size = Vector2(1000, 50)
	root.add_child(_banner)
	_sub = _label(20, INK.darkened(0.12))
	_sub.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub.position = Vector2(-500, 104)
	_sub.size = Vector2(1000, 30)
	root.add_child(_sub)

	var status_panel := _panel()
	status_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	status_panel.position = Vector2(-300, 20)
	status_panel.custom_minimum_size = Vector2(280, 0)
	root.add_child(status_panel)
	_status = _label(18, INK)
	status_panel.add_child(_status)

	_ability = Button.new()
	_ability.text = "  Topple the Tower   [T]  "
	_ability.add_theme_font_size_override("font_size", 18)
	_ability.add_theme_stylebox_override("normal", _box(Color(0.32, 0.18, 0.1, 0.85), Color(0.85, 0.65, 0.35), 2))
	_ability.add_theme_stylebox_override("hover", _box(Color(0.45, 0.25, 0.12, 0.92), Color(1.0, 0.8, 0.45), 2))
	_ability.add_theme_stylebox_override("pressed", _box(Color(0.6, 0.32, 0.12, 0.95), Color(1.0, 0.85, 0.5), 2))
	_ability.add_theme_stylebox_override("disabled", _box(Color(0.12, 0.11, 0.1, 0.6), Color(0.3, 0.28, 0.25), 2))
	_ability.add_theme_color_override("font_color", INK)
	_ability.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_ability.position = Vector2(-320, -86)
	_ability.custom_minimum_size = Vector2(290, 52)
	_ability.focus_mode = Control.FOCUS_NONE
	_ability.pressed.connect(func(): topple_pressed.emit())
	root.add_child(_ability)

	_boss_box = VBoxContainer.new()
	_boss_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_boss_box.position = Vector2(-330, 150)
	_boss_box.custom_minimum_size = Vector2(660, 0)
	_boss_box.visible = false
	_boss_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bname := _label(24, Color(0.75, 1.0, 0.92))
	bname.text = "Haldor, the Drowned Jarl"
	bname.add_theme_font_override("font", preload("res://scripts/ui/ui_theme.gd").title())
	bname.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_box.add_child(bname)
	_boss_bar = ProgressBar.new()
	_boss_bar.show_percentage = false
	_boss_bar.custom_minimum_size = Vector2(660, 14)
	_boss_bar.add_theme_stylebox_override("background", _flat(Color(0.08, 0.07, 0.07, 0.85)))
	_boss_bar.add_theme_stylebox_override("fill", _flat(Color(0.25, 0.75, 0.62)))
	_boss_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boss_box.add_child(_boss_bar)
	root.add_child(_boss_box)

	_hint = _label(15, INK.darkened(0.25))
	_hint.text = "LMB select  •  RMB move  •  F squad ability  •  Rest at a house to refit  •  T topple tower  •  WASD / Q E / wheel"
	_hint.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_hint.position = Vector2(24, -36)
	root.add_child(_hint)

	_end_panel = _panel()
	_end_panel.set_anchors_preset(Control.PRESET_CENTER)
	_end_panel.position = Vector2(-380, -100)
	_end_panel.custom_minimum_size = Vector2(760, 200)
	_end_panel.visible = false
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	_end_panel.add_child(v)
	_end_title = _label(44, INK)
	_end_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_end_title)
	_end_detail = _label(22, INK.darkened(0.08))
	_end_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_end_detail)
	var again := _label(18, INK.darkened(0.2))
	again.text = "Press Enter to return to the sea chart" if Campaign.active else "R replay  ·  N new island  ·  Esc title"
	again.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(again)
	root.add_child(_end_panel)

	battle.message.connect(func(t: String): show_banner(t, "", 2.5))
	battle.house_lost.connect(func(_h): show_banner("A house has fallen", "", 2.5))
	battle.squad_refitted.connect(func(s): show_banner("%s refitted" % s.name, "Fresh recruits join from the village", 2.0))
	director.wave_started.connect(func(i: int, total: int, boats: int):
		Sfx.play_ui("horn", -5.0)
		show_banner("Wave %d of %d" % [i, total], "%d longboats sighted" % boats, 4.0))
	director.victory.connect(func():
		var saved: int = battle.intact_houses().size()
		var total: int = battle.houses.size()
		_end("The island holds" if saved == total else "Victory, at a cost", _stat_line()))
	director.defeat.connect(func(): _end("Your warband has fallen", _stat_line()))
	commander.selection_changed.connect(func(_s): _refresh_cards())
	_build_tutorial(root)
	commander.ability_state.connect(func(armed: bool):
		_ability.text = "  Click where it should fall  " if armed else "  Topple the Tower   [T]  ")


# Tutorial ----------------------------------------------------------------

var _tut_panel: PanelContainer
var _tut_label: Label
var _tut_step := -1
var _tut_t := 0.0
const TUTORIAL := [
	"Left-click one of your squads, or press 1, to select it.  Time slows while you decide.",
	"Right-click the ground to march there.  The dotted line shows the route.",
	"Watch the sea.  Longboats beach where raiders will land: meet them at the shore.",
	"Select a squad and press F to use its ability.",
	"Badly hurt squads can rest at a house door to refit.  Good luck.",
]


func _build_tutorial(root: Control) -> void:
	if Settings.tutorial_done or Capture.has("capture"):
		return
	_tut_panel = PanelContainer.new()
	_tut_panel.add_theme_stylebox_override("panel", _box(Color(0.1, 0.08, 0.06, 0.9), Color(1.0, 0.8, 0.45), 2))
	_tut_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_tut_panel.position = Vector2(24, -150)
	_tut_panel.custom_minimum_size = Vector2(560, 0)
	_tut_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tut_label = _label(19, INK)
	_tut_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tut_label.custom_minimum_size = Vector2(530, 0)
	_tut_panel.add_child(_tut_label)
	root.add_child(_tut_panel)
	commander.selection_changed.connect(func(s): if s != null and _tut_step == 0: _tut_next())
	battle.ability_used.connect(func(_s): if _tut_step == 3: _tut_next())
	_tut_next()


func _tut_next() -> void:
	_tut_step += 1
	_tut_t = 0.0
	if _tut_step >= TUTORIAL.size():
		Settings.tutorial_done = true
		Settings.save()
		create_tween().tween_property(_tut_panel, "modulate:a", 0.0, 0.6)
		return
	_tut_label.text = "%d / %d    %s" % [_tut_step + 1, TUTORIAL.size(), TUTORIAL[_tut_step]]
	_tut_panel.modulate.a = 0.0
	create_tween().tween_property(_tut_panel, "modulate:a", 1.0, 0.4)


func _tut_tick(real_dt: float) -> void:
	if _tut_panel == null or _tut_step >= TUTORIAL.size():
		return
	_tut_t += real_dt
	match _tut_step:
		1:
			for s in battle.squads:
				if s.team == battle.PLAYER and s.order != 0:
					_tut_next()
					return
		2:
			if director.wave_i > 0 and _tut_t > 8.0:
				_tut_next()
		4:
			if _tut_t > 9.0:
				_tut_next()


func show_banner(title: String, sub: String, secs: float) -> void:
	_banner.text = title
	_sub.text = sub
	_banner_t = secs
	_banner.modulate.a = 0.0
	_sub.modulate.a = 0.0


func _end(title: String, detail := "") -> void:
	_end_title.text = title
	_end_detail.text = detail
	_end_panel.visible = true
	_end_panel.modulate.a = 0.0
	create_tween().tween_property(_end_panel, "modulate:a", 1.0, 0.8)


func _label(size: int, col: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.add_theme_constant_override("shadow_outline_size", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _box(bg: Color, border: Color, bw: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	sb.shadow_color = Color(0, 0, 0, 0.3)
	sb.shadow_size = 6
	return sb


func _flat(c: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(2)
	return sb


func _panel() -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _box(PANEL, Color(0.5, 0.42, 0.3, 0.6), 1))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


func _refresh_cards() -> void:
	var mine: Array = battle.squads.filter(func(s): return s.team == battle.PLAYER)
	for s in mine:
		if not _cards.has(s):
			_cards[s] = _make_card(s, mine.find(s) + 1)
		var card: Dictionary = _cards[s]
		var sel: bool = s == commander.selected
		var border := Color(1.0, 0.85, 0.5) if sel else Color(0.5, 0.42, 0.3, 0.6)
		(card["panel"] as PanelContainer).add_theme_stylebox_override("panel", _box(Color(0.12, 0.1, 0.08, 0.9) if sel else PANEL, border, 2 if sel else 1))
		var pips: Array = card["pips"]
		var alive: int = s.alive_count()
		for i in pips.size():
			(pips[i] as ColorRect).color = s.color.lightened(0.15) if i < alive else Color(0.25, 0.22, 0.2, 0.8)
		(card["panel"] as PanelContainer).modulate.a = 1.0 if alive > 0 else 0.45
		var info: Dictionary = s.ability_info()
		var abil: Label = card["abil"]
		var bar: ProgressBar = card["bar"]
		if info.is_empty() or not s.ability_unlocked:
			abil.text = ""
			bar.visible = false
		else:
			bar.visible = true
			if s.ability_t > 0.0 and info["duration"] > 0.0:
				abil.text = "%s  active" % info["name"]
				bar.value = s.ability_t / info["duration"]
			elif s.ability_cd > 0.0:
				abil.text = "%s  %ds" % [info["name"], int(ceil(s.ability_cd))]
				bar.value = 1.0 - s.ability_cd / info["cooldown"]
			else:
				abil.text = "%s  ready  [F]" % info["name"]
				bar.value = 1.0
			if commander.ability_armed and sel:
				abil.text = "Click to target %s" % info["name"]


func _make_card(s, index: int) -> Dictionary:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(190, 0)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			card_pressed.emit(s))
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(v)
	var title := _label(18, INK)
	title.text = "%d   %s" % [index, s.name]
	v.add_child(title)
	var abil := _label(14, Color(1.0, 0.82, 0.5))
	v.add_child(abil)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 5)
	bar.max_value = 1.0
	bar.add_theme_stylebox_override("background", _flat(Color(0.2, 0.18, 0.16, 0.9)))
	bar.add_theme_stylebox_override("fill", _flat(Color(1.0, 0.75, 0.35)))
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(row)
	var pips: Array = []
	for i in s.units.size():
		var pip := ColorRect.new()
		pip.custom_minimum_size = Vector2(12, 12)
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(pip)
		pips.append(pip)
	v.add_child(bar)
	_card_row.add_child(panel)
	return {"panel": panel, "pips": pips, "abil": abil, "bar": bar}


func _process(dt: float) -> void:
	var real_dt := dt / maxf(Engine.time_scale, 0.01)
	_tut_tick(real_dt)
	if _banner_t > 0.0:
		_banner_t -= real_dt
		var a := clampf(minf(_banner_t, 1.0), 0.0, 1.0)
		var appear := clampf(_banner.modulate.a + real_dt * 3.0, 0.0, 1.0)
		_banner.modulate.a = minf(a, appear)
		_sub.modulate.a = _banner.modulate.a
	_refresh_cards()
	var boss = null
	for u in battle.units:
		if u.kind == "jarl" and not u.boarded:
			boss = u
	_boss_box.visible = boss != null and boss.alive()
	if boss != null:
		_boss_bar.value = lerpf(_boss_bar.value, boss.hp / boss.max_hp * 100.0, clampf(real_dt * 6.0, 0.0, 1.0))
	var houses: int = battle.intact_houses().size()
	var raiders: int = director.raiders_alive()
	var next: float = director.time_to_next_wave()
	var lines := "Village   %d / %d houses\nRaiders ashore   %d" % [houses, battle.houses.size(), raiders]
	if next >= 0.0:
		lines += "\nNext wave in   %d s" % int(ceil(next))
	_status.text = lines
	_ability.disabled = battle.tower == null or battle.tower.collapsed
	if commander.selected != null or commander.topple_armed or commander.ability_armed:
		_hint.text = "Tactical pause  •  RMB move  •  F ability  •  Esc cancel"
	else:
		_hint.text = "LMB select  •  RMB move  •  F squad ability  •  Rest at a house to refit  •  T topple tower  •  WASD / Q E / wheel"


func _stat_line() -> String:
	var saved: int = battle.intact_houses().size()
	var total: int = battle.houses.size()
	var line := "Houses saved %d / %d    ·    Raiders slain %d    ·    Soldiers lost %d" % [saved, total, battle.stats["slain"], battle.stats["lost"]]
	if Campaign.active and director.raiders_alive() == 0:
		var gold := saved * Campaign.ISLAND_REWARD_PER_HOUSE + (15 if saved == total else 0)
		line += "\n+%d gold" % gold
	return line
