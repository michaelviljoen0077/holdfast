extends Node3D
## Base for anything soldiers can hack, burn or topple: palisades, beached
## longboats, enemy longhouses and watchtowers.
##
## A structure occupies a footprint (a segment with thickness) on the nav grid
## and blocks it while standing. Damage chips it; at zero it breaks apart with
## physics and frees the ground.

signal destroyed(structure)
signal damaged(structure)

var team := 0
var hp := 30.0
var max_hp := 30.0
var label := "Structure"
var a := Vector2.ZERO          # footprint segment start (world xz)
var b := Vector2.ZERO          # footprint segment end
var thickness := 0.35
var blocks_nav := true
var flammable := false
var burning := false
var dead := false
var nav
var island
var battle
var _cells: Array[Vector2i] = []
var _shake := 0.0


func setup_footprint(p_nav, p_island, p_a: Vector2, p_b: Vector2, p_thickness: float) -> void:
	nav = p_nav
	island = p_island
	a = p_a
	b = p_b
	thickness = p_thickness
	if blocks_nav:
		_cells = nav.cells_along(a, b, thickness * 0.5)
		# The player's own walls have gates for the player's soldiers.
		nav.block(_cells, team == 0)


func centre() -> Vector2:
	return (a + b) * 0.5


## Closest point of the footprint to p, pushed out by `pad` on p's side.
func nearest_point(p: Vector2, pad := 0.0) -> Vector2:
	var ab := b - a
	var t := 0.0
	if ab.length_squared() > 1e-6:
		t = clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	var q := a + ab * t
	var off := p - q
	var d := off.length()
	if d < 1e-4:
		off = ab.orthogonal().normalized()
		d = 1.0
	return q + off / d * (thickness * 0.5 + pad)


func distance_to(p: Vector2) -> float:
	var ab := b - a
	var t := 0.0
	if ab.length_squared() > 1e-6:
		t = clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return maxf((a + ab * t).distance_to(p) - thickness * 0.5, 0.0)


func take_damage(amount: float, from: Vector2) -> void:
	if dead:
		return
	hp -= amount
	_shake = 1.0
	_on_hit(from)
	damaged.emit(self)
	if hp <= 0.0:
		dead = true
		if blocks_nav:
			nav.unblock(_cells)
		_break_apart(from)
		destroyed.emit(self)


## Fire: flammable structures burn down by themselves once lit.
func ignite() -> void:
	if burning or dead or not flammable:
		return
	burning = true
	_on_ignite()


func _process(dt: float) -> void:
	if burning and not dead:
		take_damage(dt * max_hp / 9.0, centre())
	if _shake > 0.0:
		_shake = maxf(_shake - dt * 6.0, 0.0)
		_apply_shake(_shake)


# Overridables -----------------------------------------------------------------

func _on_hit(_from: Vector2) -> void:
	pass


func _on_ignite() -> void:
	pass


func _apply_shake(_amount: float) -> void:
	pass


func _break_apart(_from: Vector2) -> void:
	pass


## Walkable standing spots around the footprint, nearest to `from` first.
func approach_points(from: Vector2) -> Array:
	var out := []
	var ab := b - a
	var along := ab.normalized() if ab.length_squared() > 1e-6 else Vector2.RIGHT
	var side := along.orthogonal()
	var half := ab.length() * 0.5
	var c := centre()
	for pad in [0.55, 0.9, 1.4]:
		var reach: float = thickness * 0.5 + pad
		for t in [-0.6, -0.3, 0.0, 0.3, 0.6]:
			for sgn in [-1.0, 1.0]:
				out.append(c + along * half * t + side * reach * sgn)
		out.append(c + along * (half + pad))
		out.append(c - along * (half + pad))
	var ok := out.filter(func(p): return nav.is_walkable(nav.cell_of(p)))
	ok.sort_custom(func(p, q): return p.distance_to(from) < q.distance_to(from))
	return ok


## First approach point the squad can actually path to, as [point, path].
func reachable_approach(from: Vector2) -> Array:
	for p in approach_points(from):
		var path: PackedVector2Array = nav.find_path(from, p)
		if not path.is_empty() and path[path.size() - 1].distance_to(p) < 0.8:
			return [p, path]
	return []
