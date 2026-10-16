extends RefCounted
## Shared UI look: fonts, colours and widget styles for every screen.

const INK := Color(0.96, 0.93, 0.86)
const INK_DIM := Color(0.78, 0.74, 0.66)
const GOLD := Color(1.0, 0.8, 0.42)
const PANEL := Color(0.08, 0.07, 0.06, 0.82)
const EDGE := Color(0.55, 0.45, 0.3, 0.7)

static var _theme: Theme
static var _title: FontVariation
static var _body: Font
static var _bold: Font


static func body() -> Font:
	if _body == null:
		_body = load("res://assets/fonts/AlegreyaSans-Regular.ttf")
	return _body


static func bold() -> Font:
	if _bold == null:
		_bold = load("res://assets/fonts/AlegreyaSans-Bold.ttf")
	return _bold


static func title() -> FontVariation:
	if _title == null:
		_title = FontVariation.new()
		_title.base_font = load("res://assets/fonts/Cinzel.ttf")
		_title.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 700}
		_title.spacing_glyph = 1
	return _title


static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font = body()
	t.default_font_size = 18
	t.set_color("font_color", "Label", INK)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.55))
	t.set_constant("shadow_offset_x", "Label", 0)
	t.set_constant("shadow_offset_y", "Label", 2)
	t.set_constant("shadow_outline_size", "Label", 5)
	t.set_stylebox("normal", "Button", box(Color(0.16, 0.12, 0.09, 0.92), EDGE, 1))
	t.set_stylebox("hover", "Button", box(Color(0.26, 0.18, 0.11, 0.95), GOLD, 2))
	t.set_stylebox("pressed", "Button", box(Color(0.36, 0.22, 0.1, 0.98), GOLD, 2))
	t.set_stylebox("disabled", "Button", box(Color(0.1, 0.09, 0.08, 0.6), Color(0.3, 0.27, 0.24, 0.6), 1))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", INK)
	t.set_color("font_hover_color", "Button", Color(1, 0.95, 0.82))
	t.set_color("font_disabled_color", "Button", Color(0.5, 0.47, 0.42))
	t.set_font("font", "Button", bold())
	t.set_font_size("font_size", "Button", 19)
	t.set_stylebox("panel", "PanelContainer", box(PANEL, EDGE, 1))
	_theme = t
	return t


static func box(bg: Color, border: Color, bw: int, radius := 8) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	sb.shadow_color = Color(0, 0, 0, 0.3)
	sb.shadow_size = 6
	return sb


static func label(text: String, size := 18, col := INK, font: Font = null) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if font != null:
		l.add_theme_font_override("font", font)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func heading(text: String, size := 40, col := INK) -> Label:
	return label(text, size, col, title())
