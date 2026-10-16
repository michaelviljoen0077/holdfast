extends RefCounted
## A squad: a group of units sharing an anchor that moves along a nav path.
## Units hold formation slots around the anchor and break ranks to fight.

enum Order { HOLD, MOVE, ATTACK_MOVE }

var team := 0
var name := ""
var kind := "spear"
var units: Array = []
var anchor := Vector2.ZERO
var facing := 0.0
var order := Order.HOLD
var path := PackedVector2Array()
var path_i := 0
var speed := 2.0
var spacing := 0.46
var cols := 3
var engage_radius := 3.8
var leash := 4.5
var selected := false
var color := Color.WHITE
var goal_house                # raider objective (untyped house record)
var in_combat := false
var refit_t := 0.0             # time spent resting at a house door
var refit_cooldown := 0.0
var visual                     # spawn spec, reused when replenishing
var level := 1
var siege                      # structure this squad is ordered to tear down
var formation := "block"       # block | line | wedge | ring
var end_facing := INF          # facing to adopt on arrival (set by right-drag)

const FORMATIONS := ["block", "line", "wedge", "ring"]
const FORMATION_NAMES := {"block": "Block", "line": "Line", "wedge": "Wedge", "ring": "Ring"}


func cycle_formation() -> void:
	formation = FORMATIONS[(FORMATIONS.find(formation) + 1) % FORMATIONS.size()]


## Speed multiplier from formation: a ring shuffles, a wedge drives.
func formation_speed() -> float:
	match formation:
		"ring":
			return 0.6
		"wedge":
			return 1.1
	return 1.0
var ability := ""              # brace | charge | volley
var ability_cd := 0.0          # seconds until usable again
var ability_t := 0.0           # seconds the effect remains active
var ability_unlocked := true

const ABILITIES := {
	"brace": {"name": "Brace", "cooldown": 22.0, "duration": 6.0, "targeted": false},
	"charge": {"name": "Charge", "cooldown": 20.0, "duration": 3.5, "targeted": true},
	"volley": {"name": "Volley", "cooldown": 16.0, "duration": 0.0, "targeted": true},
}


func ability_info() -> Dictionary:
	return ABILITIES.get(ability, {})


func ability_ready() -> bool:
	return ability != "" and ability_unlocked and ability_cd <= 0.0 and not is_dead()


func braced() -> bool:
	return ability == "brace" and ability_t > 0.0


func charging() -> bool:
	return ability == "charge" and ability_t > 0.0
var banner: Node3D


func alive_units() -> Array:
	return units.filter(func(u): return u.alive())


func alive_count() -> int:
	var c := 0
	for u in units:
		if u.alive():
			c += 1
	return c


func is_dead() -> bool:
	return alive_count() == 0


func set_path(p: PackedVector2Array, attack := false) -> void:
	path = p
	path_i = 1 if p.size() > 1 else 0
	order = Order.ATTACK_MOVE if attack else Order.MOVE
	if p.is_empty():
		order = Order.HOLD


func destination() -> Vector2:
	return path[path.size() - 1] if not path.is_empty() else anchor


## Advances the anchor along its path. Returns true on arrival.
func advance(dt: float, nav) -> bool:
	if order == Order.HOLD or path.is_empty():
		return false
	# Wait for stragglers so the formation arrives together.
	var lag := 0.0
	for u in units:
		if u.alive():
			lag = maxf(lag, u.pos.distance_to(u.slot))
	var pace := speed * clampf(1.4 - lag * 0.35, 0.35, 1.0)
	var step := pace * dt
	while step > 0.0 and path_i < path.size():
		var tgt := path[path_i]
		var to := tgt - anchor
		var d := to.length()
		if d > 0.001:
			var want := atan2(to.x, to.y)
			facing = lerp_angle(facing, want, clampf(dt * 6.0, 0.0, 1.0))
		if d <= step:
			anchor = tgt
			step -= d
			path_i += 1
		else:
			anchor += to / d * step
			step = 0.0
	if path_i >= path.size():
		order = Order.HOLD
		if end_facing != INF:
			facing = end_facing
			end_facing = INF
		return true
	return false


## World positions for each living unit's formation slot. Slot indices are
## only reshuffled when `reassign` is set (new order, casualties), so units
## don't swap places every frame.
func assign_slots(nav, reassign := false) -> void:
	var alive := alive_units()
	var count := alive.size()
	if count == 0:
		return
	var basis_x := Vector2(cos(facing), -sin(facing))   # local +x (right)
	var basis_z := Vector2(sin(facing), cos(facing))    # local +z (forward)
	var offsets: Array[Vector2] = []
	for o in formation_offsets(count):
		offsets.append(basis_x * o.x + basis_z * o.y)
	var need := reassign
	for u in alive:
		if u.slot_i < 0 or u.slot_i >= count:
			need = true
	if need:
		var taken := []
		taken.resize(count)
		taken.fill(false)
		for u in alive:
			var best := -1
			var best_d := INF
			for i in count:
				if taken[i]:
					continue
				var d: float = (anchor + offsets[i]).distance_squared_to(u.pos)
				if d < best_d:
					best_d = d
					best = i
			taken[best] = true
			u.slot_i = best
	for u in alive:
		var s: Vector2 = anchor + offsets[u.slot_i]
		if not nav.clear_line(anchor, s):
			s = anchor
		u.slot = s


## Local offsets (x right, y forward) for each formation.
func formation_offsets(count: int) -> Array[Vector2]:
	var out: Array[Vector2] = []
	match formation:
		"line":
			# Two ranks, wide front: more blades engage at once, flanks are thin.
			var per := int(ceil(count / 2.0))
			for i in count:
				var r := i / per
				var col := i % per
				var in_row := mini(per, count - r * per)
				out.append(Vector2((col - (in_row - 1) * 0.5) * spacing * 1.05, (0.5 - r) * spacing))
		"wedge":
			# Arrowhead with the point forward.
			var row := 0
			var placed := 0
			while placed < count:
				var in_row := mini(row * 2 + 1, count - placed)
				for k in in_row:
					out.append(Vector2((k - (in_row - 1) * 0.5) * spacing, -row * spacing * 0.9 + spacing))
				placed += in_row
				row += 1
		"ring":
			# Shields outward; one in the middle when there are enough.
			var outer := count if count < 7 else count - 1
			var radius := maxf(spacing * outer / TAU * 1.15, spacing)
			for i in outer:
				var a := TAU * i / outer
				out.append(Vector2(sin(a), cos(a)) * radius)
			if outer < count:
				out.append(Vector2.ZERO)
		_:
			var c := mini(cols, count)
			var rows := int(ceil(float(count) / c))
			for i in count:
				var r := i / c
				var col := i % c
				var in_row := mini(c, count - r * c)
				var stagger := 0.08 * (1 if (r + col) % 2 == 0 else -1)
				out.append(Vector2((col - (in_row - 1) * 0.5) * spacing + stagger, ((rows - 1) * 0.5 - r) * spacing))
	return out
