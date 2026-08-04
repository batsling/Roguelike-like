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
#   { "games": { "hades": {"beaten": 3, "amulets": 1}, ... },
#     "deck_wins": { "ironclad": ["Random", "Silent"], ... },
#     "enemy_log": { "<game>": { "<enemy>": {"beaten": 2, "note": "…"} } },
#     "levelup_log": { "<game>": { "<character>": {"levels": 1, "note": "…"} } },
#     "character_enemy_log": { "<character>": { "<enemy>": {"beaten": 4} } } }
# (Older files were the bare games dictionary; load_data migrates them, and a
# file predating any of the three logs just starts that log empty.)

signal changed

const SAVE_PATH := "user://game_stats.json"

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

# Which goal-enemies each CHARACTER has beaten, across every run and every game
# they were beaten at. Keyed character id -> enemy id -> {"beaten": int}.
#
# Deliberately not keyed by game as well: this is the character's own trophy
# shelf, the roster-side counterpart to "enemies beaten in <game>". Which game
# each fell at is already in enemy_log.
var character_enemy_log: Dictionary = {}

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

func beaten_count(id) -> int:
	return int(get_stats(id).get("beaten", 0))

func amulet_wins(id) -> int:
	return int(get_stats(id).get("amulets", 0))

# Deck ids (DeckCatalog) this character has won at least one run with.
func deck_wins_for(character_id) -> Array:
	return deck_wins.get(String(character_id), [])

func has_deck_win(character_id, deck_id) -> bool:
	return String(deck_id) in deck_wins_for(character_id)

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

# Records a run win for a (character, deck) pair. Idempotent — the checklist
# only cares that the pair was won at least once.
func record_deck_win(character_id, deck_id) -> void:
	var ck := String(character_id)
	var dk := String(deck_id)
	if ck == "" or dk == "":
		return
	if not deck_wins.has(ck):
		deck_wins[ck] = []
	if dk in deck_wins[ck]:
		return
	deck_wins[ck].append(dk)
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
	for id in GameState.visited_games:
		path.append(String(id))
	var current := String(GameState.current_game_id)
	if current != "" and (path.is_empty() or String(path[path.size() - 1]) != current):
		path.append(current)
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

func has_enemy_log(game_id) -> bool:
	return not enemy_log.get(String(game_id), {}).is_empty()

# ---------------------------------------------------------------------------
# Level-ups: the (game, character) pair, mirroring enemy_log
# ---------------------------------------------------------------------------

# Record that `character_id` levelled up while playing `game_id`. One call per
# level gained, so a Crown-chained double level counts twice.
func record_level_up(game_id, character_id) -> void:
	var g := String(game_id)
	var c := String(character_id)
	if g == "" or c == "":
		return
	if not levelup_log.has(g):
		levelup_log[g] = {}
	var entry: Dictionary = levelup_log[g].get(c, {"levels": 0, "note": ""})
	entry["levels"] = int(entry.get("levels", 0)) + 1
	levelup_log[g][c] = entry
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

# The inverse: every GAME this character has levelled up at. Drives the
# character detail.
func games_for_character(character_id) -> Array:
	var target := String(character_id)
	var out: Array = []
	for g in levelup_log.keys():
		var entry: Dictionary = levelup_log[g].get(target, {})
		if entry.is_empty():
			continue
		if int(entry.get("levels", 0)) <= 0 and String(entry.get("note", "")).strip_edges() == "":
			continue
		out.append({"id": String(g), "levels": int(entry.get("levels", 0)),
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
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_error("[GameStats] could not open '%s' for write" % SAVE_PATH)
		return false
	f.store_string(JSON.stringify(
		{"games": stats, "deck_wins": deck_wins, "runs": runs,
		 "enemy_log": enemy_log, "levelup_log": levelup_log,
		 "character_enemy_log": character_enemy_log}, "  "))
	return true

func load_data() -> void:
	stats = {}
	deck_wins = {}
	runs = []
	enemy_log = {}
	levelup_log = {}
	character_enemy_log = {}
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
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
	if json.data.has("character_enemy_log") and typeof(json.data["character_enemy_log"]) == TYPE_DICTIONARY:
		character_enemy_log = json.data["character_enemy_log"]
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
		}
