extends SceneTree
## Round-trips a campaign through save/load and checks the state survives.
func _initialize() -> void:
	var c = root.get_node("Campaign")
	c.new_campaign(3)
	c.sail_to(0)
	c.finish_island(true, 6, 7, {0: 5, 1: 0})
	c.train(c.roster[0])
	var before := [c.gold, c.column, c.node_i, c.roster.size(), c.roster[0]["level"], c.roster[1]["alive"], c.chart[0][0]["name"]]
	c.save_game()
	c.active = false
	c.roster = []
	c.gold = 0
	var ok: bool = c.load_game()
	var after := [c.gold, c.column, c.node_i, c.roster.size(), c.roster[0]["level"], c.roster[1]["alive"], c.chart[0][0]["name"]]
	print("load ok=", ok, " before=", before, " after=", after, " MATCH=", before == after)
	c.delete_save()
	print("deleted=", not c.has_save())
	quit()
