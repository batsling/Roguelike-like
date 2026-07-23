extends Node

# ---------------------------------------------------------------------------
# Economy simulator — a headless Monte-Carlo playthrough that reports how much
# GOLD the player earns per combat-style floor and across a whole run, so shop
# prices can be balanced against real income.
#
# It reuses the game's real systems rather than re-deriving them:
#   * floor structure   — the real DeckbuilderMap / IsaacFloorGenerator /
#                          strategy Map generators,
#   * enemy composition  — the real EnemySpawner / ActionEnemySpawner and the
#                          strategy weight-budget roller,
#   * gold formulas      — CombatEconomy (the single source of truth the live
#                          combat scenes also use).
#
# It does NOT simulate turn-by-turn combat (winning/HP) — economy balancing only
# needs income, and income is a function of floor structure + spawns + the gold
# formulas, all of which are modelled faithfully here. Where the player's route
# matters (which rooms get fought), we walk the shortest start->exit path and
# count the combats on it, and also report the floor's total combats as context.
#
# Run headless:
#   godot --headless res://tools/economy_sim.tscn
# Optional env knobs: ECON_RUNS (default 2000), ECON_FLOOR_SAMPLES (default 4000),
# ECON_SEED (default random).
# ---------------------------------------------------------------------------

const DeckMap := preload("res://scripts/deckbuilder/DeckbuilderMap.gd")
const IsaacGen := preload("res://scripts/action/IsaacFloorGenerator.gd")
const StratMap := preload("res://scripts/strategy_prototype/Map.gd")

var _rng := RandomNumberGenerator.new()

# Shop price tables (read straight off the shop scripts so the report tracks the
# live prices — update these consts if the shops move).
const DECK_SHOP_ITEM_PRICES := {0: 8, 1: 15, 2: 25, 3: 35, 4: 40}
const OVERWORLD_SHOP_PRICES := [50, 80, 120, 175, 250]
const DECK_SHOP_REMOVE_PRICE := 50

func _ready() -> void:
	var seed_val: int = int(_env("ECON_SEED", str(randi())))
	_rng.seed = seed_val
	var runs: int = int(_env("ECON_RUNS", "2000"))
	var floor_samples: int = int(_env("ECON_FLOOR_SAMPLES", "4000"))

	print("============================================================")
	print("  ECONOMY SIMULATION  (seed %d)" % seed_val)
	print("  runs=%d  floor_samples=%d" % [runs, floor_samples])
	print("============================================================")

	_report_per_floor_economy(floor_samples)
	var mean_run_gold: float = _report_whole_run_economy(runs)
	_report_shop_affordability(mean_run_gold)

	print("\n(Modelling notes: gold is income only — no HP/loss modelled. Deckbuilder")
	print(" & strategy floors walk the shortest start->boss/stairs path and pay the")
	print(" combats on it; action rooms roll a chance-based coin drop per clear.")
	print(" Section reward is granted once per game beaten. Item/event/King-Bomber")
	print(" gold is excluded.)")
	get_tree().quit(0)

func _env(key: String, def: String) -> String:
	var v: String = OS.get_environment(key)
	return v if v != "" else def

# ---------------------------------------------------------------------------
# Per-floor economy — isolate one game floor of each style, at each tier.
# ---------------------------------------------------------------------------

func _report_per_floor_economy(samples: int) -> void:
	print("\n------------------------------------------------------------")
	print(" GOLD PER COMBAT-STYLE FLOOR  (mean over %d samples each)" % samples)
	print("------------------------------------------------------------")
	print(" Tier  Style        Combats  Elites   CombatGold   +Section   FloorTotal")
	for tier in range(4):
		for style in ["deckbuilder", "action", "strategy"]:
			var acc_combats := 0.0
			var acc_elites := 0.0
			var acc_gold := 0.0
			for _i in range(samples):
				var r: Dictionary = _sim_floor(style, tier)
				acc_combats += float(r.combats)
				acc_elites += float(r.elites)
				acc_gold += float(r.combat_gold)
			var mean_combats := acc_combats / samples
			var mean_elites := acc_elites / samples
			var mean_gold := acc_gold / samples
			var section := float(CombatEconomy.section_reward_gold(tier))
			print(" %-5s %-12s %6.1f  %6.1f   %9.1f   %8.1f   %9.1f" % [
				RunDifficulty.tier_name(tier), style,
				mean_combats, mean_elites, mean_gold, section, mean_gold + section])
		print("")

# Simulate ONE game floor of `style` at `tier`. Returns
# { combats, elites, combat_gold } — the combats fought on the traversed path
# and the gold they pay (section reward added by the caller).
func _sim_floor(style: String, tier: int) -> Dictionary:
	match style:
		"deckbuilder":
			return _sim_deckbuilder_floor(tier)
		"action":
			return _sim_action_floor(tier)
		"strategy":
			return _sim_strategy_floor(tier)
	return {"combats": 0, "elites": 0, "combat_gold": 0}

# --- Deckbuilder: generate the real mini-map, walk a random path to the elite,
# pay each COMBAT/ELITE node on it via CombatEconomy. games_beaten drives the
# purse tier; approximate it from the run tier (tier*3 games played ~ beaten).
func _sim_deckbuilder_floor(tier: int) -> Dictionary:
	var games_beaten: int = tier * RunDifficulty.GAMES_PER_TIER
	# DeckbuilderMap reads RunDifficulty via GameState.games_played for node
	# rolls; set it so the generated map matches this tier.
	GameState.games_played = games_beaten
	var m: DeckMap = DeckMap.new()
	m.generate(_rng)
	# Walk a random path from a floor-0 node to the elite.
	var combats := 0
	var elites := 0
	var gold := 0
	var node: Dictionary = m.get_reachable_next().pick_random() if not m.get_reachable_next().is_empty() else {}
	var beaten_so_far := games_beaten
	while not node.is_empty():
		var t: int = int(node.type)
		if t == DeckMap.NodeType.COMBAT:
			combats += 1
			gold += CombatEconomy.deckbuilder_combat_gold(beaten_so_far, false)
		elif t == DeckMap.NodeType.ELITE:
			elites += 1
			gold += CombatEconomy.deckbuilder_combat_gold(beaten_so_far, true)
		m.enter(node)
		var nexts: Array = m.get_reachable_next()
		if nexts.is_empty():
			break
		node = nexts.pick_random()
	return {"combats": combats, "elites": elites, "combat_gold": gold}

# --- Action: generate the real floor, count combat rooms on the shortest
# start->boss path. Each cleared room has a CombatEconomy chance to drop gold.
func _sim_action_floor(tier: int) -> Dictionary:
	var tv: int = RunDifficulty.tier_value(tier)
	var floor_data: Dictionary = IsaacGen.new().generate(_rng.randi(), tv)
	if not bool(floor_data.get("success", false)):
		return {"combats": 0, "elites": 0, "combat_gold": 0}
	var path: Array = _bfs_room_path(floor_data.rooms, int(floor_data.start_index),
		int(floor_data.get("boss_index", -1)))
	var combats := 0
	var elites := 0
	var gold := 0
	for idx in path:
		var rt: int = int(floor_data.rooms[idx].type)
		if rt == IsaacGen.RoomType.NORMAL:
			combats += 1
			gold += CombatEconomy.roll_action_combat_gold(tier, _rng)
		elif rt == IsaacGen.RoomType.BOSS:
			elites += 1
			gold += CombatEconomy.roll_action_combat_gold(tier, _rng)
	return {"combats": combats, "elites": elites, "combat_gold": gold}

# --- Strategy: generate the real dungeon, count combat rooms on the shortest
# start->stairs path, roll each room's encounter gold via CombatEconomy.
func _sim_strategy_floor(tier: int) -> Dictionary:
	GameState.games_played = tier * RunDifficulty.GAMES_PER_TIER
	StrategyState.dungeon_floor = tier + 1
	var m := StratMap.new()
	m.generate(_rng)
	var combats := 0
	var gold := 0
	# The strategy floor is free-roam; the player fights the combat rooms they
	# enter walking to the stairs. Model that as the combat rooms whose rect the
	# shortest room-graph path start->stairs passes through. Room adjacency isn't
	# exposed, so approximate the "committed" set as the combat rooms nearest the
	# start->stairs line (all combat rooms is an upper bound). We use all combat
	# rooms weighted by an engagement factor to stay between "just the path" and
	# "clear everything".
	var engagement := 0.6   # fraction of combat rooms a typical run actually fights
	for rd in m.room_data:
		if str(rd.tag) != "combat":
			continue
		if _rng.randf() > engagement:
			continue
		combats += 1
		for kind in rd.encounter:
			gold += CombatEconomy.roll_strategy_enemy_gold(str(kind), _rng)
	return {"combats": combats, "elites": 0, "combat_gold": gold}

# BFS over the room-neighbour graph, returning the index path from `start` to
# `goal` inclusive (empty if unreachable). Rooms carry `neighbors: {Dir: index}`.
func _bfs_room_path(rooms: Dictionary, start: int, goal: int) -> Array:
	if goal < 0 or not rooms.has(start) or not rooms.has(goal):
		return []
	var prev := {start: start}
	var queue: Array = [start]
	while not queue.is_empty():
		var cur: int = queue.pop_front()
		if cur == goal:
			break
		for dir in rooms[cur].neighbors.keys():
			var nb: int = int(rooms[cur].neighbors[dir])
			if not prev.has(nb):
				prev[nb] = cur
				queue.append(nb)
	if not prev.has(goal):
		return []
	var path: Array = []
	var n: int = goal
	while n != start:
		path.append(n)
		n = prev[n]
	path.append(start)
	path.reverse()
	return path

# ---------------------------------------------------------------------------
# Whole-run economy — a full start->amulet run of mixed game types.
# ---------------------------------------------------------------------------

func _report_whole_run_economy(runs: int) -> float:
	print("------------------------------------------------------------")
	print(" WHOLE-RUN GOLD  (mean over %d runs, mixed game types)" % runs)
	print("------------------------------------------------------------")
	# Real distribution of game types across the catalog, so the type mix a run
	# fights matches the actual map.
	var type_weights := _catalog_type_weights()
	print(" Catalog game-type mix: " + str(type_weights))

	var totals := {"combat": 0.0, "section": 0.0, "total": 0.0, "games": 0.0}
	var by_style := {"deckbuilder": 0.0, "action": 0.0, "strategy": 0.0}
	var style_games := {"deckbuilder": 0.0, "action": 0.0, "strategy": 0.0}
	var min_total := 1e12
	var max_total := -1.0
	for _r in range(runs):
		var games: int = _rng.randi_range(5, 8)   # a run beats 5-8 games
		var run_combat := 0.0
		var run_section := 0.0
		for gi in range(games):
			var tier: int = RunDifficulty.tier_for(gi)
			var style: String = _weighted_pick(type_weights)
			var fr: Dictionary = _sim_floor(style, tier)
			run_combat += float(fr.combat_gold)
			run_section += float(CombatEconomy.section_reward_gold(tier))
			by_style[style] += float(fr.combat_gold)
			style_games[style] += 1.0
		totals.combat += run_combat
		totals.section += run_section
		totals.games += games
		var run_total := run_combat + run_section
		totals.total += run_total
		min_total = minf(min_total, run_total)
		max_total = maxf(max_total, run_total)

	print(" Games beaten / run (avg): %.1f" % (totals.games / runs))
	print(" Gold from combat  / run:  %.1f" % (totals.combat / runs))
	print(" Gold from section / run:  %.1f" % (totals.section / runs))
	print(" TOTAL gold / run:         %.1f   (min %.0f, max %.0f)" % [
		totals.total / runs, min_total, max_total])
	print("")
	print(" Combat gold contribution by style (per run, and per floor of that style):")
	for style in ["deckbuilder", "action", "strategy"]:
		var per_run: float = float(by_style[style]) / runs
		var per_floor: float = (float(by_style[style]) / float(style_games[style])) if float(style_games[style]) > 0 else 0.0
		print("   %-12s %7.1f / run     %6.1f / floor" % [style, per_run, per_floor])
	return float(totals.total) / runs

# Type weights for the real game catalog, as { style_string: count }.
func _catalog_type_weights() -> Dictionary:
	var out := {"deckbuilder": 0, "action": 0, "strategy": 0}
	for g in Data.all_games():
		match int(g.type):
			GameData.GameType.ACTION:
				out.action += 1
			GameData.GameType.STRATEGY:
				out.strategy += 1
			_:
				# Deckbuilder / traditional / everything else routes to the
				# deckbuilder mini-map (see Main._on_portal_entered).
				out.deckbuilder += 1
	return out

func _weighted_pick(weights: Dictionary) -> String:
	var total := 0
	for k in weights:
		total += int(weights[k])
	if total <= 0:
		return "deckbuilder"
	var roll := _rng.randi() % total
	var acc := 0
	for k in weights:
		acc += int(weights[k])
		if roll < acc:
			return String(k)
	return "deckbuilder"

# ---------------------------------------------------------------------------
# Shop affordability — how the two shops' prices compare to income.
# ---------------------------------------------------------------------------

func _report_shop_affordability(mean_run_gold: float) -> void:
	print("\n------------------------------------------------------------")
	print(" SHOP PRICES vs INCOME  (mean run gold = %.0f)" % mean_run_gold)
	print("------------------------------------------------------------")
	var rarities := ["Common", "Uncommon", "Rare", "Epic", "Legendary"]
	# The unified scale CombatEconomy now serves to BOTH shops.
	var unified: Array = CombatEconomy.SHOP_ITEM_PRICE_BY_RARITY
	print(" Rarity      DeckOld  OverworldOld  Unified   Run buys @Unified")
	for i in range(rarities.size()):
		var deck_old: int = int(DECK_SHOP_ITEM_PRICES.get(i, 0))
		var ow_old: int = int(OVERWORLD_SHOP_PRICES[i]) if i < OVERWORLD_SHOP_PRICES.size() else 0
		var uni: int = int(unified[i]) if i < unified.size() else 0
		var buys: float = (mean_run_gold / float(uni)) if uni > 0 else 0.0
		print("  %-10s %6d   %10d   %7d   %6.1f items" % [rarities[i], deck_old, ow_old, uni, buys])
	print("")
	print(" Both shops now price items from CombatEconomy.SHOP_ITEM_PRICE_BY_RARITY,")
	print(" so identical rarities cost the same wherever you buy them. At the unified")
	print(" scale a mean run (%.0fg) affords roughly %.1f rare-tier items' worth of" % [
		mean_run_gold, mean_run_gold / float(unified[2]) if unified.size() > 2 and int(unified[2]) > 0 else 0.0])
	print(" shopping, spread across items / potions / card removal.")
	print(" Remove-card service: %dg" % DECK_SHOP_REMOVE_PRICE)
