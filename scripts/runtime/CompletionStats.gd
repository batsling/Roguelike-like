class_name CompletionStats
extends RefCounted

# THE STATS PAGE'S NUMBERS (docs/achievements.md §Stats; the owner, 10 Nov 2026):
# everything this profile has done, in sections, each thing out of how many there
# are — a completion page, with a meter.
#
# Nothing here is stored. Every number is read off what the game already keeps
# (GameStats, Achievements, Radio, TitleUnlocks, Cosmetics) when the page opens.
#
# A SECTION is {"title", "rows", "ratio"}; a ROW is {"label", "value", "total",
# "note"}. `total` 0 is a plain count with nothing to complete (a run record).
#
# THE METER (the owner chose it): a section's is the average of its rows that
# have a total, so each LINE counts the same whatever it is out of; the overall
# one is the average of the sections', so Achievements weigh as much as the
# thousand games. A section with no totals (Run Records) has `ratio` -1 and is
# left out.

const FRACTURE_TOP := 10

# What the Collection veils until seen, in the order it is listed there.
const SEEN := [
	["game", "Games", "all_games"], ["character", "Characters", "all_characters2"],
	["enemy", "Enemies", "all_goal_enemies"], ["boss", "Bosses", "all_bosses"],
	["item", "Items", "all_items2"], ["trinket", "Trinkets", "all_trinkets"],
	["weapon", "Weapons", "all_weapons"], ["evolution", "Evolutions", "all_evolutions"],
	["card", "Cards", "all_cards"], ["potion", "Potions", "all_potions"],
	["scroll", "Scrolls", "all_scrolls2"], ["wand", "Wands", "all_wands"],
	["pill", "Pills", "all_pills"], ["bag", "Bags", "all_bags"],
	["event", "Events", "all_events2"], ["object", "Objects", "all_objects2"],
	["shopkeeper", "Shopkeepers", "all_shopkeepers"], ["location", "Locations", "all_locations"],
]

static func row(label: String, value: int, total: int = 0, note: String = "") -> Dictionary:
	return {"label": label, "value": value, "total": total, "note": note}

static func _section(title: String, rows: Array) -> Dictionary:
	var sum: float = 0.0
	var n: int = 0
	for r in rows:
		if int(r["total"]) > 0:
			sum += clampf(float(r["value"]) / float(r["total"]), 0.0, 1.0)
			n += 1
	return {"title": title, "rows": rows, "ratio": sum / n if n > 0 else -1.0}

static func sections() -> Array:
	return [achievements(), games(), enemies(), characters(), collection(), unlocks(),
		run_records()]

# 0..1: the average of every section that has something to complete.
static func overall(list: Array = []) -> float:
	if list.is_empty():
		list = sections()
	var sum: float = 0.0
	var n: int = 0
	for s in list:
		if float(s["ratio"]) >= 0.0:
			sum += float(s["ratio"])
			n += 1
	return sum / n if n > 0 else 0.0

# --- the sections -------------------------------------------------------------------

static func achievements() -> Dictionary:
	var rows: Array = []
	for tab in Achievements.tabs():
		var list: Array = Achievements.in_tab(String(tab))
		rows.append(row("%s unlocked" % String(tab), _done_for_real(list), list.size()))
	return _section("Achievements", rows)

# Done on THIS profile's record: the test switch opens everyone, and does not
# complete anything.
static func _done_for_real(list: Array) -> int:
	var n: int = 0
	for a in list:
		if bool(GameStats.achievement_record((a as AchievementData).id).get("done", false)):
			n += 1
	return n

static func games() -> Dictionary:
	var total: int = Data.all_games().size()
	var beaten := 0
	var wins := 0
	var perfected := 0
	var perfects := 0
	var amulets := 0
	var amulet_wins := 0
	var top := 0
	var top_amulets := 0
	for id in GameStats.stats:
		var r = GameStats.stats[id]
		if not (r is Dictionary):
			continue
		var b: int = int(r.get("beaten", 0))
		wins += b
		if b > 0:
			beaten += 1
		var p: int = int(r.get("perfects", 0))
		perfects += p
		if p > 0:
			perfected += 1
		var a: int = int(r.get("amulets", 0))
		amulet_wins += a
		if a > 0:
			amulets += 1
		if GameStats.game_fracture_best(id) >= FRACTURE_TOP:
			top += 1
		if GameStats.amulet_best(id) >= FRACTURE_TOP:
			top_amulets += 1
	return _section("Games", [
		row("Different games beaten", beaten, total, "%d wins in all" % wins),
		row("Different games perfected", perfected, total, "%d perfects in all" % perfects),
		row("Different games won as the Amulet", amulets, total, "%d Amulets in all" % amulet_wins),
		row("Different games beaten on Fracture %d" % FRACTURE_TOP, top, total),
		row("Different Amulets won on Fracture %d" % FRACTURE_TOP, top_amulets, total),
	])

static func enemies() -> Dictionary:
	var seen: Dictionary = {}
	var kills := 0
	for g in GameStats.enemy_log:
		var per = GameStats.enemy_log[g]
		if not (per is Dictionary):
			continue
		for e in per:
			var n: int = int((per[e] as Dictionary).get("beaten", 0)) if per[e] is Dictionary else 0
			kills += n
			if n > 0:
				seen[String(e)] = true
	var plain := 0
	var bosses := 0
	for e in seen:
		if Data.get_boss(StringName(e)) != null:
			bosses += 1
		elif Data.get_goal_enemy(StringName(e)) != null:
			plain += 1
	return _section("Enemies", [
		row("Different enemies beaten", plain, Data.all_goal_enemies().size()),
		row("Different bosses beaten", bosses, Data.all_bosses().size()),
		row("Enemies and bosses beaten in all", kills),
	])

# Who is unlocked is the Achievements section's line, not counted here again.
static func characters() -> Dictionary:
	var roster: Array = Data.all_characters2()
	var winners := 0
	for ch in roster:
		if GameStats.character_amulet_wins(ch.id) > 0:
			winners += 1
	# The Fracture ladder is the PLAYER's (docs/players-design.md §2), so the top
	# of it is counted per player.
	var players: Array = Data.all_players()
	var top := 0
	for pl in players:
		if GameStats.player_fracture_best(pl.id) >= FRACTURE_TOP:
			top += 1
	return _section("Characters", [
		row("Characters with an Amulet win", winners, roster.size()),
		row("Players who cleared Fracture %d" % FRACTURE_TOP, top, players.size()),
	])

# One line per character for the table under the Characters section:
# {"name", "locked", "games", "amulets", "perfects", "fracture"} (fracture -1: no win).
static func character_table() -> Array:
	var out: Array = []
	for ch in Data.all_characters2():
		out.append({
			"name": ch.display_name,
			"locked": Achievements.character_locked(ch.id),
			"games": GameStats.character_wins(ch.id),
			"amulets": GameStats.character_amulet_wins(ch.id),
			"perfects": GameStats.character_perfects(ch.id),
			"fracture": GameStats.fracture_best(ch.id),
		})
	return out

static func collection() -> Dictionary:
	var rows: Array = []
	for k in SEEN:
		var total: int = (Data.call(String(k[2])) as Array).size()
		if total > 0:
			rows.append(row("%s seen" % String(k[1]), mini(GameStats.seen_count(String(k[0])), total), total))
	return _section("Collection Discovered", rows)

static func unlocks() -> Dictionary:
	var songs := 0
	for s in Data.all_songs():
		if Radio.is_drawn(s):
			songs += 1
	return _section("Unlocks Earned", [
		row("Radio songs", songs, Data.all_songs().size()),
		row("Title letters", TitleUnlocks.unlocked_keys().size(), TitleLetters.units().size()),
		row("Costumes and icons", Cosmetics.unlocked_keys().size(), CosmeticCatalog.all_units().size()),
	])

static func run_records() -> Dictionary:
	var goals := 0
	for g in GameStats.goal_log:
		for kind in GameStats.goal_log[g]:
			goals += (GameStats.goal_log[g][kind] as Dictionary).size()
	var levels := 0
	for g in GameStats.levelup_log:
		for c in GameStats.levelup_log[g]:
			levels += int((GameStats.levelup_log[g][c] as Dictionary).get("levels", 0))
	var played: int = GameStats.runs_played
	var won: int = GameStats.runs_won
	return _section("Run Records", [
		row("Runs played", played),
		row("Runs won", won, 0, "%d%% of runs" % roundi(100.0 * won / played) if played > 0 else ""),
		row("Different goals completed", goals),
		row("Level-ups earned", levels),
		row("Donation Machine's best bank", GameStats.donation_best()),
	])
