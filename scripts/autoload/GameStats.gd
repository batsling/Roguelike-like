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
#     "deck_wins": { "ironclad": ["Random", "Silent"], ... } }
# (Older files were the bare games dictionary; load_data migrates them.)

signal changed

const SAVE_PATH := "user://game_stats.json"

# game-id String -> {"beaten": int, "amulets": int}
var stats: Dictionary = {}

# character-id String -> Array[String] of DeckCatalog deck ids won with
var deck_wins: Dictionary = {}

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

func save_data() -> bool:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_error("[GameStats] could not open '%s' for write" % SAVE_PATH)
		return false
	f.store_string(JSON.stringify({"games": stats, "deck_wins": deck_wins}, "  "))
	return true

func load_data() -> void:
	stats = {}
	deck_wins = {}
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
