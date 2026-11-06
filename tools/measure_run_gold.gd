extends SceneTree
## MEASURE WHAT A RUN EARNS IN GOLD, by playing whole runs through the real page.
##
##   godot --headless -s tools/measure_run_gold.gd -- [runs=200] [tick=1.0,0.75,0.5] [seed=1]
##
## Each run takes a random card on the start panel (so the run lengths come out in
## the proportions the panel deals them), then walks the SHORTEST ROAD to the
## Amulet, reporting every game beaten first try. At each report it ticks each body
## on the board with probability `tick` — the share of goals the player answers —
## so a body left unticked follows the run the way it does in play and may be
## ticked at a later game. Nothing is bombed, no run is lost, and the run stops at
## the Amulet's report.
##
## WHAT IT COUNTS is every `gold_gained` the run fires (GameState.change_gold's own
## hook), split into what the bodies and bosses paid (`GameLoop2._defeat`, read off
## the report's `gold`) and everything else, plus the opening purse.
##
## WHAT IT LEAVES OUT, because the harness makes no choices a player would:
## events are closed without pressing anything (Jungle Maze's +2/+6 is the only
## event that pays gold), chests and drops are left on the floor (Old Coin and the
## other gold relics never reach the pack), and no shop is opened (so nothing is
## spent, and the shop bar's fill is reported as kills). Starting gear, shopkeepers
## and locations are ON, as in a real run — this does not use the suite's pre-run
## hook. docs/games-first-redesign.md §14.1 carries the result.

# Autoloads are not in scope when a `-s` script compiles, and neither is anything
# that names them (Overworld2.gd), so both are looked up once the tree is running.
var SCENE: PackedScene
var GameLoop2: Node
var GameState: Node
var TriggerBus: Node
var ObjectSystem: Node

var _gold_this_run: int = 0


func _initialize() -> void:
	_main.call_deferred()


func _arg(name: String, fallback: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with(name + "="):
			return a.substr(name.length() + 1)
	return fallback


func _main() -> void:
	GameLoop2 = root.get_node("GameLoop2")
	GameState = root.get_node("GameState")
	TriggerBus = root.get_node("TriggerBus")
	ObjectSystem = root.get_node("ObjectSystem")
	SCENE = load("res://scenes/redesign2/Overworld2.tscn")
	var runs: int = int(_arg("runs", "200"))
	var ticks: Array = []
	for t in _arg("tick", "1.0,0.75,0.5").split(","):
		ticks.append(float(t))
	var rng := RandomNumberGenerator.new()
	rng.seed = int(_arg("seed", "1"))
	TriggerBus.gold_gained.connect(func(p: Dictionary) -> void:
		_gold_this_run += int(p.get("amount", 0))
		if OS.get_environment("MEASURE_TRACE") != "":
			var where: Array = []
			for f in get_stack().slice(1, 7):
				where.append("%s:%d" % [String(f.source).get_file(), int(f.line)])
			print("  +%d gold  %s" % [int(p.get("amount", 0)), " < ".join(where)]))
	print("tick\truns\tgames\tstart\tbodies_gold\tother_gold\ttotal\tkills\tbosses\tleft_on_board\tdied")
	for tick in ticks:
		var rows: Array = []
		for i in range(runs):
			var r: Dictionary = await _one_run(rng, tick)
			if not r.is_empty():
				rows.append(r)
				print("RUN\t%.2f\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d" % [tick, r.games, r.start,
					r.body_gold, r.other_gold, r.start + r.body_gold + r.other_gold,
					r.kills, r.bosses, r.left, int(r.died)])
		_summarise(tick, rows)
	quit()


func _one_run(rng: RandomNumberGenerator, tick: float) -> Dictionary:
	var ui = SCENE.instantiate()
	root.add_child(ui)
	await process_frame
	var r := {"dashes": 0, "scrambles": 0, "path_len": 0, "games": 0, "start": 0, "body_gold": 0, "other_gold": 0, "kills": 0,
		"bosses": 0, "left": 0, "died": false}
	var n_opts: int = ui._start_options.size()
	if n_opts == 0:
		ui.queue_free()
		await process_frame
		return {}
	var pick: int = rng.randi_range(0, n_opts - 1)
	r.path_len = int(ui._start_options[pick].get("path_len", 0))
	ui.choose_start(pick)
	r.start = GameState.gold
	_gold_this_run = 0
	var kill_counter := {"n": 0, "b": 0}
	var on_kill := func(enemy, _a = null, _b = null, _c = null) -> void:
		kill_counter.n += 1
		if enemy != null and enemy.has_method("is_boss") and enemy.is_boss():
			kill_counter.b += 1
	GameLoop2.enemy_defeated.connect(on_kill)
	var guard: int = 0
	while guard < 60:   # 30 games: a run still walking then is reported as capped
		guard += 1
		if ui._phase == ui.Phase.PLAYING:
			var ticked: Array = []
			for entry in GameLoop2.stack:
				if rng.randf() < tick:
					ticked.append(int(entry.get("instance", 0)))
			var before: int = _gold_this_run
			ui.report(true, ticked)
			var res: Dictionary = GameLoop2.last_result if GameLoop2.last_result is Dictionary else {}
			var paid: int = int(res.get("gold", 0))
			r.body_gold += paid
			r.other_gold += (_gold_this_run - before) - paid
			r.games += 1
			if GameLoop2.run_over or ui._phase == ui.Phase.OVER:
				r.died = not GameLoop2.won
				break
			ui._end_resolve()
			ui._board.clear_fx()
			_leave(ui)
		elif ui._phase == ui.Phase.SELECT:
			if ui._choices.is_empty():
				break
			var here: int = ui.steps_to_amulet(GameState.current_game_id)
			var best: int = _best_card(ui)
			# STUCK — no card gets closer. Spend what a player would: a Dash names
			# any connected game, a Scramble re-deals the hand. Neither is bought;
			# they are whatever the run has handed over (a repeat visit pays a Dash).
			if _card_hops(ui, best) >= here and GameState.dash_charges > 0:
				ui.dash()
				best = _best_card(ui)
				r.dashes += 1
			elif _card_hops(ui, best) >= here and GameState.scramble > 0 and ui.scramble():
				best = _best_card(ui)
				r.scrambles += 1
			if OS.get_environment("MEASURE_DEBUG") != "":
				var ds: Array = []
				for c in ui._choices:
					ds.append(ui.steps_to_amulet(c.get("game").id) if c.get("game") != null else -9)
				print("  at %s hops=%d offered=%s" % [GameState.current_game_id, here, ds])
			ui.pick(best)
			if ui._phase == ui.Phase.SELECT:
				break   # the pick raised something the harness does not answer
		else:
			break
	r.kills = kill_counter.n
	r.bosses = kill_counter.b
	r.left = GameLoop2.stack.size()
	GameLoop2.enemy_defeated.disconnect(on_kill)
	ui.queue_free()
	await process_frame
	return r


# The card a player walking to the Amulet takes: the closest, and among equals
# one not played yet. A revisit is not penalised beyond that: arriving again
# re-deals the hand (Overworld2._offer_seed).
func _best_card(ui) -> int:
	var best: int = 0
	var best_d: int = 1 << 30
	for i in range(ui._choices.size()):
		var d: int = _card_hops(ui, i)
		if d < 0:
			continue
		var g = ui._choices[i].get("game")
		d = d * 2 + (1 if GameState.has_played_game(g.id) else 0)
		if d < best_d:
			best_d = d
			best = i
	return best

func _card_hops(ui, i: int) -> int:
	if i < 0 or i >= ui._choices.size() or ui._choices[i].get("game") == null:
		return -1
	return ui.steps_to_amulet(ui._choices[i].get("game").id)


func _leave(ui) -> void:
	if ui._post_screen != null and is_instance_valid(ui._post_screen):
		ui._post_screen.dismiss()
	ui._post_screen = null
	ui._post_snapshot = {}
	ui._drop_queue.clear()
	if ui._drop_modal != null and is_instance_valid(ui._drop_modal):
		ui._drop_modal.queue_free()
		ui._drop_modal = null
	if ui._event_modal != null and is_instance_valid(ui._event_modal):
		ui._event_modal._close()
	ui._event_modal = null
	ui._pending_event = null
	ui._pending_event_node = &""
	ObjectSystem.clear()


func _summarise(tick: float, rows: Array) -> void:
	if rows.is_empty():
		print("tick %.2f: no runs completed" % tick)
		return
	var keys := ["dashes", "scrambles", "path_len", "games", "start", "body_gold", "other_gold", "kills", "bosses", "left"]
	var totals: Array = []
	for row in rows:
		totals.append(int(row.start) + int(row.body_gold) + int(row.other_gold))
	totals.sort()
	var line := "SUMMARY tick=%.2f runs=%d" % [tick, rows.size()]
	for k in keys:
		var s: float = 0.0
		for row in rows:
			s += float(row[k])
		line += " %s=%.2f" % [k, s / rows.size()]
	var games_sum: float = 0.0
	var gold_sum: float = 0.0
	for row in rows:
		games_sum += float(row.games)
		gold_sum += float(row.body_gold) + float(row.other_gold)
	line += " earned_per_game=%.2f" % (gold_sum / games_sum)
	var died: int = 0
	for row in rows:
		died += int(row.died)
	line += " total_mean=%.2f p10=%d median=%d p90=%d died=%d" % [
		float(totals.reduce(func(a, b): return a + b, 0)) / rows.size(),
		totals[int(rows.size() * 0.1)], totals[rows.size() / 2],
		totals[mini(rows.size() - 1, int(rows.size() * 0.9))], died]
	# By run length, so the doc can quote the short and the long run.
	var by_len := {}
	for row in rows:
		var g: int = int(row.games)
		if not by_len.has(g):
			by_len[g] = []
		by_len[g].append(int(row.start) + int(row.body_gold) + int(row.other_gold))
	var lens: Array = by_len.keys()
	lens.sort()
	for g in lens:
		var arr: Array = by_len[g]
		line += "\n    %d games: n=%d mean=%.1f" % [g, arr.size(),
			float(arr.reduce(func(a, b): return a + b, 0)) / arr.size()]
	var by_path := {}
	for row in rows:
		var k: int = int(row.path_len)
		if not by_path.has(k):
			by_path[k] = []
		by_path[k].append(row)
	var paths: Array = by_path.keys()
	paths.sort()
	for k in paths:
		var arr: Array = by_path[k]
		var g: Array = []
		var t: Array = []
		for row in arr:
			g.append(int(row.games))
			t.append(int(row.start) + int(row.body_gold) + int(row.other_gold))
		g.sort()
		t.sort()
		line += "\n    panel %d hops: n=%d games median=%d gold median=%d (p10 %d, p90 %d)" % [
			k, arr.size(), g[arr.size() / 2], t[arr.size() / 2],
			t[int(arr.size() * 0.1)], t[mini(arr.size() - 1, int(arr.size() * 0.9))]]
	print(line)
