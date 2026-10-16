extends Control
## Threat readability layer: arrows on the screen edge pointing at longboats
## that are still out of view, and pulsing landing marks on the beaches they
## are heading for.

const UI := preload("res://scripts/ui/ui_theme.gd")

var director
var battle
var island
var rig
var _marks := {}           # boat dict id -> Decal
var _mark_tex: ImageTexture
var _t := 0.0
var night := false


func setup(p_director, p_battle, p_island, p_rig) -> void:
	director = p_director
	battle = p_battle
	island = p_island
	rig = p_rig
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mark_tex = _landing_texture()


func _landing_texture() -> ImageTexture:
	var size := 128
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var p := Vector2(x + 0.5 - size * 0.5, y + 0.5 - size * 0.5) / (size * 0.5)
			var r := p.length()
			var ring := smoothstep(0.72, 0.78, r) * (1.0 - smoothstep(0.9, 0.96, r))
			# Inward chevrons around the ring: "they land here".
			var ang := atan2(p.y, p.x)
			var tick := 1.0 if fmod(ang + TAU, TAU / 6.0) < 0.18 and r > 0.45 and r < 0.7 else 0.0
			var a := maxf(ring, tick * (1.0 - smoothstep(0.62, 0.7, r)))
			img.set_pixel(x, y, Color(1, 1, 1, a))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _process(dt: float) -> void:
	_t += dt / maxf(Engine.time_scale, 0.01)
	_update_marks()
	queue_redraw()


func _boat_color(b: Dictionary) -> Color:
	var sq = b["squad"]
	return sq.color if sq != null else Color(0.8, 0.22, 0.16)


func _update_marks() -> void:
	var live := {}
	for b in director.boats:
		if b["state"] != "sail" and b["state"] != "unload":
			continue
		if night and b["t"] < 0.55:
			continue
		var key: int = b["node"].get_instance_id()
		live[key] = true
		if not _marks.has(key):
			var d := Decal.new()
			d.texture_albedo = _mark_tex
			d.size = Vector3(3.2, 6.0, 3.2)
			d.cull_mask = 1 << 1
			d.modulate = _boat_color(b)
			var w: Vector2 = b["wade"]
			d.position = Vector3(w.x, maxf(island.height_at(w.x, w.y), 0.0), w.y)
			battle.add_child(d)
			_marks[key] = d
		var dec: Decal = _marks[key]
		var pulse := 0.8 + 0.2 * sin(_t * 5.0)
		dec.scale = Vector3(pulse, 1.0, pulse)
		dec.modulate.a = 0.55 + 0.35 * sin(_t * 5.0)
	for key in _marks.keys():
		if not live.has(key):
			(_marks[key] as Decal).queue_free()
			_marks.erase(key)


func _draw() -> void:
	if rig == null:
		return
	var cam: Camera3D = rig.camera
	_draw_routes(cam)
	var vp := get_viewport_rect().size
	var margin := 46.0
	var centre := vp * 0.5
	for b in director.boats:
		if b["state"] != "sail":
			continue
		# At night you only spot a longboat when it is nearly ashore.
		if night and b["t"] < 0.55:
			continue
		var node: Node3D = b["node"]
		var w := node.global_position + Vector3(0, 1.0, 0)
		var behind := cam.is_position_behind(w)
		var sp := cam.unproject_position(w)
		if behind:
			sp = centre - (sp - centre) * 10.0
		var inside := not behind and sp.x > margin and sp.y > margin and sp.x < vp.x - margin and sp.y < vp.y - 140
		if inside:
			continue
		var dir := (sp - centre).normalized()
		# Clamp to the screen rectangle.
		var half := Vector2(vp.x * 0.5 - margin, vp.y * 0.5 - margin - 50)
		var k := minf(absf(half.x / maxf(absf(dir.x), 0.001)), absf(half.y / maxf(absf(dir.y), 0.001)))
		var at := centre + dir * k
		var col := _boat_color(b)
		var bob := sin(_t * 6.0) * 4.0
		at += dir * bob
		var tip := at + dir * 16.0
		var side := dir.orthogonal() * 12.0
		draw_circle(at, 20.0, Color(0.06, 0.05, 0.05, 0.75))
		draw_colored_polygon(PackedVector2Array([tip, at - dir * 4.0 + side, at - dir * 4.0 - side]), col)
		draw_arc(at, 20.0, 0, TAU, 24, col, 2.0, true)
		# Seconds until landfall.
		var left: float = maxf((1.0 - b["t"]) * b["dur"], 0.0)
		var txt := "%d" % int(ceil(left))
		var f := UI.bold()
		var tw := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		draw_string(f, at - dir * 34.0 + Vector2(-tw * 0.5, 6), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UI.INK)


var _routes := {}       # boat id -> PackedVector2Array (world xz)


## Where each incoming crew will march: beach to the nearest house.
func _route_for(b: Dictionary) -> PackedVector2Array:
	var key: int = b["node"].get_instance_id()
	if _routes.has(key):
		return _routes[key]
	var wade: Vector2 = b["wade"]
	var best := Vector2.INF
	for h in battle.intact_houses():
		if best == Vector2.INF or wade.distance_to(h["door"]) < wade.distance_to(best):
			best = h["door"]
	var path := PackedVector2Array()
	if best != Vector2.INF:
		var nav = battle.nav
		var was: bool = nav.raider_mode
		nav.raider_mode = true
		path = nav.find_path(wade, best)
		nav.raider_mode = was
	_routes[key] = path
	return path


func _draw_routes(cam: Camera3D) -> void:
	if director.mode != "defend":
		return
	var live := {}
	for b in director.boats:
		if b["state"] != "sail" and b["state"] != "unload":
			continue
		if night and b["t"] < 0.55:
			continue
		var key: int = b["node"].get_instance_id()
		live[key] = true
		var path := _route_for(b)
		if path.size() < 2:
			continue
		var col := _boat_color(b)
		var dash := 0.0
		var phase := fmod(_t * 1.4, 1.0)
		for i in range(1, path.size()):
			var a := path[i - 1]
			var c := path[i]
			var seg := a.distance_to(c)
			var d := 0.0
			while d < seg:
				var p := a.lerp(c, d / seg)
				var w := Vector3(p.x, maxf(island.height_at(p.x, p.y), 0.0) + 0.15, p.y)
				if not cam.is_position_behind(w):
					var k := fmod(dash * 0.5 - phase + 10.0, 1.0)
					draw_circle(cam.unproject_position(w), 3.2, Color(col.r, col.g, col.b, 0.35 + 0.45 * k))
				d += 0.55
				dash += 1.0
	for key in _routes.keys():
		if not live.has(key):
			_routes.erase(key)
