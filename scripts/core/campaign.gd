extends Node
## Campaign state that survives scene changes: the sea chart, the warband
## roster, gold, and the island currently being fought over.

signal changed

const COLUMNS := 6                  # islands to cross, the last is the finale
const ISLAND_REWARD_PER_HOUSE := 10

const KINDS := {
	"shield": {"title": "Shieldwall", "size": 9, "ability": "Brace"},
	"sword": {"title": "Swordsmen", "size": 8, "ability": "Charge"},
	"archer": {"title": "Crossbows", "size": 8, "ability": "Volley"},
}
const COST_UNLOCK := 25
const COST_TRAIN := [0, 30, 50]      # cost to reach level 2, 3
const COST_RECRUIT := 45
const MAX_SQUADS := 4

var active := false
var gold := 0
var roster: Array = []              # {id, name, kind, level, ability, alive}
var chart: Array = []               # columns of island nodes
var column := -1                    # column of the island last fought (-1 = harbour)
var node_i := 0
var current: Dictionary = {}        # island being fought
var rng := RandomNumberGenerator.new()
var _next_id := 0
var last_result := {}


func new_campaign(p_seed := -1) -> void:
	active = true
	rng.seed = p_seed if p_seed >= 0 else int(Time.get_unix_time_from_system())
	gold = 20
	roster.clear()
	_next_id = 0
	_add_squad("shield")
	_add_squad("archer")
	_build_chart()
	column = -1
	node_i = 0
	current = {}
	last_result = {}
	changed.emit()
	save_game()


func _add_squad(kind: String) -> Dictionary:
	var count := 0
	for r in roster:
		if r["kind"] == kind:
			count += 1
	var title: String = KINDS[kind]["title"]
	var names := ["", " II", " III", " IV"]
	var sq := {"id": _next_id, "name": title + names[mini(count, 3)], "kind": kind, "level": 1, "ability": false, "alive": true}
	_next_id += 1
	roster.append(sq)
	return sq


func living_squads() -> Array:
	return roster.filter(func(r): return r["alive"])


# Sea chart -------------------------------------------------------------------

func _build_chart() -> void:
	chart.clear()
	_used_names.clear()
	for c in COLUMNS:
		var col := []
		var count := 1 if c == COLUMNS - 1 else rng.randi_range(2, 3)
		for i in count:
			var difficulty := c + (1 if rng.randf() < 0.35 else 0)
			var node := {
				"seed": rng.randi_range(1, 99999),
				"difficulty": difficulty,
				"y": (i + 0.5) / count + rng.randf_range(-0.08, 0.08),
				"links": [],
				"visited": false,
				"finale": c == COLUMNS - 1,
				"name": _island_name(),
			}
			col.append(node)
		chart.append(col)
	# Each island links to one or two islands in the next column.
	for c in COLUMNS - 1:
		var here: Array = chart[c]
		var there: Array = chart[c + 1]
		for i in here.size():
			var nearest := 0
			for j in there.size():
				if absf(there[j]["y"] - here[i]["y"]) < absf(there[nearest]["y"] - here[i]["y"]):
					nearest = j
			here[i]["links"].append(nearest)
			if there.size() > 1 and rng.randf() < 0.6:
				var other := (nearest + (1 if rng.randf() < 0.5 else -1) + there.size()) % there.size()
				if not here[i]["links"].has(other):
					here[i]["links"].append(other)
		# Every island in the next column must be reachable.
		for j in there.size():
			var linked := false
			for i in here.size():
				if here[i]["links"].has(j):
					linked = true
			if not linked:
				here[rng.randi() % here.size()]["links"].append(j)


var _used_names := {}


func _island_name() -> String:
	var a := ["Gull", "Raven", "Thorn", "Mist", "Salt", "Ember", "Ash", "Holm", "Kettle", "Wren", "Stag", "Grey", "Elder", "Cold"]
	var b := ["holm", "ey", " Rock", " Isle", "wick", "stead", " Skerry", "ness", " Haven", "by"]
	for _try in 50:
		var n: String = a[rng.randi() % a.size()] + b[rng.randi() % b.size()]
		if not _used_names.has(n):
			_used_names[n] = true
			return n
	return "Nameless Isle"


## Islands the player may sail to next.
func reachable() -> Array:
	if column < 0:
		var all := []
		for i in chart[0].size():
			all.append(i)
		return all
	return chart[column][node_i]["links"]


func sail_to(i: int) -> void:
	column += 1
	node_i = i
	current = chart[column][node_i]
	current["visited"] = true
	changed.emit()
	save_game()


## Wave plan for an island of the given difficulty.
func waves_for(node: Dictionary) -> Array:
	var d: int = node["difficulty"]
	var plans := [
		[["raiders"], ["raiders", "raiders"]],
		[["raiders"], ["raiders", "raiders"], ["raiders", "berserkers"]],
		[["raiders", "raiders"], ["raiders", "draugr"], ["raiders", "draugr", "bowmen"]],
		[["raiders", "draugr"], ["draugr", "bowmen", "raiders"], ["chieftain", "raiders", "berserkers"]],
		[["draugr", "raiders"], ["draugr", "draugr", "bowmen"], ["berserkers", "raiders", "bowmen"], ["chieftain", "draugr", "bowmen"]],
		[["raiders", "berserkers"], ["draugr", "draugr", "bowmen"], ["chieftain", "raiders", "draugr"], ["chieftain", "berserkers", "draugr", "bowmen"]],
	]
	var plan: Array = plans[5] if node.get("finale", false) else plans[mini(d, 4)]
	var delays := [8.0, 38.0, 42.0, 45.0]
	var waves := []
	for i in plan.size():
		waves.append({"delay": delays[i], "boats": plan[i]})
	return waves


# Results ---------------------------------------------------------------------

## Called when a battle ends. `survivors` maps roster id -> living unit count.
func finish_island(won: bool, saved: int, total: int, survivors: Dictionary) -> void:
	var earned := saved * ISLAND_REWARD_PER_HOUSE if won else 0
	if won and saved == total:
		earned += 15
	gold += earned
	var fallen := []
	for r in roster:
		if not r["alive"]:
			continue
		if survivors.get(r["id"], 0) <= 0:
			r["alive"] = false
			fallen.append(r["name"])
	last_result = {"won": won, "saved": saved, "total": total, "earned": earned, "fallen": fallen,
		"finale": current.get("finale", false)}
	# Back at camp: the island is done, so a reload resumes on the chart.
	current = {}
	changed.emit()
	if is_over():
		delete_save()
	else:
		save_game()


func is_over() -> bool:
	return living_squads().is_empty() or (last_result.get("won", false) and last_result.get("finale", false))


# Camp purchases -------------------------------------------------------------

func can_unlock(r: Dictionary) -> bool:
	return r["alive"] and not r["ability"] and gold >= COST_UNLOCK


func unlock(r: Dictionary) -> void:
	if can_unlock(r):
		gold -= COST_UNLOCK
		r["ability"] = true
		changed.emit()
		save_game()


func train_cost(r: Dictionary) -> int:
	return COST_TRAIN[r["level"]] if r["level"] < 3 else -1


func can_train(r: Dictionary) -> bool:
	var c := train_cost(r)
	return r["alive"] and c > 0 and gold >= c


func train(r: Dictionary) -> void:
	if can_train(r):
		gold -= train_cost(r)
		r["level"] += 1
		changed.emit()
		save_game()


func can_recruit() -> bool:
	return living_squads().size() < MAX_SQUADS and gold >= COST_RECRUIT


func recruit(kind: String) -> void:
	if can_recruit():
		gold -= COST_RECRUIT
		_add_squad(kind)
		changed.emit()
		save_game()


# Persistence ---------------------------------------------------------------

const SAVE_PATH := "user://campaign.save"


func save_game() -> void:
	if not active or Capture.has("capture"):
		return
	var data := {"gold": gold, "roster": roster, "chart": chart, "column": column, "node_i": node_i,
		"current": current, "last_result": last_result, "next_id": _next_id, "rng_state": rng.state}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_var(data)


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func load_game() -> bool:
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return false
	var data = f.get_var()
	if typeof(data) != TYPE_DICTIONARY:
		return false
	gold = data["gold"]
	roster = data["roster"]
	chart = data["chart"]
	column = data["column"]
	node_i = data["node_i"]
	last_result = data["last_result"]
	_next_id = data["next_id"]
	rng.state = data["rng_state"]
	# `current` must alias the chart entry so marking it visited sticks.
	current = chart[column][node_i] if column >= 0 else {}
	active = true
	changed.emit()
	return true


func delete_save() -> void:
	if has_save():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
