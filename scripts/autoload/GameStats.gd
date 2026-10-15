extends Node

# Cross-run, lifetime per-game play stats — the Godot port of the HTML build's
# `gameStats` localStorage record (collection.js getGameStats/incrementGameBeaten).
# Like TierList, this persists in a single global file that outlives any run.
#
# Two counters per game:
#   beaten  — times the player beat the game AND verified it (played the real
#             game). Skipping the verification does NOT count, by design.
#   amulets — times the game was the run's amulet and the run was won. A win
#             also bumps `beaten` (reaching the amulet means you beat it),
#             matching the HTML's incrementGameBeaten(name, true).
#
# Also tracks which DECKS each character has won a run with (the HTML build's
# `deckWins` localStorage record — see legacy-web/js/main.js recordDeckWin).
# Drives the "Beaten With Deck" checklist on character select + Collection.
#
# Persisted shape (user://game_stats.json):
#   { "games": { "hades": {"beaten": 3, "amulets": 1, "perfects": 1}, ... },
#     "deck_wins": { "ironclad": ["Random", "Silent"], ... },
#     "enemy_log": { "<game>": { "<enemy>": {"beaten": 2, "note": "…"} } },
#     "levelup_log": { "<game>": { "<character>": {"levels": 1, "note": "…"} } },
#     "status_goal_log": { "<game>": { "<status>": {"note": "…"} } },
#     "character_enemy_log": { "<character>": { "<enemy>": {"beaten": 4} } },
#     "character_game_log": { "<character>": { "<game>": {"beaten": 2,
#                                                "amulets": 0, "perfects": 1} } },
#     "character_goal_log": { "<character>": { "<kind>": { "<key>":
#                                                {"done": 1, "label": "…"} } } } }
# (Older files were the bare games dictionary; load_data migrates them, and a
# file predating any of the three logs just starts that log empty.)

signal changed

# Per-profile (see Profiles): a function, not a const, because the answer moves
# when the player switches profile.
static func save_path() -> String:
	return Profiles.path("game_stats.json")

# game-id String -> {"beaten": int, "amulets": int}
var stats: Dictionary = {}

# character-id String -> Array[String] of DeckCatalog deck ids won with
var deck_wins: Dictionary = {}

# Finished runs, newest first. Each is the route the player actually walked:
#   {"path": [game ids], "amulet": id, "won": bool, "character": id,
#    "at": unix seconds, "beaten": int}
# Capped, because this file is rewritten on every run and nobody needs a
# thousand of them.
const MAX_RUNS := 40
var runs: Array = []

# Which enemies have been beaten ON which game, and the player's own notes about
# how. Keyed game id -> enemy id -> {"beaten": int, "note": String}.
#
# A note belongs to the PAIR, not to the enemy: the same goal-enemy shows up on
# many games and how you cleared it is a fact about that combination.
var enemy_log: Dictionary = {}

# The same record for LEVEL-UPS: which characters levelled at which game, and
# what the player wrote about doing it. Keyed game id -> character id ->
# {"levels": int, "note": String}.
#
# The pairing matches enemy_log for the same reason. A character's level-up is a
# standing condition ("Unlock a new Item", "Collect 3+ types of currency") that
# reads completely differently game to game, so how you satisfied it is a fact
# about the (game, character) combination, not about the character alone.
var levelup_log: Dictionary = {}

# The player's notes on the WINNING-RUN STATUS GOALS, keyed game id -> status id
# -> {"note": String}. `levelup_log` for the other half of that section of the
# checklist (see ReportChecklist's winning-run block), and paired the same way and
# for the same reason: "beat every boss without getting hit" is a standing
# condition that reads completely differently game to game, so how you were
# getting on with it is a fact about the (game, status) combination.
#
# NOTE ONLY, with no count beside it. A level-up is a thing that HAPPENS at a game
# and is worth tallying; a status goal is a claim about the run, and how many
# times it has been ticked at one game is not a fact anyone reads.
var status_goal_log: Dictionary = {}

# Which goal-enemies each CHARACTER has beaten, across every run and every game
# they were beaten at. Keyed character id -> enemy id -> {"beaten": int}.
#
# Deliberately not keyed by game as well: this is the character's own trophy
# shelf, the roster-side counterpart to "enemies beaten in <game>". Which game
# each fell at is already in enemy_log.
var character_enemy_log: Dictionary = {}

# Which GAMES each character has beaten, playing as them. Keyed character id ->
# game id -> {"beaten": int}. The character page's "Games beaten". Started
# empty when it was added: no older record says which character beat which game,
# and the owner chose an empty list over a guessed one.
var character_game_log: Dictionary = {}

# EVERY OTHER KIND OF GOAL, per CHARACTER (character ranks,
# docs/games-first-redesign.md §20.9): what goal_log is to a game, keyed by who
# was playing. Keyed character id -> kind -> goal key -> {"done", "label"}.
# Enemies and bosses are not written here — character_enemy_log already has
# them — and nor is a character's OWN level-up from before this log existed,
# which levelup_log still answers (`character_goals` reads all three).
var character_goal_log: Dictionary = {}

# EVERY OTHER KIND OF GOAL, per game: the weapons charged, the standing status
# goals met, the bonus clauses paid and the curses followed. Keyed game id -> kind -> goal key -> {"done": int, "label": String}.
#
# The enemies and the level-ups keep their own logs above (they carry notes and
# predate this); `goals_at` reads all three as one list, which is what the
# Collection's game page draws and what Roguelike Radio counts towards a game's
# songs, one for every five (docs/roguelike-radio.md).
var goal_log: Dictionary = {}

# THE KINDS, IN THE ORDER A GAME'S PAGE LISTS THEM: who you are, what you fought
# (bosses after the rest), what you carried, what you were holding yourself to,
# what an enemy's clause paid, and last the curses you followed. Every one of
# them counts towards "complete X distinct goals".
#
# A BONUS is keyed by its STATUS, not by the enemy it rode on: Burn paid on two
# different enemies is one goal, the same rule that makes five Monkeys one.
#
# EVENT GOALS ARE NOT ON THIS LIST, on purpose (the owner's call): there is one
# of them in the game and it is not worth a section. `record_goal` refuses the
# kind, so none are written, and `goals_at` drops any an older save holds.
const GOAL_KINDS := ["character", "enemy", "boss", "weapon", "status", "bonus",
	"curse"]
const GOAL_KIND_NAMES := {
	"character": "Character", "enemy": "Enemies", "boss": "Bosses",
	"weapon": "Weapons", "status": "Statuses", "bonus": "Bonuses",
	"curse": "Curses",
}

func _ready() -> void:
	load_data()

# ---------------------------------------------------------------------------
# Reads
# ---------------------------------------------------------------------------

func get_stats(id) -> Dictionary:
	var key := String(id)
	if not stats.has(key):
		return {"beaten": 0, "amulets": 0}
	return stats[key]

# The two counts read `stats` DIRECTLY rather than going through get_stats, and
# that is a performance decision rather than a style one.
#
# get_stats returns a fresh `{"beaten": 0, "amulets": 0}` for a game with no
# record — which is most games — so every ask for a count on an unplayed game
# allocated a Dictionary and threw it away. The Atlas's catalog view asks for both
# counts on every star of an 852-star sky on every redraw (AtlasView's
# star_record_color), so a pan across the chart was minting thousands of
# throwaway dictionaries a frame for two integers that are almost always zero.
# Measured over the whole sky: ~1.0 ms a pass, all of it garbage.
#
# get_stats keeps its contract for anything that wants the record as a whole —
# it hands back a private copy, which is what a caller that might mutate it
# needs.
func beaten_count(id) -> int:
	var row: Variant = stats.get(String(id))
	return int((row as Dictionary).get("beaten", 0)) if row is Dictionary else 0

func amulet_wins(id) -> int:
	var row: Variant = stats.get(String(id))
	return int((row as Dictionary).get("amulets", 0)) if row is Dictionary else 0

# How many visits beat this game with no lost run on that visit — PERFECTED it
# (game ranks, docs/games-first-redesign.md §20.1). Started at 0 when it was
# added: nothing before it recorded a perfect, so none can be backfilled.
func perfect_count(id) -> int:
	var row: Variant = stats.get(String(id))
	return int((row as Dictionary).get("perfects", 0)) if row is Dictionary else 0

# How many runs have put this game in a rift (docs/rifts-design.md §3.3). The
# rotation hands out the least-seen first.
func rift_count(id) -> int:
	var row: Variant = stats.get(String(id))
	return int((row as Dictionary).get("rifts", 0)) if row is Dictionary else 0

# The rift games of the most recent run, which the next run's rotation saves for
# last so two runs in a row never share them.
var last_rifts: Array = []

func last_rift_games() -> Array:
	return last_rifts

# Records a run's rift games: one more appearance each, and the list the next run
# avoids. Called once, when the run is dealt its rifts.
func record_rifts(ids: Array) -> void:
	last_rifts = []
	for id in ids:
		var e := _entry(String(id))
		e["rifts"] = int(e.get("rifts", 0)) + 1
		last_rifts.append(String(id))
	save_data()

# A Rift Key opened a rift mid-run (docs/rifts-design.md §8): one more appearance
# for the rotation, without touching last run's list, which is the dealt rifts'.
func record_key_rift(id) -> void:
	var e := _entry(String(id))
	e["rifts"] = int(e.get("rifts", 0)) + 1
	save_data()

# ---------------------------------------------------------------------------
# Writes
# ---------------------------------------------------------------------------

# Records a verified beat. Called when the player confirms the "play the real
# game" verification — NOT on skip.
func record_beaten(id) -> void:
	_entry(String(id))["beaten"] += 1
	save_data()
	emit_signal("changed")

# Records a won run keyed to its amulet game. Bumps both amulets and beaten so
# an amulet-only win still shows in the beaten tally.
func record_amulet_win(id) -> void:
	var e := _entry(String(id))
	e["beaten"] += 1
	e["amulets"] += 1
	save_data()
	emit_signal("changed")

# Records a PERFECTED visit: the game won with no lost run logged on it (§20.1).
# Called beside record_beaten / record_amulet_win, never instead of them.
func record_perfect(id) -> void:
	var e := _entry(String(id))
	e["perfects"] = int(e.get("perfects", 0)) + 1
	save_data()
	emit_signal("changed")

func _entry(key: String) -> Dictionary:
	if not stats.has(key):
		stats[key] = {"beaten": 0, "amulets": 0}
	return stats[key]

# ---------------------------------------------------------------------------
# Persistence
# ---------------------------------------------------------------------------

# Write a finished run to history. Called from GameLoop2._finish_run, which is
# the only way a run ends. A run that never moved anywhere is not recorded —
# there's no route to show.
func record_run(did_win: bool) -> void:
	var path: Array = []
	# The walk, repeats included (GameState.walked_path) — a run that went back to
	# a game twice is a different run from one that passed it once, and the history
	# it is filed under should be able to tell them apart.
	for id in GameState.walked_path():
		path.append(String(id))
	if path.size() < 2:
		return
	runs.push_front({
		"path": path,
		"amulet": String(GameState.amulet_game_id),
		"won": did_win,
		"character": String(GameState.character_id),
		"at": int(Time.get_unix_time_from_system()),
		"beaten": int(GameState.total_games_beaten),
	})
	while runs.size() > MAX_RUNS:
		runs.pop_back()
	save_data()
	changed.emit()

# Record that `enemy_id` was beaten while playing `game_id`. Idempotent per
# clear — the count is how many times, so a re-clear is visible.
func record_enemy_beaten(game_id, enemy_id) -> void:
	var g := String(game_id)
	var e := String(enemy_id)
	if g == "" or e == "":
		return
	if not enemy_log.has(g):
		enemy_log[g] = {}
	var entry: Dictionary = enemy_log[g].get(e, {"beaten": 0, "note": ""})
	entry["beaten"] = int(entry.get("beaten", 0)) + 1
	enemy_log[g][e] = entry
	save_data()
	changed.emit()

# The player's note on how they beat `enemy_id` at `game_id`. Storing a note for
# a pair that was never beaten is allowed — you might write it before ticking.
func set_enemy_note(game_id, enemy_id, note: String) -> void:
	var g := String(game_id)
	var e := String(enemy_id)
	if g == "" or e == "":
		return
	if not enemy_log.has(g):
		enemy_log[g] = {}
	var entry: Dictionary = enemy_log[g].get(e, {"beaten": 0, "note": ""})
	entry["note"] = note
	enemy_log[g][e] = entry
	save_data()
	changed.emit()

# Erase the note for a pair, keeping how many times the enemy fell there — that
# is a record of fact rather than something the player wrote.
func clear_enemy_note(game_id, enemy_id) -> void:
	var g := String(game_id)
	var e := String(enemy_id)
	if not enemy_log.has(g) or not enemy_log[g].has(e):
		return
	enemy_log[g][e]["note"] = ""
	save_data()
	changed.emit()

# The inverse of enemies_for(): every GAME this enemy has been beaten at, most
# beaten first, as [{"id": String, "beaten": int, "note": String}]. Drives the
# Collection's enemy detail.
func games_for_enemy(enemy_id) -> Array:
	var target := String(enemy_id)
	var out: Array = []
	for g in enemy_log.keys():
		var entry: Dictionary = enemy_log[g].get(target, {})
		if entry.is_empty() or int(entry.get("beaten", 0)) <= 0:
			continue
		out.append({"id": String(g), "beaten": int(entry.get("beaten", 0)),
			"note": String(entry.get("note", ""))})
	out.sort_custom(func(a, b):
		if int(a["beaten"]) != int(b["beaten"]):
			return int(a["beaten"]) > int(b["beaten"])
		return String(a["id"]) < String(b["id"]))
	return out

func enemy_note(game_id, enemy_id) -> String:
	return String(enemy_log.get(String(game_id), {}).get(String(enemy_id), {}).get("note", ""))

func enemy_beaten_count(game_id, enemy_id) -> int:
	return int(enemy_log.get(String(game_id), {}).get(String(enemy_id), {}).get("beaten", 0))

# Every enemy logged against a game, most-beaten first then by name, as
# [{"id": String, "beaten": int, "note": String}]. Used by the Atlas card.
func enemies_for(game_id) -> Array:
	var out: Array = []
	for e in enemy_log.get(String(game_id), {}).keys():
		var entry: Dictionary = enemy_log[String(game_id)][e]
		out.append({"id": String(e), "beaten": int(entry.get("beaten", 0)),
			"note": String(entry.get("note", ""))})
	out.sort_custom(func(a, b):
		if int(a["beaten"]) != int(b["beaten"]):
			return int(a["beaten"]) > int(b["beaten"])
		return String(a["id"]) < String(b["id"]))
	return out

# One goal of a kind enemy_log and levelup_log do not cover, completed at a
# game. `key` is what makes two completions the SAME goal (a weapon's id, a
# status's id, a curse's id); `label` is how the game's page names it.
func record_goal(game_id, kind: String, key: String, label: String) -> void:
	var g := String(game_id)
	if g == "" or key == "" or not (kind in GOAL_KINDS):
		return
	if not goal_log.has(g):
		goal_log[g] = {}
	if not goal_log[g].has(kind):
		goal_log[g][kind] = {}
	var entry: Dictionary = goal_log[g][kind].get(key, {"done": 0, "label": label})
	entry["done"] = int(entry.get("done", 0)) + 1
	if label != "":
		entry["label"] = label
	goal_log[g][kind][key] = entry
	# …and on the record of whoever was playing (§20.9).
	_add_character_goal(String(GameState.character_id), kind, key, label)
	save_data()
	changed.emit()

# EVERY goal completed at a game, grouped by kind in GOAL_KINDS order:
# kind -> [{"key", "label", "done", "note"}], each kind sorted by label. Kinds
# with nothing done are left out.
func goals_at(game_id) -> Dictionary:
	var g := String(game_id)
	var out: Dictionary = {}
	for e in enemy_log.get(g, {}).keys():
		var entry: Dictionary = enemy_log[g][e]
		if int(entry.get("beaten", 0)) <= 0:
			continue
		var is_boss: bool = Data.get_boss(StringName(e)) != null
		var enemy: GoalEnemyData = Data.get_goal_enemy_any(StringName(e))
		_add_goal(out, "boss" if is_boss else "enemy", String(e),
			enemy.display_name if enemy != null else String(e).capitalize(),
			int(entry.get("beaten", 0)), String(entry.get("note", "")))
	for c in levelup_log.get(g, {}).keys():
		var entry: Dictionary = levelup_log[g][c]
		if int(entry.get("levels", 0)) <= 0:
			continue
		var ch: CharacterData = Data.get_character2(StringName(c))
		_add_goal(out, "character", String(c),
			ch.display_name if ch != null else String(c).capitalize(),
			int(entry.get("levels", 0)), String(entry.get("note", "")))
	var rest: Dictionary = goal_log.get(g, {})
	for kind in rest.keys():
		for key in rest[kind].keys():
			var entry: Dictionary = rest[kind][key]
			var note: String = status_goal_note(g, key) if kind == "status" else ""
			_add_goal(out, String(kind), String(key), String(entry.get("label", key)),
				int(entry.get("done", 0)), note)
	var ordered: Dictionary = {}
	for kind in GOAL_KINDS:
		if out.has(kind):
			var rows: Array = out[kind]
			rows.sort_custom(func(a, b): return String(a["label"]) < String(b["label"]))
			ordered[kind] = rows
	return ordered

func _add_goal(out: Dictionary, kind: String, key: String, label: String,
		done: int, note: String) -> void:
	if not out.has(kind):
		out[kind] = []
	out[kind].append({"key": key, "label": label, "done": done, "note": note})

# The DISTINCT goals completed at a game, each counted once however often it was
# done again. Roguelike Radio draws a song at a game for every five of these.
func distinct_goals_count(game_id) -> int:
	var n: int = 0
	var all: Dictionary = goals_at(game_id)
	for kind in all.keys():
		n += (all[kind] as Array).size()
	return n

func has_enemy_log(game_id) -> bool:
	return not enemy_log.get(String(game_id), {}).is_empty()

# ---------------------------------------------------------------------------
# Level-ups: the (game, character) pair, mirroring enemy_log
# ---------------------------------------------------------------------------

# Record that `character_id` levelled up while playing `game_id`. One call per
# level gained, so a Crown-chained double level counts twice.
#
# `masked`: the level was a MYSTERIOUS MASK's — `character_id`'s condition met
# while playing someone else. It is still a goal done at this game (the game's
# page lists it and Roguelike Radio counts it), so it lands in `levels` like any
# other; `masked` counts how many of those were borrowed, so the character's own
# page (games_for_character) lists only the games they levelled up at themselves.
func record_level_up(game_id, character_id, masked: bool = false) -> void:
	var g := String(game_id)
	var c := String(character_id)
	if g == "" or c == "":
		return
	if not levelup_log.has(g):
		levelup_log[g] = {}
	var entry: Dictionary = levelup_log[g].get(c, {"levels": 0, "note": ""})
	entry["levels"] = int(entry.get("levels", 0)) + 1
	if masked:
		entry["masked"] = int(entry.get("masked", 0)) + 1
	levelup_log[g][c] = entry
	# …and on the PLAYER's record (§20.9): a level is a goal of the character
	# being played, and a masked one is `c`'s level taken by someone else.
	_add_character_goal(String(GameState.character_id) if masked else c,
		"character", c, _character_name(c))
	save_data()
	changed.emit()

# The player's note on how they hit `character_id`'s level-up at `game_id`.
# Writable before the level is ever taken, exactly like an enemy note.
func set_level_up_note(game_id, character_id, note: String) -> void:
	var g := String(game_id)
	var c := String(character_id)
	if g == "" or c == "":
		return
	if not levelup_log.has(g):
		levelup_log[g] = {}
	var entry: Dictionary = levelup_log[g].get(c, {"levels": 0, "note": ""})
	entry["note"] = note
	levelup_log[g][c] = entry
	save_data()
	changed.emit()

# Erase the note, keeping how many times the level was taken there — that is a
# record of fact rather than something the player wrote.
func clear_level_up_note(game_id, character_id) -> void:
	var g := String(game_id)
	var c := String(character_id)
	if not levelup_log.has(g) or not levelup_log[g].has(c):
		return
	levelup_log[g][c]["note"] = ""
	save_data()
	changed.emit()

func level_up_note(game_id, character_id) -> String:
	return String(levelup_log.get(String(game_id), {}).get(String(character_id), {}).get("note", ""))

# ---------------------------------------------------------------------------
# Winning-run status goals: the (game, status) pair, mirroring levelup_log
# ---------------------------------------------------------------------------

func set_status_goal_note(game_id, status_id, note: String) -> void:
	var g := String(game_id)
	var sid := String(status_id)
	if g == "" or sid == "":
		return
	if not status_goal_log.has(g):
		status_goal_log[g] = {}
	status_goal_log[g][sid] = {"note": note}
	save_data()
	changed.emit()

func status_goal_note(game_id, status_id) -> String:
	return String(status_goal_log.get(String(game_id), {})
		.get(String(status_id), {}).get("note", ""))

func level_up_count(game_id, character_id) -> int:
	return int(levelup_log.get(String(game_id), {}).get(String(character_id), {}).get("levels", 0))

# Every character logged against a game, most levels first then by id, as
# [{"id": String, "levels": int, "note": String}]. Drives the game detail.
func characters_for_game(game_id) -> Array:
	var out: Array = []
	for c in levelup_log.get(String(game_id), {}).keys():
		var entry: Dictionary = levelup_log[String(game_id)][c]
		out.append({"id": String(c), "levels": int(entry.get("levels", 0)),
			"note": String(entry.get("note", ""))})
	_sort_log(out, "levels")
	return out

# The inverse: every GAME this character has levelled up at, AS THEMSELVES —
# a level taken through a Mysterious Mask is not counted here (`masked`), since
# the character page is about games played as that character. Drives the
# character detail.
func games_for_character(character_id) -> Array:
	var target := String(character_id)
	var out: Array = []
	for g in levelup_log.keys():
		var entry: Dictionary = levelup_log[g].get(target, {})
		if entry.is_empty():
			continue
		# A note with no level yet still lists (a plan written before the level
		# was taken) — unless the only level there is a masked one, whose note is
		# about the game played as someone else.
		var own: int = int(entry.get("levels", 0)) - int(entry.get("masked", 0))
		if own <= 0 and (int(entry.get("masked", 0)) > 0
				or String(entry.get("note", "")).strip_edges() == ""):
			continue
		out.append({"id": String(g), "levels": own,
			"note": String(entry.get("note", ""))})
	_sort_log(out, "levels")
	return out

# ---------------------------------------------------------------------------
# The character's trophy shelf: which enemies fell to whom
# ---------------------------------------------------------------------------

# Record that `character_id` beat `enemy_id`. Called alongside
# record_enemy_beaten, so the two records can never disagree about a defeat.
func record_character_enemy(character_id, enemy_id) -> void:
	var c := String(character_id)
	var e := String(enemy_id)
	if c == "" or e == "":
		return
	if not character_enemy_log.has(c):
		character_enemy_log[c] = {}
	var entry: Dictionary = character_enemy_log[c].get(e, {"beaten": 0})
	entry["beaten"] = int(entry.get("beaten", 0)) + 1
	character_enemy_log[c][e] = entry
	save_data()
	changed.emit()

# Every enemy this character has beaten, most-beaten first then by id, as
# [{"id": String, "beaten": int}].
func enemies_for_character(character_id) -> Array:
	var out: Array = []
	for e in character_enemy_log.get(String(character_id), {}).keys():
		var entry: Dictionary = character_enemy_log[String(character_id)][e]
		out.append({"id": String(e), "beaten": int(entry.get("beaten", 0))})
	_sort_log(out, "beaten")
	return out

func character_enemy_count(character_id, enemy_id) -> int:
	return int(character_enemy_log.get(String(character_id), {}).get(String(enemy_id), {}).get("beaten", 0))

# ---------------------------------------------------------------------------
# The games a character has beaten, playing as them
# ---------------------------------------------------------------------------

# Record that `game_id` was beaten while playing `character_id`. Called beside
# record_beaten / record_amulet_win, so this and the game's own tally agree.
#
# `amulet` and `perfect` say the win was also the run's Amulet, or a perfected
# visit (§20.1): the character's rank pays for each once, like the game's does.
func record_character_game(character_id, game_id, amulet: bool = false,
		perfect: bool = false) -> void:
	var c := String(character_id)
	var g := String(game_id)
	if c == "" or g == "":
		return
	if not character_game_log.has(c):
		character_game_log[c] = {}
	var entry: Dictionary = character_game_log[c].get(g, {"beaten": 0})
	entry["beaten"] = int(entry.get("beaten", 0)) + 1
	if amulet:
		entry["amulets"] = int(entry.get("amulets", 0)) + 1
	if perfect:
		entry["perfects"] = int(entry.get("perfects", 0)) + 1
	character_game_log[c][g] = entry
	save_data()
	changed.emit()

# Every game this character has beaten, most-beaten first then by id, as
# [{"id": String, "beaten": int}].
func games_beaten_by(character_id) -> Array:
	var out: Array = []
	for g in character_game_log.get(String(character_id), {}).keys():
		var entry: Dictionary = character_game_log[String(character_id)][g]
		out.append({"id": String(g), "beaten": int(entry.get("beaten", 0))})
	_sort_log(out, "beaten")
	return out

# ---------------------------------------------------------------------------
# A character's own record, for its rank (§20.9)
# ---------------------------------------------------------------------------

# Every game won playing as `character_id`, however many times each.
func character_wins(character_id) -> int:
	return _character_game_sum(character_id, "beaten")

func character_perfects(character_id) -> int:
	return _character_game_sum(character_id, "perfects")

# Amulet wins as `character_id`. The count only started with character ranks, so
# the run history (which has always said who won) is read as well when the count
# is still 0: a won run in it was an Amulet win. The history is capped, so this
# is a backfill for old saves, not a second count.
func character_amulet_wins(character_id) -> int:
	var n: int = _character_game_sum(character_id, "amulets")
	if n > 0:
		return n
	for r in runs:
		if r is Dictionary and bool(r.get("won", false)) \
				and String(r.get("character", "")) == String(character_id):
			n += 1
	return n

func _character_game_sum(character_id, field: String) -> int:
	var n: int = 0
	var games: Dictionary = character_game_log.get(String(character_id), {})
	for g in games.keys():
		n += int((games[g] as Dictionary).get(field, 0))
	return n

# EVERY distinct goal beaten playing as `character_id`, wherever it was beaten,
# grouped by kind in GOAL_KINDS order the way goals_at groups a game's:
# kind -> [{"key", "label", "done"}], sorted by label. Read from three records,
# so an older save counts what it already holds: the enemies and bosses
# (character_enemy_log), the character's own level-ups (levelup_log, which has
# always said who levelled where), and everything since character ranks
# (character_goal_log).
func character_goals(character_id) -> Dictionary:
	var c := String(character_id)
	var out: Dictionary = {}
	if c == "":
		return out
	for e in character_enemy_log.get(c, {}).keys():
		var beaten: int = int(character_enemy_log[c][e].get("beaten", 0))
		if beaten <= 0:
			continue
		var is_boss: bool = Data.get_boss(StringName(e)) != null
		var enemy: GoalEnemyData = Data.get_goal_enemy_any(StringName(e))
		_add_goal(out, "boss" if is_boss else "enemy", String(e),
			enemy.display_name if enemy != null else String(e).capitalize(), beaten, "")
	var logged: Dictionary = character_goal_log.get(c, {})
	for kind in logged.keys():
		for key in logged[kind].keys():
			var entry: Dictionary = logged[kind][key]
			_add_goal(out, String(kind), String(key), String(entry.get("label", key)),
				int(entry.get("done", 0)), "")
	# The character's own level-ups from before character_goal_log: levelup_log
	# has always kept them, so an old save's count. Once, like any goal.
	var own: int = 0
	for g in levelup_log.keys():
		var entry: Dictionary = levelup_log[g].get(c, {})
		own += int(entry.get("levels", 0)) - int(entry.get("masked", 0))
	var logged_own: bool = (logged.get("character", {}) as Dictionary).has(c)
	if own > 0 and not logged_own:
		_add_goal(out, "character", c, _character_name(c), own, "")
	var ordered: Dictionary = {}
	for kind in GOAL_KINDS:
		if out.has(kind):
			var rows: Array = out[kind]
			rows.sort_custom(func(a, b): return String(a["label"]) < String(b["label"]))
			ordered[kind] = rows
	return ordered

# One goal on `c`'s record. Enemies and bosses are character_enemy_log's, so
# they are never written here.
func _add_character_goal(c: String, kind: String, key: String, label: String) -> void:
	if c == "" or key == "" or not (kind in GOAL_KINDS) or kind == "enemy" or kind == "boss":
		return
	if not character_goal_log.has(c):
		character_goal_log[c] = {}
	if not character_goal_log[c].has(kind):
		character_goal_log[c][kind] = {}
	var entry: Dictionary = character_goal_log[c][kind].get(key, {"done": 0, "label": label})
	entry["done"] = int(entry.get("done", 0)) + 1
	if label != "":
		entry["label"] = label
	character_goal_log[c][kind][key] = entry

func _character_name(c: String) -> String:
	var ch: CharacterData = Data.get_character2(StringName(c))
	return ch.display_name if ch != null else c.capitalize()

# Shared ordering for the log lists: the biggest tally first, ties by id, so the
# panels read the same way whichever log they are drawn from.
func _sort_log(rows: Array, key: String) -> void:
	rows.sort_custom(func(a, b):
		if int(a[key]) != int(b[key]):
			return int(a[key]) > int(b[key])
		return String(a["id"]) < String(b["id"]))

func run_count() -> int:
	return runs.size()

func save_data() -> bool:
	var f := FileAccess.open(save_path(), FileAccess.WRITE)
	if f == null:
		push_error("[GameStats] could not open '%s' for write" % save_path())
		return false
	f.store_string(JSON.stringify(
		{"games": stats, "deck_wins": deck_wins, "runs": runs,
		 "enemy_log": enemy_log, "levelup_log": levelup_log,
		 "status_goal_log": status_goal_log,
		 "character_enemy_log": character_enemy_log, "goal_log": goal_log,
		 "character_game_log": character_game_log,
		 "character_goal_log": character_goal_log,
		 "donation_bank": donation_bank_total, "last_rifts": last_rifts}, "  "))
	return true

# --- the Donation Machine's bank -------------------------------------------
#
# Gold fed to a Donation Machine (docs/object-sheet-authoring.md), and the only
# number in this build that is deliberately NOT about the current run. It lives
# here rather than on GameState for exactly that reason: GameState.reset_run
# wipes the run, and a bank you can empty by starting a new one is not a bank.
#
# Isaac's works the same way, and the machine's 999 ceiling is the reason to have
# a lifetime counter at all — at a coin a time it is a number you fill over many
# runs, or blow up for pocket change in one.
var donation_bank_total: int = 0


func donation_bank() -> int:
	return donation_bank_total


# Add (or, with a negative amount, take) and persist immediately. Written on
# every coin because the alternative is losing the bank to a crash, and a bank
# that sometimes forgets is worse than no bank.
func add_to_donation_bank(amount: int) -> void:
	if amount == 0:
		return
	donation_bank_total = maxi(0, donation_bank_total + amount)
	save_data()
	changed.emit()


func load_data() -> void:
	stats = {}
	deck_wins = {}
	runs = []
	enemy_log = {}
	levelup_log = {}
	status_goal_log = {}
	character_enemy_log = {}
	character_game_log = {}
	character_goal_log = {}
	goal_log = {}
	donation_bank_total = 0
	last_rifts = []
	if not FileAccess.file_exists(save_path()):
		return
	var f := FileAccess.open(save_path(), FileAccess.READ)
	if f == null:
		return
	var json := JSON.new()
	if json.parse(f.get_as_text()) != OK or typeof(json.data) != TYPE_DICTIONARY:
		return
	# Current shape nests games under "games"; older files were the bare
	# game dictionary. Both parse — a game will never be named "games".
	if json.data.has("runs") and typeof(json.data["runs"]) == TYPE_ARRAY:
		runs = json.data["runs"]
	if json.data.has("enemy_log") and typeof(json.data["enemy_log"]) == TYPE_DICTIONARY:
		enemy_log = json.data["enemy_log"]
	# Both added after the file format existed, so an older save simply has
	# neither key and starts them empty rather than migrating.
	if json.data.has("levelup_log") and typeof(json.data["levelup_log"]) == TYPE_DICTIONARY:
		levelup_log = json.data["levelup_log"]
	if json.data.has("status_goal_log") and typeof(json.data["status_goal_log"]) == TYPE_DICTIONARY:
		status_goal_log = json.data["status_goal_log"]
	if json.data.has("character_enemy_log") and typeof(json.data["character_enemy_log"]) == TYPE_DICTIONARY:
		character_enemy_log = json.data["character_enemy_log"]
	if json.data.has("character_game_log") and typeof(json.data["character_game_log"]) == TYPE_DICTIONARY:
		character_game_log = json.data["character_game_log"]
	if json.data.has("character_goal_log") and typeof(json.data["character_goal_log"]) == TYPE_DICTIONARY:
		character_goal_log = json.data["character_goal_log"]
	if json.data.has("goal_log") and typeof(json.data["goal_log"]) == TYPE_DICTIONARY:
		goal_log = json.data["goal_log"]
	donation_bank_total = maxi(0, int(json.data.get("donation_bank", 0)))
	if typeof(json.data.get("last_rifts")) == TYPE_ARRAY:
		for id in json.data["last_rifts"]:
			last_rifts.append(String(id))
	var games: Dictionary = json.data
	if json.data.has("games") and typeof(json.data["games"]) == TYPE_DICTIONARY:
		games = json.data["games"]
		var dw = json.data.get("deck_wins", {})
		if typeof(dw) == TYPE_DICTIONARY:
			for ck in dw.keys():
				if typeof(dw[ck]) == TYPE_ARRAY:
					var ids: Array = []
					for d in dw[ck]:
						ids.append(String(d))
					deck_wins[String(ck)] = ids
	for k in games.keys():
		var r: Dictionary = games[k]
		stats[String(k)] = {
			"beaten": int(r.get("beaten", 0)),
			"amulets": int(r.get("amulets", 0)),
			"rifts": int(r.get("rifts", 0)),
			# Kept since game ranks (§20.1) count it. It used to be dropped here,
			# so every perfect was forgotten the next time the file loaded.
			"perfects": int(r.get("perfects", 0)),
		}
