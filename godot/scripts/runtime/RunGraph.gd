class_name RunGraph
extends RefCounted

# Pure-data helpers for picking a start/amulet pair and presenting
# choose-your-start options. Ports js/character-start.js + the
# `getGameConnections` helper from the HTML build into GDScript so the
# Godot main menu can drive the same start-game progression.

# Path length tuning. The HTML build runs on a much larger game catalog
# and uses 5..8. Godot's authored data set is currently ~15 games with a
# very sparse influence graph (diameter ~2-3), so we start at 2 and
# accept up to 8. When the catalog grows we can tighten the lower bound
# to match the HTML feel.
const MIN_PATH_LENGTH := 2
const MAX_PATH_LENGTH := 8
const EARLY_LAYERS_FOR_SCORE := 3
const NUM_START_OPTIONS := 3
# Minimum outgoing connections a game needs to qualify as a "start".
# Falls back to any-game on sparse graphs (see pick_amulet_and_starts).
const MIN_START_CONNECTIONS := 3

# Game-type ordering used to pick "one start per type" for the
# choose-your-start panel. Matches the JS GAME_TYPES list.
const TYPE_ORDER: Array = [
	GameData.GameType.ACTION,
	GameData.GameType.TRADITIONAL,
	GameData.GameType.STRATEGY,
	GameData.GameType.DECKBUILDER,
]

# ---------------------------------------------------------------------------
# Graph access — `games_influenced` is directed in the .tres files but
# the HTML build treats it as undirected (you can travel back along
# either direction). Mirror that here.
# ---------------------------------------------------------------------------

static func neighbors(game_id: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	var src: GameData = Data.get_game(game_id)
	if src != null:
		for gid in src.games_influenced:
			if Data.get_game(gid) != null and not out.has(gid):
				out.append(gid)
	for g in Data.all_games():
		if g.id == game_id:
			continue
		for influenced_id in g.games_influenced:
			if influenced_id == game_id and not out.has(g.id):
				out.append(g.id)
	return out

# Shortest-hop distance from start_id to every reachable game.
static func bfs_distances(start_id: StringName) -> Dictionary:
	var dist: Dictionary = {}
	dist[start_id] = 0
	var queue: Array[StringName] = [start_id]
	var qi := 0
	while qi < queue.size():
		var cur: StringName = queue[qi]
		qi += 1
		var cur_d: int = dist[cur]
		for nb in neighbors(cur):
			if not dist.has(nb):
				dist[nb] = cur_d + 1
				queue.append(nb)
	return dist

# Score a start->amulet pair by how many of the first `early_layers`
# depths have 2+ nodes lying on a shortest-path DAG between them.
# Higher = more meaningful branching choice in the early run.
static func dag_branch_score_early(d_from_start: Dictionary, amulet_id: StringName,
		early_layers: int = EARLY_LAYERS_FOR_SCORE,
		d_to_amulet_cache: Dictionary = {}) -> int:
	if not d_from_start.has(amulet_id):
		return 0
	var amulet_dist: int = d_from_start[amulet_id]
	var d_to_amulet: Dictionary = d_to_amulet_cache if not d_to_amulet_cache.is_empty() else bfs_distances(amulet_id)
	var count_at_depth: Dictionary = {}
	for name in d_from_start:
		var from_d: int = d_from_start[name]
		if from_d == 0 or from_d >= amulet_dist or from_d > early_layers:
			continue
		if d_to_amulet.has(name) and from_d + int(d_to_amulet[name]) == amulet_dist:
			count_at_depth[from_d] = int(count_at_depth.get(from_d, 0)) + 1
	var branched := 0
	for c in count_at_depth.values():
		if int(c) >= 2:
			branched += 1
	return branched

# Per-layer "how many nodes are on a shortest-path DAG at depth d?".
# Used by the choose-your-start panel's vertical bar chart.
static func layer_widths(start_id: StringName, amulet_id: StringName) -> Array:
	# Returns [{depth: int, count: int}, ...] from depth 1 to amulet_dist
	# inclusive. The amulet depth has count = 1 (the goal itself).
	var d_from_start := bfs_distances(start_id)
	if not d_from_start.has(amulet_id):
		return []
	var amulet_dist: int = d_from_start[amulet_id]
	var d_to_amulet := bfs_distances(amulet_id)
	var count_at_depth: Dictionary = {}
	for name in d_from_start:
		var from_d: int = d_from_start[name]
		if from_d == 0 or from_d > amulet_dist:
			continue
		if d_to_amulet.has(name) and from_d + int(d_to_amulet[name]) == amulet_dist:
			count_at_depth[from_d] = int(count_at_depth.get(from_d, 0)) + 1
	var out: Array = []
	for d in range(1, amulet_dist + 1):
		out.append({"depth": d, "count": int(count_at_depth.get(d, 1))})
	return out

# Returns the set of game ids that lie on a shortest path between
# start_id and amulet_id, organized by layer. Used by the map preview
# to draw the actual graph nodes.
static func shortest_path_dag(start_id: StringName, amulet_id: StringName) -> Dictionary:
	var d_from_start := bfs_distances(start_id)
	if not d_from_start.has(amulet_id):
		return {"layers": [], "edges": []}
	var amulet_dist: int = d_from_start[amulet_id]
	var d_to_amulet := bfs_distances(amulet_id)
	var layers: Array = []
	for d in range(0, amulet_dist + 1):
		layers.append([])
	for name in d_from_start:
		var from_d: int = d_from_start[name]
		if from_d > amulet_dist:
			continue
		if d_to_amulet.has(name) and from_d + int(d_to_amulet[name]) == amulet_dist:
			(layers[from_d] as Array).append(name)
	var edges: Array = []
	for d in range(0, amulet_dist):
		for a in layers[d]:
			for b in neighbors(a):
				if (layers[d + 1] as Array).has(b):
					edges.append({"from": a, "to": b})
	return {"layers": layers, "edges": edges}

# ---------------------------------------------------------------------------
# Run setup — pick an amulet, then the top-3 starts (one per game type
# if possible), ranked by early-branching score. Mirrors the cancel-save
# handler in js/character-start.js.
# ---------------------------------------------------------------------------

# Result format:
#   {
#     "amulet_id": StringName,
#     "options": [
#       {"start_id": StringName, "type": GameData.GameType, "score": int, "path_len": int},
#       ...
#     ]
#   }
# Returns {} if no valid pair could be found (extremely unlikely with
# the current data set but the JS guards it too).
static func pick_amulet_and_starts(rng: RandomNumberGenerator) -> Dictionary:
	var all: Array[GameData] = []
	for g in Data.all_games():
		if g is GameData:
			all.append(g)
	if all.size() < 2:
		return {}

	# Starts must have >= MIN_START_CONNECTIONS connections; fall back to
	# "any" if the graph is too sparse (mirrors the JS fallback path).
	var eligible_starts: Array[GameData] = []
	for g in all:
		if neighbors(g.id).size() >= MIN_START_CONNECTIONS:
			eligible_starts.append(g)
	if eligible_starts.is_empty():
		eligible_starts = all
	var start_pool: Array[GameData] = eligible_starts

	# Pick the amulet via a random reference start, then score amulet
	# candidates by early-branching from that reference. Candidates with
	# (best - 1) or better score advance to the random pick.
	var ref_start: GameData = start_pool[rng.randi() % start_pool.size()]
	var d_from_ref := bfs_distances(ref_start.id)

	var amulet_candidates: Array[GameData] = []
	for g in all:
		if g.id == ref_start.id:
			continue
		if not d_from_ref.has(g.id):
			continue
		var d: int = d_from_ref[g.id]
		if d >= MIN_PATH_LENGTH and d <= MAX_PATH_LENGTH:
			amulet_candidates.append(g)
	if amulet_candidates.is_empty():
		# Looser fallback: anything reachable that isn't the reference.
		for g in all:
			if g.id != ref_start.id and d_from_ref.has(g.id):
				amulet_candidates.append(g)
	if amulet_candidates.is_empty():
		return {}

	var best_amulet_score := 0
	var amulet_scored: Array = []
	for g in amulet_candidates:
		var s := dag_branch_score_early(d_from_ref, g.id)
		amulet_scored.append({"g": g, "score": s})
		if s > best_amulet_score:
			best_amulet_score = s
	var amulet_finalists: Array[GameData] = []
	if best_amulet_score > 0:
		for entry in amulet_scored:
			if int(entry["score"]) >= best_amulet_score - 1:
				amulet_finalists.append(entry["g"])
	else:
		amulet_finalists = amulet_candidates
	var amulet: GameData = amulet_finalists[rng.randi() % amulet_finalists.size()]

	# For each game type, find the eligible start with the best branching
	# score *toward this amulet*. Then sort by score, take the top 3.
	var d_to_amulet := bfs_distances(amulet.id)
	var best_per_type: Dictionary = {}     # GameType -> {start, score, path_len}
	for type_val in TYPE_ORDER:
		var best: Dictionary = {}
		for g in eligible_starts:
			if g.type != type_val:
				continue
			var d_from := bfs_distances(g.id)
			if not d_from.has(amulet.id):
				continue
			var path_len: int = d_from[amulet.id]
			if path_len < MIN_PATH_LENGTH or path_len > MAX_PATH_LENGTH:
				continue
			var score := dag_branch_score_early(d_from, amulet.id, EARLY_LAYERS_FOR_SCORE, d_to_amulet)
			if best.is_empty() or score > int(best.get("score", -1)):
				best = {"start": g, "score": score, "path_len": path_len}
		if not best.is_empty():
			best_per_type[type_val] = best

	var ranked: Array = []
	for type_val in TYPE_ORDER:
		if best_per_type.has(type_val):
			var rec: Dictionary = best_per_type[type_val]
			ranked.append({
				"type": type_val,
				"start_id": (rec["start"] as GameData).id,
				"score": int(rec["score"]),
				"path_len": int(rec["path_len"]),
			})
	ranked.sort_custom(func(a, b): return int(a["score"]) > int(b["score"]))
	var options: Array = ranked.slice(0, mini(NUM_START_OPTIONS, ranked.size()))
	if options.is_empty():
		# Sparse-graph fallback: ignore the path-length window and just pick
		# any reachable game(s) that aren't the amulet. Prefer one per type
		# if possible so the panel still looks varied.
		var by_type: Dictionary = {}
		for g in eligible_starts:
			if g.id == amulet.id:
				continue
			var d := bfs_distances(g.id)
			if not d.has(amulet.id):
				continue
			if not by_type.has(g.type):
				by_type[g.type] = {
					"type": g.type,
					"start_id": g.id,
					"score": 0,
					"path_len": int(d[amulet.id]),
				}
		for type_val in TYPE_ORDER:
			if by_type.has(type_val):
				options.append(by_type[type_val])
			if options.size() >= NUM_START_OPTIONS:
				break
	if options.is_empty():
		return {}
	return {"amulet_id": amulet.id, "options": options}

# Human-readable type name.
static func type_label(type_val: int) -> String:
	match type_val:
		GameData.GameType.ACTION: return "Action"
		GameData.GameType.STRATEGY: return "Strategy"
		GameData.GameType.DECKBUILDER: return "Deckbuilder"
		GameData.GameType.TRADITIONAL: return "Traditional"
	return "?"

# Per-type starting bonus description (UI-only — applied separately).
static func type_bonus_description(type_val: int) -> String:
	match type_val:
		GameData.GameType.ACTION: return "1 Weapon Reward"
		GameData.GameType.TRADITIONAL: return "1 Item Reward"
		GameData.GameType.STRATEGY: return "+40 Gold"
		GameData.GameType.DECKBUILDER: return "1 Card Reward"
	return ""

# Themed color (RGB) used for the chip + Choose button. Matches the
# typeColors map in character-start.js.
static func type_color(type_val: int) -> Color:
	match type_val:
		GameData.GameType.ACTION: return Color8(0xc0, 0x39, 0x2b)
		GameData.GameType.TRADITIONAL: return Color8(0x7d, 0x3c, 0x98)
		GameData.GameType.STRATEGY: return Color8(0x1a, 0x52, 0x76)
		GameData.GameType.DECKBUILDER: return Color8(0x1e, 0x84, 0x49)
	return Color8(0x55, 0x55, 0x55)
