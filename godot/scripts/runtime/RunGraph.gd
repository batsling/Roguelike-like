class_name RunGraph
extends RefCounted

# Pure-data helpers for picking a start/amulet pair and presenting
# choose-your-start options. Ports js/character-start.js + the
# `getGameConnections` helper from the HTML build into GDScript so the
# Godot main menu can drive the same start-game progression.

# Path length tuning — matches js/character-start.js. With the full
# imported catalog (~660 games, ~840 connections) the graph diameter is
# large enough to support 5..8-step runs.
const MIN_PATH_LENGTH := 5
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
#
# The adjacency list is cached on first use so `neighbors()` is O(1)
# instead of O(N). Without this, picking a start/amulet on the full
# ~660-game catalog ran BFS thousands of times with O(N) per neighbor
# lookup and could freeze the menu.
# ---------------------------------------------------------------------------

static var _adj_cache: Dictionary = {}      # StringName -> Array[StringName]
static var _adj_cache_built: bool = false
static var _bfs_cache: Dictionary = {}       # StringName -> Dictionary (dist map)

static func invalidate_cache() -> void:
	_adj_cache.clear()
	_adj_cache_built = false
	_bfs_cache.clear()

# Whether a game is eligible to appear in path selection, per the global
# Settings.game_filter. Filtered-out games are excluded from the graph
# entirely (no node, no edges), so runs only traverse eligible games.
static func _passes_filter(g: GameData) -> bool:
	match Settings.game_filter:
		Settings.GameFilter.OWNED:
			return g.owned
		Settings.GameFilter.DOWNLOADED:
			return g.file_location.strip_edges() != ""
		_:
			return true

static func _build_adj() -> void:
	if _adj_cache_built:
		return
	_adj_cache.clear()
	# First pass — make sure every eligible game has an entry so a lookup on
	# an isolated node returns [] instead of triggering a default. Games the
	# active filter excludes are left out entirely.
	for g in Data.all_games():
		if _passes_filter(g):
			_adj_cache[g.id] = []
	# Second pass — add a forward and reverse edge per `games_influenced`
	# entry. Dedup via a per-game seen-set so re-runs of the importer
	# can't blow up the adjacency. Edges touching a filtered-out game are
	# skipped (one endpoint won't be in _adj_cache).
	var seen: Dictionary = {}    # StringName -> Dictionary (set)
	for g in Data.all_games():
		if not _adj_cache.has(g.id):
			continue    # filtered out
		if not seen.has(g.id):
			seen[g.id] = {}
		for influenced_id in g.games_influenced:
			if not _adj_cache.has(influenced_id):
				continue    # reference to a game we don't have
			if not seen.has(influenced_id):
				seen[influenced_id] = {}
			if not seen[g.id].has(influenced_id):
				seen[g.id][influenced_id] = true
				(_adj_cache[g.id] as Array).append(influenced_id)
			if not seen[influenced_id].has(g.id):
				seen[influenced_id][g.id] = true
				(_adj_cache[influenced_id] as Array).append(g.id)
	_adj_cache_built = true

static func neighbors(game_id: StringName) -> Array[StringName]:
	_build_adj()
	var out: Array[StringName] = []
	var arr: Array = _adj_cache.get(game_id, [])
	for n in arr:
		out.append(n)
	return out

# Shortest-hop distance from start_id to every reachable game. Memoized
# — picking start/amulet on the full catalog runs BFS hundreds of times
# from a handful of distinct origins, so recomputing is wasteful. Call
# invalidate_cache() if the underlying game graph ever changes.
static func bfs_distances(start_id: StringName) -> Dictionary:
	if _bfs_cache.has(start_id):
		return _bfs_cache[start_id]
	_build_adj()
	var dist: Dictionary = {}
	dist[start_id] = 0
	var queue: Array[StringName] = [start_id]
	var qi := 0
	while qi < queue.size():
		var cur: StringName = queue[qi]
		qi += 1
		var cur_d: int = dist[cur]
		var arr: Array = _adj_cache.get(cur, [])
		for nb in arr:
			if not dist.has(nb):
				dist[nb] = cur_d + 1
				queue.append(nb)
	_bfs_cache[start_id] = dist
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
		if g is GameData and _passes_filter(g):
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
		# Sparse graph (e.g. a restrictive game filter): accept any *connected*
		# game before falling back to the full pool, so we don't pick an
		# isolated reference start that can't reach an amulet.
		for g in all:
			if neighbors(g.id).size() > 0:
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

	# Optional: drop games already won as the amulet (GameStats.amulet_wins),
	# so a fresh run aims at an unbeaten goal. Beaten games stay in the graph
	# as intermediate stops — only the goal pool is filtered. Keep the full
	# pool if every reachable candidate has been beaten (no softlock).
	if Settings.exclude_beaten_amulets:
		var unbeaten: Array[GameData] = []
		for g in amulet_candidates:
			if GameStats.amulet_wins(g.id) == 0:
				unbeaten.append(g)
		if not unbeaten.is_empty():
			amulet_candidates = unbeaten

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

	# Guarantee three *distinct genres* on the panel. The strict pass above
	# only keeps a type when it has a start inside the MIN..MAX path window;
	# sparse graphs can leave us with fewer than three. For every type still
	# missing, relax the path-length window and take the best-scoring reachable
	# start of that genre so the player always gets three different-genre picks.
	if best_per_type.size() < NUM_START_OPTIONS:
		for type_val in TYPE_ORDER:
			if best_per_type.has(type_val):
				continue
			var relaxed: Dictionary = {}
			for g in eligible_starts:
				if g.type != type_val or g.id == amulet.id:
					continue
				var d_from := bfs_distances(g.id)
				if not d_from.has(amulet.id):
					continue
				var path_len: int = d_from[amulet.id]
				var score := dag_branch_score_early(d_from, amulet.id, EARLY_LAYERS_FOR_SCORE, d_to_amulet)
				if relaxed.is_empty() or score > int(relaxed.get("score", -1)):
					relaxed = {"start": g, "score": score, "path_len": path_len}
			if not relaxed.is_empty():
				best_per_type[type_val] = relaxed

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
