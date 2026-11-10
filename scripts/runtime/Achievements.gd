class_name Achievements
extends RefCounted

# ACHIEVEMENTS (docs/achievements.md; the owner, 10 Nov 2026): things the player
# does that unlock something — for now, characters. Each is an AchievementData in
# data/achievements/; this is the rules over them, and the only place that knows
# how one is counted. What a profile has done is `GameStats.achievements`.
#
# TWO WAYS OF COUNTING, and the screen says which beside every number:
#   run       has to happen inside ONE run. The best run is remembered, with what
#             was held in it, so the screen can say "Best in one run: 2 of 3".
#   lifetime  adds up across every run, read off the stats the game already keeps
#             (so a profile that had perfected ten games before this existed has
#             Zoe from the first boot).
#
# Nothing is ever locked again: once done, it stays done on that profile.

# THE SUITE RUNS WITH THIS ON (test/pre_run_hook.gd): nobody is locked and nothing
# is counted, so a test that hands a body three pennies does not raise a toast in
# a file about something else, and a test that picks Manager can. test_achievements
# turns it off.
static var bypass: bool = false

# What a lifetime count is drawn in beside the ember a single run's is: two kinds
# of number, told apart by more than the words.
const RUN_COLOR := UITheme.ACCENT
const LIFETIME_COLOR := Color(0.46, 0.70, 0.95)

static func all() -> Array:
	return Data.all_achievements()

# The screen's tabs, in the order their first achievement comes up.
static func tabs() -> Array:
	var out: Array = []
	for a in all():
		if not out.has((a as AchievementData).tab):
			out.append((a as AchievementData).tab)
	return out

static func in_tab(tab: String) -> Array:
	return all().filter(func(a) -> bool: return (a as AchievementData).tab == tab)

# The achievement that unlocks `character_id`, or null when nothing locks them.
static func for_character(character_id) -> AchievementData:
	for a in all():
		if String((a as AchievementData).unlocks_character) == String(character_id):
			return a
	return null

static func is_done(a: AchievementData) -> bool:
	if a == null or bypass or Settings.unlock_everything:
		return true
	return bool(GameStats.achievement_record(a.id).get("done", false))

static func character_locked(character_id) -> bool:
	var a: AchievementData = for_character(character_id)
	return a != null and not is_done(a)

static func done_count(list: Array) -> int:
	var n: int = 0
	for a in list:
		if is_done(a):
			n += 1
	return n

# --- counting ---------------------------------------------------------------------

# Where things stand RIGHT NOW: {"value": int, "held": Array[String]}. `held` is
# what a tagged_held count is made of ("item/old_coin", "trinket/burnt_penny"),
# sorted, so the best run's can be shown.
static func measure(a: AchievementData) -> Dictionary:
	match a.metric:
		"tagged_held":
			var held: Array = held_with_tag(a.tag)
			return {"value": held.size(), "held": held}
		"perfects":
			var n: int = 0
			for row in GameStats.stats.values():
				if row is Dictionary:
					n += int((row as Dictionary).get("perfects", 0))
			return {"value": n, "held": []}
	return {"value": 0, "held": []}

# What the screen shows: a lifetime count as it stands, a single-run one at its
# best, neither past the goal.
static func progress(a: AchievementData) -> int:
	var best: int = int(GameStats.achievement_record(a.id).get("best", 0))
	if not a.is_run_scope():
		best = maxi(best, int(measure(a).get("value", 0)))
	return mini(best, a.goal)

# What the best run was holding (keys as `held_with_tag` writes them).
static func best_held(a: AchievementData) -> Array:
	var held = GameStats.achievement_record(a.id).get("held", [])
	return held if held is Array else []

# Every DIFFERENT thing the run holds that carries `tag`: relics on the shelf,
# loot in the pack, and a passive piece the Smelter took out of it. Two copies of
# one trinket are one thing.
static func held_with_tag(tag: String) -> Array:
	var seen: Dictionary = {}
	for it in GameState.inventory:
		if it is ItemData and Locations.tags_of(it).has(tag):
			seen["item/%s" % String((it as ItemData).id)] = true
	for e in GameState.loot_items + GameState.smelted_loot:
		if not (e is Dictionary):
			continue
		var def: Resource = loot_def(e)
		if def != null and Locations.tags_of(def).has(tag):
			seen["%s/%s" % [String(e.get("type", "")), String(e.get("id", ""))]] = true
	var out: Array = seen.keys()
	out.sort()
	return out

# The definition behind a carried piece of loot, whatever kind it is.
static func loot_def(entry: Dictionary) -> Resource:
	var id := StringName(entry.get("id", ""))
	if id == &"":
		return null
	match String(entry.get("type", "")):
		"trinket": return Data.get_trinket(id)
		"potion": return Data.get_potion(id)
		"scroll": return Data.get_scroll(id)
		"wand": return Data.get_wand(id)
		"weapon": return Data.get_weapon(id)
		"card": return Data.get_card(id)
		"bag": return Data.get_bag(id)
	return null

# The picture for one of `held_with_tag`'s keys, or null.
static func held_art(key: String) -> Texture2D:
	var parts: PackedStringArray = key.split("/")
	if parts.size() != 2:
		return null
	var id := StringName(parts[1])
	if parts[0] == "item":
		var it: ItemData = Data.get_item2(id)
		return it.image if it != null else null
	return LootPassives.art_for(loot_def({"type": parts[0], "id": id}))

static func held_name(key: String) -> String:
	var parts: PackedStringArray = key.split("/")
	if parts.size() != 2:
		return key
	var id := StringName(parts[1])
	var def: Resource = Data.get_item2(id) if parts[0] == "item" \
		else loot_def({"type": parts[0], "id": id})
	if def != null and "display_name" in def and String(def.get("display_name")) != "":
		return String(def.get("display_name"))
	return String(parts[1]).capitalize()

# --- checking ---------------------------------------------------------------------

# Count everything not yet done and write down what moved. Called whenever what the
# run holds changes (GameState.inventory_changed) and whenever the stats do
# (GameStats.changed, which a report fires five times — so this is one pass over
# the achievements still open, and a sum over the games' rows for a lifetime one).
static func check(announce: bool = true) -> void:
	if bypass:
		return
	for a in all():
		var ach := a as AchievementData
		if bool(GameStats.achievement_record(ach.id).get("done", false)):
			continue
		var m: Dictionary = measure(ach)
		var newly: bool = GameStats.note_achievement(ach.id, int(m["value"]), ach.goal,
			m["held"] if ach.is_run_scope() else [])
		if newly and announce:
			_announce(ach)

static func _announce(a: AchievementData) -> void:
	var ch: CharacterData = Data.get_character2(a.unlocks_character)
	if ch == null:
		Notifications.notify("★ Achievement unlocked", UITheme.GOLD, null, "achievement")
		return
	Notifications.notify("★ New character: %s" % ch.display_name, UITheme.GOLD,
		ch.shown_icon(), "achievement")
