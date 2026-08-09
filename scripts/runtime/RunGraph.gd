class_name RunGraph
extends RefCounted

# Pure-data helpers for picking a start/amulet pair and presenting
# choose-your-start options. Ports js/character-start.js + the
# `getGameConnections` helper from the HTML build into GDScript so the
# Godot main menu can drive the same start-game progression.

# Path length tuning. The run opens with a CHOICE OF THREE starting games, each
# 5 to 8 games from the Amulet — so picking a start is a choice of genre, route,
# AND run length. The length is not flavour: enemies take more turns per game the
# closer the run stands to the Amulet (RunDifficulty.turns_for_hops, FAR_HOPS =
# 5), so a start 8 hops out opens with FOUR games in the calm 1-turn band while a
# start 5 hops out gets exactly one before the stack picks up your scent. Starting
# far is a longer run fought slowly; starting near is a short run fought fast.
#
# The band was 6..8 and the floor came back down to 5 because 6 was quietly
# expensive: the Amulet is drawn from games that sit inside the band from some
# eligible start, and on an OWNED-filtered catalog a floor of 6 struck 36 games
# off that list — every one of them a hub (Isaac, Hades, FTL, NetHack, Enter the
# Gungeon, Rogue), because being influential is exactly what puts a game within 5
# hops of everything. It also left only 96 of 357 Amulets able to field the
# three-genre start panel, against 346 at a floor of 5.
#
# The CEILING is not what governs that. With ~100 eligible starts any game 8 hops
# from one of them is <= 7 from another, so sweeping the ceiling from 8 out to 12
# does not add a single Amulet — the pool is set by the floor alone. 8 is kept
# because it is the longest run the pressure ladder still has room to grade.
const MIN_PATH_LENGTH := 5
const MAX_PATH_LENGTH := 8
const EARLY_LAYERS_FOR_SCORE := 3
# How many starts the choose-your-start panel offers. Each comes from a DIFFERENT
# game type (see TYPE_ORDER), so the two cards are always two genres.
const NUM_START_OPTIONS := 2
# Minimum outgoing connections a game needs to qualify as a "start".
# Falls back to any-game on sparse graphs (see pick_amulet_and_starts).
const MIN_START_CONNECTIONS := 3

# Game-type ordering used to pick "one start per type" for the
# choose-your-start panel. All four authored types are eligible, and
# pick_amulet_and_starts takes the best-scoring NUM_START_OPTIONS of them — so the
# offered starts are always DIFFERENT genres. One per type is what guarantees
# that: the panel can never draw two cards from the same genre no matter how the
# scores fall, so shrinking the panel narrows the choice without weakening it.
const TYPE_ORDER: Array = [
	GameData.GameType.ACTION,
	GameData.GameType.STRATEGY,
	GameData.GameType.DECKBUILDER,
	GameData.GameType.TRADITIONAL,
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
# Games that passed the filter but fell outside the main group, as a set. Pruned
# out of _adj_cache and kept here because Transmute needs exactly this list.
static var _off_map: Dictionary = {}         # StringName -> true

static func invalidate_cache() -> void:
	_adj_cache.clear()
	_adj_cache_built = false
	_bfs_cache.clear()
	_off_map.clear()

# Whether a game is eligible to appear in path selection, per the global
# Settings.game_filter. Filtered-out games are excluded from the graph
# entirely (no node, no edges), so runs only traverse eligible games.
# Public face of the same question, for callers outside the graph that need to
# know whether a game is one this run may touch at all — EventSystem's `play_game`
# pool asks it, since sending a player to a game they do not own is exactly what
# the filter exists to prevent.
static func passes_filter(g: GameData) -> bool:
	return g != null and _passes_filter(g)

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
	_prune_to_main_component()
	_adj_cache_built = true

# Third pass — keep only the MAIN GROUP. The influence graph is not one piece:
# on the owned catalog it is a 395-game mainland plus 76 games in sequel pairs and
# lone stars that no route can reach. Leaving them in as nodes made them dead
# weight — a run could never travel to one, but they still counted as games, could
# clear MIN_START_CONNECTIONS on an island of their own, and confused anything
# that asked the graph how big it was.
#
# They are not deleted from the catalog, only from the ROUTE. Off-map games are
# exactly the pool Transmute draws from (see GameLoop2.transmute_game and
# §Transmute in docs/games-first-redesign.md: "a random game of the same game type
# that is not connected to the map"), so being off the map IS their role — it is
# the only way a run ever meets one.
#
# Ties are broken on the lowest id so the same catalog always yields the same
# mainland; a graph that reshuffled itself between calls would move the Amulet.
static func _prune_to_main_component() -> void:
	_off_map.clear()
	if _adj_cache.is_empty():
		return
	var seen: Dictionary = {}
	var best: Array = []
	var best_key: StringName = &""
	var ids: Array = _adj_cache.keys()
	ids.sort()
	for start_id in ids:
		if seen.has(start_id):
			continue
		var comp: Array = []
		var queue: Array = [start_id]
		seen[start_id] = true
		var qi := 0
		while qi < queue.size():
			var cur: StringName = queue[qi]
			qi += 1
			comp.append(cur)
			for nb in (_adj_cache.get(cur, []) as Array):
				if not seen.has(nb):
					seen[nb] = true
					queue.append(nb)
		if comp.size() > best.size() or (comp.size() == best.size() and start_id < best_key):
			best = comp
			best_key = start_id
	var main: Dictionary = {}
	for id in best:
		main[id] = true
	for id in ids:
		if not main.has(id):
			_off_map[id] = true
			_adj_cache.erase(id)
	# Nothing in the mainland can still point at a pruned node — every edge is
	# mirrored, so an edge to an off-map game would have merged the two groups.

# Games inside the active filter that the run's routes cannot reach: everything
# outside the main group. This is the Transmute pool.
static func off_map_ids() -> Array[StringName]:
	_build_adj()
	var out: Array[StringName] = []
	for id in _off_map:
		out.append(id)
	return out

# Whether `game_id` is off the route entirely — filtered out, or in the catalog
# but not in the main group. Both mean the same thing to a run: you cannot walk
# there, and Transmute is the only way to play it.
static func is_off_map(game_id: StringName) -> bool:
	_build_adj()
	return not _adj_cache.has(game_id)

static func neighbors(game_id: StringName) -> Array[StringName]:
	_build_adj()
	var out: Array[StringName] = []
	var arr: Array = _adj_cache.get(game_id, [])
	for n in arr:
		out.append(n)
	return out

# How many games this one connects to IN THE RUN — after the game filter and the
# main-component prune, so it's the count that actually matters for routing, not
# the raw `games_influenced` length. 0 for an off-map game.
#
# Its own function because callers that only want the SIZE (the offering's hub
# rule, which asks this of every candidate) shouldn't pay for neighbors()
# copying the adjacency list out on every check.
static func degree(game_id: StringName) -> int:
	_build_adj()
	return (_adj_cache.get(game_id, []) as Array).size()

# How many of the graph's biggest games carry a shop (§14). Ten is not a round
# number picked for tidiness: on the full catalog the degree curve has a real
# shoulder there — Slay the Spire 141, Vampire Survivors 85, Isaac 69, Hades and
# Balatro 46, Spelunky Classic 37, FTL 36, NetHack 29, Dead Cells 28, Enter the
# Gungeon 26 — and the eleventh game down is in the low twenties with a long flat
# tail behind it. Those ten are also the genre's actual landmarks, which is why
# they read as places rather than as nodes that happened to score well.
const NUM_HUBS := 10

# The run's HUB GAMES: the NUM_HUBS best-connected games on the route, biggest
# first. A shop stands at each of them (§14).
#
# Measured AFTER the filter and the main-component prune, like `degree` — the
# ten biggest games in an OWNED run are not the ten biggest in the catalog, and
# the shops belong to the map the player is actually walking. Ties break on the
# lowest id so the list is stable for a given catalog rather than riding
# dictionary order; without that, two games on 24 connections could swap places
# between calls and a shop would move.
#
# Callers should not lean on this staying put across a run — the game filter can
# rebuild the graph underneath it. GameState freezes the answer at run start
# (`hub_games`) and everything in the run reads that instead, so a shop can never
# appear or vanish under a player mid-route.
static func hub_ids(count: int = NUM_HUBS) -> Array[StringName]:
	_build_adj()
	var ids: Array = _adj_cache.keys()
	# The tie-break lives INSIDE the comparator rather than in a pre-sort, because
	# Godot's sort_custom is not documented as stable — sorting by id and then by
	# degree would leave equal-degree games at the mercy of the sort's internals.
	ids.sort_custom(func(a, b):
		var da: int = (_adj_cache[a] as Array).size()
		var db: int = (_adj_cache[b] as Array).size()
		if da != db:
			return da > db
		return String(a) < String(b))
	var out: Array[StringName] = []
	for id in ids:
		if out.size() >= count:
			break
		out.append(id)
	return out

# Eligible games in this run that share `game_id`'s release year (Winged Boots
# flies to one of these, ignoring connections). Excludes the game itself and any
# already-beaten game so the jump only ever advances the run. The adjacency
# cache's keys are exactly the run's filtered game set.
static func same_year_games(game_id: StringName) -> Array[StringName]:
	_build_adj()
	var cur: GameData = Data.get_game(game_id)
	if cur == null or cur.year <= 0:
		return []
	var out: Array[StringName] = []
	for gid in _adj_cache.keys():
		if gid == game_id or GameState.beaten_games.has(gid):
			continue
		var g: GameData = Data.get_game(gid)
		if g != null and g.year == cur.year:
			out.append(gid)
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
		return {"layers": [], "edges": [], "waypoint_depth": -1}
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
					# The depths travel with the edge. Within one DAG they're
					# redundant (a game sits at exactly one depth), but a route
					# forced through a waypoint is two of these glued together and
					# can hold the same game at two depths — see route_dag_via.
					edges.append({"from": a, "to": b, "from_depth": d, "to_depth": d + 1})
	return {"layers": layers, "edges": edges, "waypoint_depth": -1}

# ---------------------------------------------------------------------------
# Routing through a game you INSIST on visiting
# ---------------------------------------------------------------------------

# The optimal route from `start_id` to `amulet_id` that is forced through
# `waypoint_id`: the shortest way to the waypoint, then the shortest way on to
# the Amulet, glued at the waypoint. Same shape as shortest_path_dag, plus
# `waypoint_depth` — which layer the join sits on.
#
# THE RETURNING PATH is the whole difficulty here. The road out of a waypoint is
# free to walk straight back over the games that led into it, so a forced route
# is not a DAG over game ids at all: the same game can legitimately appear twice,
# at two different depths, once on the way there and once on the way back. That's
# why the layers are kept as they fall and every edge carries its endpoints'
# DEPTHS — a consumer that keys nodes by id alone will collapse the two visits
# into one and draw a road that doesn't exist (see RouteLadder.node_key).
#
# An empty `waypoint_id`, or one you're already standing on, is not a detour at
# all and gives the ordinary shortest-path DAG. A waypoint that can't be reached,
# or that can't reach the Amulet, gives an empty route.
static func route_dag_via(start_id: StringName, waypoint_id: StringName,
		amulet_id: StringName) -> Dictionary:
	if waypoint_id == &"" or waypoint_id == start_id:
		var plain: Dictionary = shortest_path_dag(start_id, amulet_id)
		plain["waypoint_depth"] = 0 if waypoint_id == start_id else -1
		return plain
	var leg_in: Dictionary = shortest_path_dag(start_id, waypoint_id)
	var leg_out: Dictionary = shortest_path_dag(waypoint_id, amulet_id)
	var in_layers: Array = leg_in.get("layers", [])
	var out_layers: Array = leg_out.get("layers", [])
	if in_layers.is_empty() or out_layers.is_empty():
		return {"layers": [], "edges": [], "waypoint_depth": -1}

	var layers: Array = []
	for l in in_layers:
		layers.append((l as Array).duplicate())
	# The join layer belongs to both legs and is only added once — it holds the
	# waypoint alone, since it is the last layer of one shortest-path DAG and the
	# first of the other.
	var offset: int = in_layers.size() - 1
	for i in range(1, out_layers.size()):
		layers.append((out_layers[i] as Array).duplicate())

	var edges: Array = []
	for e in leg_in.get("edges", []):
		edges.append(e.duplicate())
	for e in leg_out.get("edges", []):
		edges.append({
			"from": e["from"], "to": e["to"],
			"from_depth": int(e["from_depth"]) + offset,
			"to_depth": int(e["to_depth"]) + offset,
		})
	return {"layers": layers, "edges": edges, "waypoint_depth": offset}

# How many hops the forced route costs: to the waypoint, then on to the Amulet.
# -1 when either leg has no route.
static func route_length_via(start_id: StringName, waypoint_id: StringName,
		amulet_id: StringName) -> int:
	if waypoint_id == &"" or waypoint_id == start_id:
		var direct: Dictionary = bfs_distances(start_id)
		return int(direct[amulet_id]) if direct.has(amulet_id) else -1
	var to_wp: Dictionary = bfs_distances(start_id)
	if not to_wp.has(waypoint_id):
		return -1
	var from_wp: Dictionary = bfs_distances(waypoint_id)
	if not from_wp.has(amulet_id):
		return -1
	return int(to_wp[waypoint_id]) + int(from_wp[amulet_id])

# ---------------------------------------------------------------------------
# Run setup — pick an amulet, then the top-3 starts (one per game type
# if possible), ranked by early-branching score. Mirrors the cancel-save
# handler in js/character-start.js.
# ---------------------------------------------------------------------------

# How many amulets to try before settling for a panel that can't fill every slot
# from inside the path-length window (see the attempt loop in
# pick_amulet_and_starts).
const AMULET_ATTEMPTS := 8

# How many reference starts the Amulet pool is drawn from before the pick.
#
# It used to be one, and which one it was mattered enormously: the number of
# games sitting 5..8 hops from a single eligible start ranges 21..318 across the
# owned catalog, median 77, against a union of 393 over every start. A run that
# rolled a narrow reference was offered a fifteenth of the goals another run
# would see, for no reason the player could observe. Unioning a few references
# flattens that, and costs one BFS each — bfs_distances is memoized, so every
# later lookup against the same start is free.
const AMULET_REFERENCE_STARTS := 3

# How far below the best early-branching score an Amulet candidate may sit and
# still make the final draw.
#
# The filter is there so the goal has a route worth walking, not so that the same
# handful of well-connected games are the goal every run — at a slack of 1 the
# top ten Amulets took 18% of 600 sampled runs on the owned catalog. Widening it
# spreads the draw across the pool while still excluding candidates whose
# approach has no branching in it at all.
const AMULET_SCORE_SLACK := 2

# Every in-window start worth offering, as type -> (path_len -> record): for each
# genre, the best-branching eligible start AT EACH DISTANCE its routes to `amulet`
# can take. The caller reads the SIZE of the outer dictionary — one entry per
# genre — to judge whether an amulet can fill the panel, exactly as before.
#
# Keeping one start PER LENGTH rather than one per genre is the whole point. The
# panel wants its cards at different distances (see _spread_across_band), and
# collapsing each genre to its single best-scoring start first throws that choice
# away before it can be made: a genre whose top start is 5 hops out still has a 7
# and an 8 further down the score order, and those are what a spread is built
# from. Deciding the spread here, with every length still on the table, is what
# keeps the cost of the rule down to the 23 Amulets that genuinely have no two
# lengths to offer.
static func _strict_starts_for(amulet: GameData, eligible_starts: Array,
		d_to_amulet: Dictionary) -> Dictionary:
	var by_type: Dictionary = {}
	for g in eligible_starts:
		if g.id == amulet.id:
			continue
		var d_from := bfs_distances(g.id)
		if not d_from.has(amulet.id):
			continue
		var path_len: int = d_from[amulet.id]
		if path_len < MIN_PATH_LENGTH or path_len > MAX_PATH_LENGTH:
			continue
		var score := dag_branch_score_early(d_from, amulet.id, EARLY_LAYERS_FOR_SCORE, d_to_amulet)
		if not by_type.has(g.type):
			by_type[g.type] = {}
		var per_len: Dictionary = by_type[g.type]
		var cur: Dictionary = per_len.get(path_len, {})
		# Ties break on the id so the same catalog always offers the same card.
		if cur.is_empty() or score > int(cur["score"]) \
				or (score == int(cur["score"]) and g.id < (cur["start"] as GameData).id):
			per_len[path_len] = {"start": g, "score": score, "path_len": path_len,
				"in_window": true}
	return by_type

# Pick `count` records out of `by_type` — one per genre, and at DIFFERENT
# DISTANCES from the Amulet wherever the graph allows it.
#
# Distance is a real choice now that the band is 5..8: enemies take more turns per
# game the closer the run stands to the Amulet (RunDifficulty.turns_for_hops), so
# an 8-hop card opens with four games in the calm band and a 5-hop card with one.
# Two cards at the same distance offer a genre and nothing else.
#
# It is a PREFERENCE, not a requirement. 23 Amulets on the owned catalog have
# every in-band start at one single distance — no differing-length pair exists at
# any price — and dropping them from the Amulet pool to enforce a presentation
# rule is the worse trade. Those fall back to repeating a length rather than
# shrinking the panel, the same way a sparse graph falls back to an out-of-band
# start rather than offering fewer cards.
#
# Selections are compared on, in order: how many cards are in-window (the band is
# the panel's first promise), then how many DISTINCT lengths they cover, then
# total branching. Exhaustive over at most 4 genres x 4 lengths, so a few hundred
# leaves at worst, run once per amulet attempt.
static func _spread_across_band(by_type: Dictionary, count: int) -> Array:
	var types: Array = []
	for type_val in TYPE_ORDER:
		if by_type.has(type_val):
			types.append(type_val)
	var want: int = mini(count, types.size())
	if want <= 0:
		return []
	var out: Dictionary = {"key": [], "best": []}
	_spread_search(types, 0, by_type, want, [], out)
	return out["best"]

# Ranks one candidate selection. Higher is better, compared left to right.
static func _spread_key(chosen: Array) -> Array:
	var lens: Dictionary = {}
	var in_window := 0
	var total := 0
	for rec in chosen:
		lens[int(rec["path_len"])] = true
		total += int(rec["score"])
		if bool(rec.get("in_window", false)):
			in_window += 1
	return [in_window, lens.size(), total]

static func _key_greater(a: Array, b: Array) -> bool:
	for i in range(mini(a.size(), b.size())):
		if int(a[i]) != int(b[i]):
			return int(a[i]) > int(b[i])
	return false

static func _spread_search(types: Array, ti: int, by_type: Dictionary, want: int,
		chosen: Array, out: Dictionary) -> void:
	if chosen.size() == want:
		var key: Array = _spread_key(chosen)
		if (out["best"] as Array).is_empty() or _key_greater(key, out["key"]):
			out["key"] = key
			out["best"] = chosen.duplicate()
		return
	if ti >= types.size():
		return
	# Not enough genres left to reach `want` — abandon this branch.
	if types.size() - ti < want - chosen.size():
		return
	var per_len: Dictionary = by_type[types[ti]]
	var lens: Array = per_len.keys()
	lens.sort()
	for l in lens:
		chosen.append(per_len[l])
		_spread_search(types, ti + 1, by_type, want, chosen, out)
		chosen.pop_back()
	# ...or skip this genre entirely and take the remaining cards from later ones.
	_spread_search(types, ti + 1, by_type, want, chosen, out)

# Result format:
#   {
#     "amulet_id": StringName,
#     "options": [
#       {"start_id": StringName, "type": GameData.GameType, "score": int,
#        "path_len": int, "in_window": bool},
#       ...
#     ]
#   }
# One option per game type, NUM_START_OPTIONS of them, each `path_len` inside
# MIN..MAX_PATH_LENGTH — `in_window` is false only on the sparse-graph fallbacks
# that fill a slot no in-band start could.
#
# The options are also spread across the band: different genres AND different
# distances from the Amulet, longest first, so the panel is a choice of how long
# the run is as well as what it is played in (see _spread_across_band). Where the
# graph has no two lengths to offer — 23 Amulets on the owned catalog — the cards
# repeat a distance rather than the panel losing one.
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

	# Pick the amulet from the games sitting in the band from ANY OF SEVERAL
	# reference starts, then score each by early-branching. Candidates within
	# AMULET_SCORE_SLACK of the best advance to the random pick.
	var refs: Array[GameData] = []
	var ref_pool: Array[GameData] = start_pool.duplicate()
	for _i in range(mini(AMULET_REFERENCE_STARTS, ref_pool.size())):
		var ri: int = rng.randi() % ref_pool.size()
		refs.append(ref_pool[ri])
		ref_pool.remove_at(ri)
	var ref_ids: Dictionary = {}
	for r in refs:
		ref_ids[r.id] = true
	var ref_dists: Array = []
	for r in refs:
		ref_dists.append(bfs_distances(r.id))

	# A game keeps its BEST score across the references it is in band from — it
	# only has to be a good goal from somewhere, not from all of them.
	var cand_game: Dictionary = {}       # StringName -> GameData
	var cand_score: Dictionary = {}      # StringName -> int
	for i in range(refs.size()):
		var d_ref: Dictionary = ref_dists[i]
		for g in all:
			if ref_ids.has(g.id) or not d_ref.has(g.id):
				continue
			var d: int = d_ref[g.id]
			if d < MIN_PATH_LENGTH or d > MAX_PATH_LENGTH:
				continue
			var s := dag_branch_score_early(d_ref, g.id)
			if not cand_score.has(g.id) or s > int(cand_score[g.id]):
				cand_score[g.id] = s
				cand_game[g.id] = g
	var amulet_candidates: Array[GameData] = []
	for id in cand_game:
		amulet_candidates.append(cand_game[id])
	if amulet_candidates.is_empty():
		# Looser fallback: anything reachable from any reference.
		for i in range(refs.size()):
			var d_ref: Dictionary = ref_dists[i]
			for g in all:
				if ref_ids.has(g.id) or not d_ref.has(g.id) or cand_score.has(g.id):
					continue
				cand_score[g.id] = 0
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
	for g in amulet_candidates:
		best_amulet_score = maxi(best_amulet_score, int(cand_score.get(g.id, 0)))
	var amulet_finalists: Array[GameData] = []
	if best_amulet_score > 0:
		for g in amulet_candidates:
			if int(cand_score.get(g.id, 0)) >= best_amulet_score - AMULET_SCORE_SLACK:
				amulet_finalists.append(g)
	else:
		amulet_finalists = amulet_candidates
	# Pick the amulet, then check it can actually SUPPLY the panel: three genres
	# each with a start inside the 6..8 band. Most amulets can; the odd one leaves a
	# genre short, and rather than quietly offering a 4-hop start we try another
	# amulet from the same finalist pool. bfs_distances is memoized, so an extra
	# attempt is nearly free after the first. The best attempt seen is what we keep
	# if none of them fills the panel outright.
	var amulet: GameData = null
	var best_per_type: Dictionary = {}     # GameType -> {start, score, path_len}
	var d_to_amulet: Dictionary = {}
	var untried: Array[GameData] = amulet_finalists.duplicate()
	for _attempt in range(AMULET_ATTEMPTS):
		if untried.is_empty():
			break
		var idx: int = rng.randi() % untried.size()
		var candidate: GameData = untried[idx]
		untried.remove_at(idx)
		var d_to_cand := bfs_distances(candidate.id)
		var per_type := _strict_starts_for(candidate, eligible_starts, d_to_cand)
		if amulet == null or per_type.size() > best_per_type.size():
			amulet = candidate
			best_per_type = per_type
			d_to_amulet = d_to_cand
		if best_per_type.size() >= NUM_START_OPTIONS:
			break
	if amulet == null:
		amulet = amulet_finalists[rng.randi() % amulet_finalists.size()]
		d_to_amulet = bfs_distances(amulet.id)

	# Guarantee one start per *distinct genre* on the panel. The strict pass
	# above only keeps a type when it has a start inside the MIN..MAX path
	# window; sparse graphs can leave us short. For every type still missing,
	# relax the path-length window and take the best-scoring reachable start of
	# that genre so the player always gets a pick from each live genre. These
	# carry in_window = false, and the ranking below puts every in-window option
	# ahead of them, so a relaxed start is only ever offered to FILL the panel.
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
					relaxed = {"start": g, "score": score, "path_len": path_len, "in_window": false}
			if not relaxed.is_empty():
				best_per_type[type_val] = {int(relaxed["path_len"]): relaxed}

	# Choose the cards: one genre each, spread across the band where it can be.
	# _spread_across_band already prefers in-window records over relaxed ones and
	# distinct lengths over repeated ones, so what comes back is the panel.
	var chosen: Array = _spread_across_band(best_per_type, NUM_START_OPTIONS)
	var options: Array = []
	for rec in chosen:
		options.append({
			"type": (rec["start"] as GameData).type,
			"start_id": (rec["start"] as GameData).id,
			"score": int(rec["score"]),
			"path_len": int(rec["path_len"]),
			"in_window": bool(rec.get("in_window", false)),
		})
	# In-window cards first (the 5..8 band is the promise the panel makes), then
	# the LONGER route, then branching. Distance leads the display order because it
	# is the choice the spread exists to offer — the first card is the long way
	# round, the second the short one, every time, so the panel reads the same way
	# twice rather than reshuffling on score.
	options.sort_custom(func(a, b):
		if bool(a["in_window"]) != bool(b["in_window"]):
			return bool(a["in_window"])
		if int(a["path_len"]) != int(b["path_len"]):
			return int(a["path_len"]) > int(b["path_len"])
		return int(a["score"]) > int(b["score"]))
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
				var plen: int = int(d[amulet.id])
				by_type[g.type] = {
					"type": g.type,
					"start_id": g.id,
					"score": 0,
					"path_len": plen,
					"in_window": plen >= MIN_PATH_LENGTH and plen <= MAX_PATH_LENGTH,
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
