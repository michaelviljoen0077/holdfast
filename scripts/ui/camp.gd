extends Control
## Between-battle screen: an ink-and-parchment sea chart for choosing the next
## island, and the war camp for spending gold on the warband.

const UI := preload("res://scripts/ui/ui_theme.gd")

const PARCHMENT := Color(0.87, 0.80, 0.64)
const PARCHMENT_DARK := Color(0.70, 0.60, 0.43)
const INK_DARK := Color(0.24, 0.17, 0.11)
const SEA_INK := Color(0.42, 0.52, 0.55)
const ROUTE := Color(0.62, 0.16, 0.10)

var _chart: Control
var _roster_box: VBoxContainer
var _gold: Label
var _leg: Label
var _sail: Button
var _detail: Label
var _hover := Vector2i(-1, -1)
var _picked := -1
var _t := 0.0
var _shapes := {}          # seed -> PackedVector2Array (unit blob)


func _ready() -> void:
	theme = UI.theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	if not Campaign.active:
		Campaign.new_campaign()
	var bg := ColorRect.new()
	bg.color = Color(0.09, 0.11, 0.13)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	_chart = Control.new()
	_chart.anchor_left = 0.0
	_chart.anchor_right = 0.66
	_chart.anchor_top = 0.0
	_chart.anchor_bottom = 1.0
	_chart.offset_left = 40
	_chart.offset_top = 110
	_chart.offset_right = -20
	_chart.offset_bottom = -40
	_chart.mouse_filter = Control.MOUSE_FILTER_STOP
	_chart.draw.connect(_draw_chart)
	_chart.gui_input.connect(_chart_input)
	add_child(_chart)

	_leg = UI.heading("", 34)
	_leg.position = Vector2(44, 30)
	add_child(_leg)
	_detail = UI.label("", 20, UI.INK_DIM)
	_detail.position = Vector2(46, 74)
	add_child(_detail)

	var side := PanelContainer.new()
	side.anchor_left = 0.66
	side.anchor_right = 1.0
	side.anchor_bottom = 1.0
	side.offset_left = 10
	side.offset_top = 30
	side.offset_right = -40
	side.offset_bottom = -40
	add_child(side)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	side.add_child(col)
	var head := HBoxContainer.new()
	col.add_child(head)
	head.add_child(UI.heading("War Camp", 30))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	_gold = UI.label("", 26, UI.GOLD, UI.bold())
	head.add_child(_gold)
	_roster_box = VBoxContainer.new()
	_roster_box.add_theme_constant_override("separation", 10)
	_roster_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_roster_box)
	_sail = Button.new()
	_sail.text = "Choose an island on the chart"
	_sail.custom_minimum_size = Vector2(0, 64)
	_sail.add_theme_font_override("font", UI.title())
	_sail.add_theme_font_size_override("font_size", 24)
	_sail.pressed.connect(_set_sail)
	col.add_child(_sail)

	Campaign.changed.connect(_refresh)
	_refresh()
	if Campaign.is_over():
		_show_end()


func _process(dt: float) -> void:
	_t += dt
	_chart.queue_redraw()


# Chart ----------------------------------------------------------------------

func _node_pos(c: int, i: int) -> Vector2:
	var r := _chart.size
	var x := lerpf(0.13, 0.93, float(c) / (Campaign.COLUMNS - 1))
	var y: float = Campaign.chart[c][i]["y"]
	return Vector2(x * r.x, lerpf(0.12, 0.88, y) * r.y)


func _harbour_pos() -> Vector2:
	return Vector2(_chart.size.x * 0.04, _chart.size.y * 0.5)


func _blob(seed_v: int) -> PackedVector2Array:
	if _shapes.has(seed_v):
		return _shapes[seed_v]
	var n := FastNoiseLite.new()
	n.seed = seed_v
	n.frequency = 1.3
	var pts := PackedVector2Array()
	for k in 28:
		var a := TAU * k / 28.0
		var r := 1.0 + n.get_noise_2d(cos(a) * 1.5, sin(a) * 1.5) * 0.45
		pts.append(Vector2(cos(a) * 1.15, sin(a) * 0.85) * r)
	_shapes[seed_v] = pts
	return pts


func _draw_chart() -> void:
	var r := Rect2(Vector2.ZERO, _chart.size)
	# Parchment with darkened, burnt edges.
	_chart.draw_rect(r, PARCHMENT)
	for k in 14:
		var inset := k * 4.0
		var a := 0.06 * (1.0 - k / 14.0)
		_chart.draw_rect(r.grow(-inset), Color(PARCHMENT_DARK.r, PARCHMENT_DARK.g, PARCHMENT_DARK.b, a), false, 8.0)
	# Faint chart grid and wave marks.
	for gx in range(1, 12):
		var x := r.size.x * gx / 12.0
		_chart.draw_line(Vector2(x, 0), Vector2(x, r.size.y), Color(SEA_INK, 0.12), 1.0)
	for gy in range(1, 8):
		var y := r.size.y * gy / 8.0
		_chart.draw_line(Vector2(0, y), Vector2(r.size.x, y), Color(SEA_INK, 0.12), 1.0)
	var wrng := RandomNumberGenerator.new()
	wrng.seed = 77
	for w in 60:
		var p := Vector2(wrng.randf() * r.size.x, wrng.randf() * r.size.y)
		var sway := sin(_t * 0.8 + w) * 2.0
		_chart.draw_arc(p + Vector2(sway, 0), 7.0, PI * 1.15, PI * 1.85, 6, Color(SEA_INK, 0.35), 1.5)
		_chart.draw_arc(p + Vector2(14 + sway, 0), 7.0, PI * 1.15, PI * 1.85, 6, Color(SEA_INK, 0.35), 1.5)
	_draw_compass(Vector2(r.size.x - 80, 80), 46.0)

	var chart: Array = Campaign.chart
	var reach: Array = Campaign.reachable()
	# Routes.
	for i in chart[0].size():
		_dashed(_harbour_pos(), _node_pos(0, i), Color(INK_DARK, 0.45))
	for c in chart.size() - 1:
		for i in chart[c].size():
			for j in chart[c][i]["links"]:
				_dashed(_node_pos(c, i), _node_pos(c + 1, j), Color(INK_DARK, 0.45))
	# Voyage so far, in red ink.
	var prev := _harbour_pos()
	for c in chart.size():
		for i in chart[c].size():
			if chart[c][i]["visited"]:
				var p := _node_pos(c, i)
				_chart.draw_line(prev, p, ROUTE, 3.0, true)
				prev = p
	# Islands.
	var font := UI.title()
	for c in chart.size():
		for i in chart[c].size():
			var node: Dictionary = chart[c][i]
			var p := _node_pos(c, i)
			var size := 30.0 if not node["finale"] else 46.0
			var shape := _blob(node["seed"])
			var sand := PackedVector2Array()
			var grass := PackedVector2Array()
			for q in shape:
				sand.append(p + q * size)
				grass.append(p + q * size * 0.72 + Vector2(0, -2))
			_chart.draw_colored_polygon(sand, Color(0.83, 0.72, 0.5))
			_chart.draw_polyline(sand + PackedVector2Array([sand[0]]), INK_DARK, 2.0, true)
			_chart.draw_colored_polygon(grass, Color(0.45, 0.55, 0.32) if not node["finale"] else Color(0.42, 0.38, 0.34))
			var selectable: bool = (c == Campaign.column + 1) and reach.has(i)
			if selectable:
				var pulse := 0.5 + 0.5 * sin(_t * 3.0)
				_chart.draw_arc(p, size * 1.6 + pulse * 4.0, 0, TAU, 40, Color(UI.GOLD, 0.5 + pulse * 0.4), 3.0, true)
			if _picked == i and selectable:
				_chart.draw_arc(p, size * 1.6 + 8.0, 0, TAU, 40, ROUTE, 4.0, true)
			if _hover == Vector2i(c, i):
				_chart.draw_arc(p, size * 1.35, 0, TAU, 40, Color(INK_DARK, 0.7), 2.0, true)
			if node["finale"]:
				_draw_skull(p + Vector2(0, -4), 12.0)
			var name: String = node["name"]
			var tw := font.get_string_size(name, HORIZONTAL_ALIGNMENT_CENTER, -1, 17).x
			_chart.draw_string(font, p + Vector2(-tw * 0.5, size + 26), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, INK_DARK)
			# Threat pips.
			var d: int = node["difficulty"]
			for k in 5:
				var pp := p + Vector2((k - 2) * 11.0, size + 40)
				if k <= d:
					_chart.draw_circle(pp, 3.6, ROUTE)
				else:
					_chart.draw_arc(pp, 3.6, 0, TAU, 10, Color(INK_DARK, 0.5), 1.2)
	# The warband's longship.
	var ship_at := _harbour_pos() if Campaign.column < 0 else _node_pos(Campaign.column, Campaign.node_i)
	_draw_ship(ship_at + Vector2(-8, -48 + sin(_t * 2.0) * 3.0))
	_chart.draw_string(UI.title(), _harbour_pos() + Vector2(-20, 70), "Harbour", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(INK_DARK, 0.8))


func _dashed(a: Vector2, b: Vector2, col: Color) -> void:
	var l := a.distance_to(b)
	var d := (b - a) / l
	var s := 0.0
	while s < l:
		_chart.draw_line(a + d * s, a + d * minf(s + 8.0, l), col, 2.0, true)
		s += 16.0


func _draw_compass(c: Vector2, r: float) -> void:
	_chart.draw_arc(c, r, 0, TAU, 48, Color(INK_DARK, 0.6), 2.0, true)
	_chart.draw_arc(c, r * 0.82, 0, TAU, 48, Color(INK_DARK, 0.35), 1.0, true)
	for k in 4:
		var a := k * PI * 0.5 - PI * 0.5
		var tip := c + Vector2(cos(a), sin(a)) * r
		var l := c + Vector2(cos(a + 0.5), sin(a + 0.5)) * r * 0.22
		var rr := c + Vector2(cos(a - 0.5), sin(a - 0.5)) * r * 0.22
		_chart.draw_colored_polygon(PackedVector2Array([tip, l, c]), INK_DARK)
		_chart.draw_colored_polygon(PackedVector2Array([tip, c, rr]), Color(INK_DARK, 0.35))
	_chart.draw_string(UI.title(), c + Vector2(-6, -r - 8), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, INK_DARK)


func _draw_ship(p: Vector2) -> void:
	var hull := PackedVector2Array([p + Vector2(-26, 0), p + Vector2(26, 0), p + Vector2(18, 10), p + Vector2(-18, 10)])
	_chart.draw_colored_polygon(hull, Color(0.35, 0.22, 0.13))
	_chart.draw_line(p + Vector2(-26, 0), p + Vector2(-32, -10), Color(0.35, 0.22, 0.13), 3.0)
	_chart.draw_line(p + Vector2(26, 0), p + Vector2(32, -10), Color(0.35, 0.22, 0.13), 3.0)
	_chart.draw_line(p + Vector2(0, 0), p + Vector2(0, -34), Color(0.3, 0.2, 0.12), 2.5)
	var sail := PackedVector2Array([p + Vector2(-15, -32), p + Vector2(15, -32), p + Vector2(17, -8), p + Vector2(-17, -8)])
	_chart.draw_colored_polygon(sail, Color(0.25, 0.38, 0.68))
	for k in 3:
		_chart.draw_line(p + Vector2(-16, -26 + k * 8), p + Vector2(16, -26 + k * 8), Color(0.95, 0.9, 0.78, 0.8), 2.0)


func _draw_skull(p: Vector2, s: float) -> void:
	_chart.draw_circle(p, s, Color(0.95, 0.9, 0.8))
	_chart.draw_rect(Rect2(p + Vector2(-s * 0.5, s * 0.6), Vector2(s, s * 0.6)), Color(0.95, 0.9, 0.8))
	_chart.draw_circle(p + Vector2(-s * 0.38, 0), s * 0.26, INK_DARK)
	_chart.draw_circle(p + Vector2(s * 0.38, 0), s * 0.26, INK_DARK)


func _chart_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		_hover = _island_at(e.position)
		_update_detail()
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		var hit := _island_at(e.position)
		if hit.x == Campaign.column + 1 and Campaign.reachable().has(hit.y):
			_picked = hit.y
			Sfx.play_ui("click", -8.0)
			_refresh()


func _island_at(p: Vector2) -> Vector2i:
	for c in Campaign.chart.size():
		for i in Campaign.chart[c].size():
			if _node_pos(c, i).distance_to(p) < 44.0:
				return Vector2i(c, i)
	return Vector2i(-1, -1)


func _update_detail() -> void:
	if _hover.x < 0:
		_detail.text = _default_detail()
		return
	var node: Dictionary = Campaign.chart[_hover.x][_hover.y]
	var waves := Campaign.waves_for(node)
	var boats := 0
	var drowned := false
	var chief := false
	for w in waves:
		boats += (w["boats"] as Array).size()
		drowned = drowned or w["boats"].has("draugr") or w["boats"].has("bowmen")
		chief = chief or w["boats"].has("chieftain")
	var what := "The Jarl's own fleet." if node["finale"] else "%d waves, %d longboats." % [waves.size(), boats]
	if drowned:
		what += "  The Drowned walk here."
	if chief:
		what += "  A chieftain leads them."
	_detail.text = "%s  —  %s" % [node["name"], what]


func _default_detail() -> String:
	var r: Dictionary = Campaign.last_result
	if r.is_empty():
		return "Pick the first island to defend. Harder islands pay the same per house but test the warband."
	var line := "%s %d of %d houses saved, +%d gold." % ["Held." if r["won"] else "Lost.", r["saved"], r["total"], r["earned"]]
	if not r["fallen"].is_empty():
		line += "  Fallen: %s." % ", ".join(r["fallen"])
	return line


# Roster ---------------------------------------------------------------------

func _refresh() -> void:
	_gold.text = "%d gold" % Campaign.gold
	_leg.text = "Sea Chart  ·  Island %d of %d" % [mini(Campaign.column + 2, Campaign.COLUMNS), Campaign.COLUMNS]
	_detail.text = _default_detail()
	for c in _roster_box.get_children():
		c.queue_free()
	for r in Campaign.roster:
		if r["alive"]:
			_roster_box.add_child(_squad_card(r))
	if Campaign.living_squads().size() < Campaign.MAX_SQUADS:
		var rec := HBoxContainer.new()
		rec.add_theme_constant_override("separation", 8)
		for kind in ["shield", "sword", "archer"]:
			var b := Button.new()
			b.text = "+ %s  %dg" % [Campaign.KINDS[kind]["title"], Campaign.COST_RECRUIT]
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.disabled = not Campaign.can_recruit()
			b.add_theme_font_size_override("font_size", 15)
			b.pressed.connect(func():
				Campaign.recruit(kind)
				Sfx.play_ui("order", -6.0))
			rec.add_child(b)
		_roster_box.add_child(UI.label("Recruit a new squad", 16, UI.INK_DIM))
		_roster_box.add_child(rec)
	var targetable := _picked >= 0
	_sail.disabled = not targetable or Campaign.is_over()
	if targetable:
		_sail.text = "Set sail for %s" % Campaign.chart[Campaign.column + 1][_picked]["name"]
	else:
		_sail.text = "Choose an island on the chart"


func _squad_card(r: Dictionary) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UI.box(Color(0.13, 0.1, 0.08, 0.95), UI.EDGE, 1))
	var v := VBoxContainer.new()
	p.add_child(v)
	var top := HBoxContainer.new()
	v.add_child(top)
	top.add_child(UI.label(r["name"], 22, UI.INK, UI.bold()))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(sp)
	top.add_child(UI.label("★".repeat(r["level"]) + "☆".repeat(3 - r["level"]), 20, UI.GOLD))
	var info: Dictionary = Campaign.KINDS[r["kind"]]
	var desc := "%d soldiers  ·  %s %s" % [info["size"], info["ability"], "ready" if r["ability"] else "locked"]
	v.add_child(UI.label(desc, 16, UI.INK_DIM))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	v.add_child(row)
	if not r["ability"]:
		var ub := Button.new()
		ub.text = "Teach %s  %dg" % [info["ability"], Campaign.COST_UNLOCK]
		ub.disabled = not Campaign.can_unlock(r)
		ub.add_theme_font_size_override("font_size", 15)
		ub.pressed.connect(func():
			Campaign.unlock(r)
			Sfx.play_ui("order", -6.0))
		row.add_child(ub)
	var cost := Campaign.train_cost(r)
	if cost > 0:
		var tb := Button.new()
		tb.text = "Train  %dg" % cost
		tb.disabled = not Campaign.can_train(r)
		tb.add_theme_font_size_override("font_size", 15)
		tb.pressed.connect(func():
			Campaign.train(r)
			Sfx.play_ui("order", -6.0))
		row.add_child(tb)
	return p


func _set_sail() -> void:
	if _picked < 0:
		return
	Campaign.sail_to(_picked)
	Sfx.play_ui("horn", -10.0)
	Fader.go("res://scenes/main.tscn")


func _show_end() -> void:
	var won: bool = Campaign.last_result.get("won", false) and Campaign.last_result.get("finale", false)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.6)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.position = Vector2(-400, -120)
	box.custom_minimum_size = Vector2(800, 240)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(box)
	var t := UI.heading("The Jarl's fleet is broken" if won else "Your warband is no more", 52, UI.GOLD if won else UI.INK)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(t)
	var sub := UI.label("The isles are safe — for now." if won else "The raiders will remember these shores.", 22, UI.INK_DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)
	var b := Button.new()
	b.text = "Return to the title"
	b.custom_minimum_size = Vector2(320, 56)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(func():
		Campaign.active = false
		Fader.go("res://scenes/title.tscn"))
	box.add_child(b)
