extends Node
## Campaign state that survives scene changes: the sea chart, the warband
## roster, gold, and the island currently being fought over.

signal changed

const COLUMNS := 6                  # islands to cross, the last is the finale
const ISLAND_REWARD_PER_HOUSE := 10

const KINDS := {
	"militia": {"title": "Freed Thralls", "size": 7, "ability": ""},
	"priest": {"title": "Rune-priests", "size": 4, "ability": "Firestorm"},
	"shield": {"title": "Shieldwall", "size": 9, "ability": "Brace"},
	"sword": {"title": "Swordsmen", "size": 8, "ability": "Charge"},
	"archer": {"title": "Crossbows", "size": 8, "ability": "Volley"},
}
const COST_UNLOCK := 25
const COST_TRAIN := [0, 30, 50]      # cost to reach level 2, 3
const COST_RECRUIT := 45
const COST_TIMBER := 15
const COST_REROLL := 20
const COST_VETERANS := 70
var veteran_recruits := false
const MAX_SQUADS := 4
const BASE_TIMBER := 10.0
const BOAT_BOUNTY := 8
var timber_bonus := 0.0
var boons: Array = []              # chosen boon ids
var boon_choice: Array = []        # three ids on offer after a won island

const TRAITS := {
	"timberland": {"name": "Timberland", "desc": "Thick woods: +8 timber for palisades."},
	"prosperous": {"name": "Prosperous", "desc": "A rich village: every saved house pays half again."},
	"haunted": {"name": "Haunted Shore", "desc": "The Drowned join every wave, and rise twice."},
	"ruins": {"name": "Old Ruins", "desc": "Stone walls of an older fort still stand."},
	"veterans": {"name": "Veteran Raiders", "desc": "Hardened foes: tougher raiders, a richer reward."},
	"fair_winds": {"name": "Fair Winds", "desc": "Slow seas: longboats take longer to arrive."},
}

const BOONS := {
	"shield_bash": {"name": "Shield Bash", "desc": "When the Shieldwall blocks, the attacker is hurled back and staggered.", "glyph": "shield"},
	"fire_bolts": {"name": "Fire Bolts", "desc": "Crossbows can set boats and walls alight from range.", "glyph": "flame"},
	"drillmaster": {"name": "Last Stand", "desc": "A squad down to half strength fights 50% harder and can't be knocked back.", "glyph": "star"},
	"swift_march": {"name": "Forced March", "desc": "For four seconds after any order, a squad sprints at double speed.", "glyph": "boot"},
	"second_wind": {"name": "Second Wind", "desc": "Refitting at a house is twice as fast and ready again sooner.", "glyph": "house"},
	"stout_timber": {"name": "Stout Timber", "desc": "+8 timber on every island, and palisades are half again as tough.", "glyph": "wall"},
	"giant_slayer": {"name": "Giant-slayer", "desc": "+60% damage against chieftains, champions and the Jarl.", "glyph": "axe"},
	"war_horn": {"name": "Bloodied Blades", "desc": "Every kill a squad makes cuts 2 seconds off its ability cooldown.", "glyph": "horn"},
	"plunder": {"name": "Plunder", "desc": "Burnt longboats pay double, and every raider slain is worth a coin.", "glyph": "coin"},
	"hallowed": {"name": "Hallowed Blades", "desc": "The Drowned you cut down stay down.", "glyph": "skull"},
	"iron_brace": {"name": "Iron Brace", "desc": "Brace holds for 10 seconds instead of 6.", "glyph": "shield"},
	"eagle_perch": {"name": "Eagle's Perch", "desc": "The high-ground bonus is doubled.", "glyph": "eye"},
	"militia_drill": {"name": "Village Drill", "desc": "Called militia are twice as many and tougher.", "glyph": "fork"},
	"shield_and_spark": {"name": "Kindling Wall", "desc": "Raiders who hack at your palisades catch fire.", "glyph": "flame"},
	"hold_the_line": {"name": "Hold the Line", "desc": "A squad that hasn't moved for 3 seconds takes 30% less damage.", "glyph": "shield"},
}


func has_boon(id: String) -> bool:
	return active and boons.has(id)


func _offer_boons() -> void:
	var pool := BOONS.keys().filter(func(k): return not boons.has(k))
	var picks := []
	for i in mini(3, pool.size()):
		var k: String = pool[rng.randi() % pool.size()]
		pool.erase(k)
		picks.append(k)
	boon_choice = picks


func choose_boon(id: String) -> void:
	if not boon_choice.has(id):
		return
	boons.append(id)
	boon_choice = []
	if id == "stout_timber":
		timber_bonus += 8.0
	changed.emit()
	save_game()


func timber() -> float:
	return BASE_TIMBER + timber_bonus

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
var totals := {"islands": 0, "slain": 0, "lost": 0, "houses": 0}


func new_campaign(p_seed := -1) -> void:
	active = true
	rng.seed = p_seed if p_seed >= 0 else int(Time.get_unix_time_from_system())
	gold = 20
	veteran_recruits = false
	roster.clear()
	_next_id = 0
	_add_squad("shield")
	_add_squad("sword")
	_add_squad("archer")
	_build_chart()
	column = -1
	node_i = 0
	current = {}
	last_result = {}
	totals = {"islands": 0, "slain": 0, "lost": 0, "houses": 0}
	veteran_recruits = false
	boons = []
	boon_choice = []
	timber_bonus = 0.0
	changed.emit()
	save_game()


func _add_squad(kind: String) -> Dictionary:
	var count := 0
	for r in roster:
		if r["kind"] == kind:
			count += 1
	var title: String = KINDS[kind]["title"]
	var start_level := 2 if (veteran_recruits and kind != "militia") else 1
	var names := ["", " II", " III", " IV"]
	var sq := {"id": _next_id, "name": title + names[mini(count, 3)], "kind": kind, "level": start_level, "ability": false, "alive": true}
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
			# Gentle ramp: the first landfall is always the easiest.
			var difficulty := 0 if c == 0 else c - 1 + (1 if rng.randf() < 0.4 else 0)
			var node := {
				"seed": rng.randi_range(1, 99999),
				"difficulty": difficulty,
				"y": (i + 0.5) / count + rng.randf_range(-0.08, 0.08),
				"links": [],
				"visited": false,
				"finale": c == COLUMNS - 1,
				"name": _island_name(),
				"type": "assault" if (c >= 1 and c < COLUMNS - 1 and rng.randf() < 0.32) else "defend",
				"trait": "" if (c == COLUMNS - 1 or rng.randf() < 0.35) else TRAITS.keys()[rng.randi() % TRAITS.size()],
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
		[["raiders", "raiders"], ["raiders", "berserkers"], ["torchbearers", "berserkers", "raiders"]],
		[["raiders", "raiders"], ["torchbearers", "draugr", "berserkers"], ["raiders", "draugr", "bowmen", "berserkers"]],
		[["raiders", "draugr", "berserkers"], ["draugr", "bowmen", "torchbearers"], ["chieftain", "raiders", "berserkers", "draugr"]],
		[["draugr", "raiders", "berserkers"], ["draugr", "draugr", "bowmen", "torchbearers"], ["berserkers", "raiders", "bowmen"], ["chieftain", "draugr", "bowmen", "berserkers"]],
		[["raiders", "berserkers"], ["draugr", "draugr", "bowmen"], ["chieftain", "raiders", "bowmen"], ["jarl", "draugr", "bowmen"]],
	]
	var plan: Array = plans[5] if node.get("finale", false) else plans[mini(d, 4)]
	var delays := [8.0, 38.0, 42.0, 45.0]
	var waves := []
	for i in plan.size():
		waves.append({"delay": delays[i], "boats": plan[i]})
	return waves


# Results ---------------------------------------------------------------------

## Called when a battle ends. `survivors` maps roster id -> living unit count.
func finish_island(won: bool, saved: int, total: int, survivors: Dictionary, slain := 0, lost := 0, boats := 0, haste := 0) -> void:
	gold += haste
	gold += boats * BOAT_BOUNTY
	totals["islands"] += 1 if won else 0
	totals["slain"] += slain
	totals["lost"] += lost
	totals["houses"] += saved if won else 0
	if has_boon("plunder"):
		gold += boats * BOAT_BOUNTY + slain
	var per_house := float(ISLAND_REWARD_PER_HOUSE)
	match current.get("trait", ""):
		"prosperous":
			per_house *= 1.5
		"veterans":
			per_house *= 1.3
	var earned := int(saved * per_house) if won else 0
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
	if won and not last_result["finale"]:
		_offer_boons()
	changed.emit()
	if is_over():
		delete_save()
	else:
		save_game()


func is_over() -> bool:
	return living_squads().is_empty() or (last_result.get("won", false) and last_result.get("finale", false))


# Camp purchases -------------------------------------------------------------

func can_unlock(r: Dictionary) -> bool:
	return r["alive"] and not r["ability"] and KINDS[r["kind"]]["ability"] != "" and gold >= COST_UNLOCK


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
		"current": current, "last_result": last_result, "next_id": _next_id, "rng_state": rng.state, "totals": totals,
		"boons": boons, "boon_choice": boon_choice, "timber_bonus": timber_bonus, "veterans": veteran_recruits}
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
	totals = data.get("totals", totals)
	boons = data.get("boons", [])
	boon_choice = data.get("boon_choice", [])
	timber_bonus = data.get("timber_bonus", 0.0)
	veteran_recruits = data.get("veterans", false)
	# `current` must alias the chart entry so marking it visited sticks.
	current = chart[column][node_i] if column >= 0 else {}
	active = true
	changed.emit()
	return true


func delete_save() -> void:
	if has_save():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


## Garrison and reinforcement plan for a raider-camp assault.
func assault_plan(node: Dictionary) -> Dictionary:
	var d: int = node["difficulty"]
	var garrisons := [["raiders", "raiders"], ["raiders", "draugr", "raiders"], ["raiders", "berserkers", "draugr"],
		["chieftain", "draugr", "raiders", "berserkers"], ["chieftain", "draugr", "berserkers", "draugr"]]
	var plan := {"garrison": garrisons[mini(d, 4)], "towers": 1 + d / 2, "longhouses": 2 + mini(d, 2), "pens": 1 + int(d >= 2)}
	plan["waves"] = [] if d < 2 else [{"delay": 75.0, "boats": ["raiders"] if d < 4 else ["raiders", "berserkers"]}]
	return plan


func finish_assault(won: bool, burned: int, total: int, freed: int, survivors: Dictionary, slain := 0, lost := 0) -> void:
	var earned := burned * 18 + (20 if won else 0)
	gold += earned
	totals["islands"] += 1 if won else 0
	totals["slain"] += slain
	totals["lost"] += lost
	var fallen := []
	for r in roster:
		if r["alive"] and survivors.get(r["id"], 0) <= 0:
			r["alive"] = false
			fallen.append(r["name"])
	# Freed captives become a new squad of thralls.
	var joined := ""
	if freed > 0 and living_squads().size() < MAX_SQUADS + 1:
		var sq := _add_squad("militia")
		joined = sq["name"]
	last_result = {"won": won, "saved": burned, "total": total, "earned": earned, "fallen": fallen,
		"finale": false, "assault": true, "joined": joined}
	current = {}
	if won:
		_offer_boons()
	changed.emit()
	if is_over():
		delete_save()
	else:
		save_game()


func buy_timber() -> void:
	if gold >= COST_TIMBER:
		gold -= COST_TIMBER
		timber_bonus += 5.0
		changed.emit()
		save_game()


func buy_veterans() -> void:
	if not veteran_recruits and gold >= COST_VETERANS:
		gold -= COST_VETERANS
		veteran_recruits = true
		changed.emit()
		save_game()


func reroll_boons() -> bool:
	if gold < COST_REROLL or boon_choice.is_empty():
		return false
	gold -= COST_REROLL
	_offer_boons()
	changed.emit()
	save_game()
	return true


## Enemies harden as the voyage goes on.
func enemy_toughness() -> float:
	return 1.0 + 0.12 * maxi(column, 0) if active else 1.0


## Trait of the island being fought (campaign), or one rolled from the seed.
static func trait_for(node: Dictionary, seed_v: int) -> String:
	if Capture.has("trait"):
		return Capture.arg("trait")
	if not node.is_empty():
		return node.get("trait", "")
	var r := RandomNumberGenerator.new()
	r.seed = seed_v * 29 + 5
	if r.randf() < 0.35:
		return ""
	return TRAITS.keys()[r.randi() % TRAITS.size()]
