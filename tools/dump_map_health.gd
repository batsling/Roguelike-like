extends GutTest

# MEASURE THE RUN MAP with the game's own graph code, for the times the question
# is "is the map healthy" rather than "does this behave".
#
#     godot --headless -s addons/gut/gut_cmdln.gd \
#         -gdir=res://tools -gprefix=dump_ -gselect=dump_map_health.gd -gexit
#
# A GutTest rather than a plain `-s` script for the same reason
# `dump_obs_payload.gd` is one: `-s` boots a SceneTree without the autoloads, and
# `Data` IS the catalog. It lives in `tools/`, and the suite's own dirs are
# `res://test/`, so it never runs as part of the suite.
#
# It rolls `RunGraph.pick_amulet_and_starts` — the whole picker, references,
# slack, spread and all — rather than reimplementing its rules, so what comes out
# is what a player would actually be offered. Two filters are measured because
# they are two different maps: ALL is the default, OWNED is what the Owned column
# and `atlas_layout_owned.tres` are for.
#
# MAP_HEALTH_ROLLS sets the sample size (default 200).

const TYPE_NAMES := ["Action", "Strategy", "Deckbuilder", "Traditional"]

func test_dump_map_health() -> void:
	var rolls: int = int(OS.get_environment("MAP_HEALTH_ROLLS"))
	if rolls <= 0:
		rolls = 200
	for filter_val in [Settings.GameFilter.ALL, Settings.GameFilter.OWNED]:
		Settings.game_filter = filter_val
		RunGraph.invalidate_cache()
		_report("ALL" if filter_val == Settings.GameFilter.ALL else "OWNED", rolls)
	Settings.game_filter = Settings.GameFilter.ALL
	RunGraph.invalidate_cache()
	assert_true(true, "the report is the output")

func _report(label: String, rolls: int) -> void:
	var on_map: Array = []
	var edges := 0
	var starts := 0
	var deg_sum := 0
	var leaves := 0
	for g in Data.all_games():
		if not RunGraph.passes_filter(g) or RunGraph.is_off_map(g.id):
			continue
		on_map.append(g)
		var d: int = RunGraph.degree(g.id)
		edges += d
		deg_sum += d
		if d >= 3:
			starts += 1
		if d == 1:
			leaves += 1
	print("\n=== %s filter ===" % label)
	print("  on the map        %d" % on_map.size())
	print("  off the map       %d" % RunGraph.off_map_ids().size())
	print("  edges             %d" % (edges / 2))
	print("  mean degree       %.2f" % (float(deg_sum) / maxf(1.0, float(on_map.size()))))
	print("  leaves (degree 1) %d" % leaves)
	print("  eligible starts   %d" % starts)
	var hubs: Array = []
	for id in RunGraph.hub_ids():
		hubs.append("%s (%d)" % [Data.get_game(id).display_name, RunGraph.degree(id)])
	print("  hubs              %s" % ", ".join(hubs))

	var amulets: Dictionary = {}
	var start_hits: Dictionary = {}
	var genres: Dictionary = {}
	var lengths: Dictionary = {}
	var amulet_degree: Dictionary = {}
	var out_of_band := 0
	var cards := 0
	var rng := RandomNumberGenerator.new()
	for i in range(rolls):
		rng.seed = 900000 + i
		var pick: Dictionary = RunGraph.pick_amulet_and_starts(rng)
		if pick.is_empty():
			continue
		var aid: StringName = pick["amulet_id"]
		amulets[aid] = int(amulets.get(aid, 0)) + 1
		var ad: int = mini(RunGraph.degree(aid), 6)
		amulet_degree[ad] = int(amulet_degree.get(ad, 0)) + 1
		for opt in pick["options"]:
			cards += 1
			var sid: StringName = opt["start_id"]
			start_hits[sid] = int(start_hits.get(sid, 0)) + 1
			genres[opt["type"]] = int(genres.get(opt["type"], 0)) + 1
			lengths[opt["path_len"]] = int(lengths.get(opt["path_len"], 0)) + 1
			if not bool(opt["in_window"]):
				out_of_band += 1
	print("  -- %d rolls --" % rolls)
	print("  distinct amulets  %d  (top ten %.1f%%)" % [amulets.size(), _top_share(amulets, 10, rolls)])
	print("  amulet leaderboard %s" % _leaderboard(amulets, 6, rolls))
	print("  amulet degree     %s" % _bucket_line(amulet_degree, rolls))
	print("  distinct starts   %d  (top ten %.1f%%)" % [start_hits.size(), _top_share(start_hits, 10, cards)])
	print("  start leaderboard %s" % _leaderboard(start_hits, 6, cards))
	var gline: Array = []
	for t in range(TYPE_NAMES.size()):
		gline.append("%s %d%%" % [TYPE_NAMES[t], roundi(100.0 * float(genres.get(t, 0)) / maxf(1.0, float(cards)))])
	print("  card genres       %s" % ", ".join(gline))
	print("  route lengths     %s" % _bucket_line(lengths, cards))
	print("  cards outside the band  %d of %d" % [out_of_band, cards])

func _sorted_ids(hits: Dictionary) -> Array:
	var ids: Array = hits.keys()
	ids.sort_custom(func(a, b): return int(hits[a]) > int(hits[b]))
	return ids

func _top_share(hits: Dictionary, n: int, total: int) -> float:
	var ids: Array = _sorted_ids(hits)
	var s := 0
	for i in range(mini(n, ids.size())):
		s += int(hits[ids[i]])
	return 100.0 * float(s) / maxf(1.0, float(total))

func _leaderboard(hits: Dictionary, n: int, total: int) -> String:
	var ids: Array = _sorted_ids(hits)
	var parts: Array = []
	for i in range(mini(n, ids.size())):
		var g: GameData = Data.get_game(ids[i])
		parts.append("%s %.1f%% (deg %d)" % [
			g.display_name if g != null else str(ids[i]),
			100.0 * float(hits[ids[i]]) / maxf(1.0, float(total)),
			RunGraph.degree(ids[i])])
	return ", ".join(parts)

func _bucket_line(hits: Dictionary, total: int) -> String:
	var keys: Array = hits.keys()
	keys.sort()
	var parts: Array = []
	for k in keys:
		parts.append("%s:%d%%" % [k, roundi(100.0 * float(hits[k]) / maxf(1.0, float(total)))])
	return ", ".join(parts)
