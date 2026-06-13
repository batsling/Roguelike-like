extends Node

# Cross-run tier list / ranking store. UNLIKE SaveSystem (which is per-run),
# this lives in a single global file that survives every run, so the player's
# scores, notes and tier placements accumulate across the whole game the way
# Settings.cfg does for preferences.
#
# Persisted shape (user://tier_list.json):
#   {
#     "tier_names": ["S","A","B","C","D","F"],   # editable labels, ordered
#     "tiers": [["hades", ...], ...],             # one game-id list per tier
#     "unranked": ["slay_the_spire", ...],        # beaten-but-unplaced games
#     "ratings": { "hades": {"score": 9, "notes": "..."} }
#   }
#
# A game id appears in exactly one place — a tier row OR the unranked tray.
# set_rating() is the entry point used when a game is beaten; it records the
# score/notes and makes sure the game is present (dropping it into Unranked the
# first time so the player can drag it onto a tier).

signal changed

const SAVE_PATH := "user://tier_list.json"

const DEFAULT_TIER_NAMES: Array[String] = ["S", "A", "B", "C", "D", "F"]

var tier_names: Array[String] = []
# tiers[i] is the ordered list of game-id Strings placed in tier i.
var tiers: Array = []
var unranked: Array = []
# game-id String -> {"score": int, "notes": String}
var ratings: Dictionary = {}

func _ready() -> void:
	load_data()

# ---------------------------------------------------------------------------
# Ratings
# ---------------------------------------------------------------------------

func has_rating(id) -> bool:
	return ratings.has(String(id))

# Returns {"score": int, "notes": String}, or {} when the game is unrated.
func get_rating(id) -> Dictionary:
	var key := String(id)
	if not ratings.has(key):
		return {}
	return ratings[key]

# Records a 1-10 score and notes for a game and ensures it's on the board.
# Used both by the post-victory prompt and the tier-list screen's editor.
func set_rating(id, score: int, notes: String) -> void:
	var key := String(id)
	ratings[key] = {"score": clampi(score, 1, 10), "notes": notes}
	ensure_present(key)
	save_data()
	emit_signal("changed")

# ---------------------------------------------------------------------------
# Placement
# ---------------------------------------------------------------------------

# Drops a freshly-beaten game into the Unranked tray if it isn't already placed
# somewhere. Does not save on its own — callers that mutate (set_rating) save.
func ensure_present(id) -> void:
	var key := String(id)
	if tier_of(key) != -1 or unranked.has(key):
		return
	unranked.append(key)

# Returns the tier index the game sits in, or -1 if it's unranked/absent.
func tier_of(id) -> int:
	var key := String(id)
	for i in tiers.size():
		if (tiers[i] as Array).has(key):
			return i
	return -1

# Moves a game onto a tier (target_tier 0..n-1) or the Unranked tray
# (target_tier == -1). insert_at < 0 appends; otherwise the game is inserted at
# that position, enabling reordering within a row.
func place(id, target_tier: int, insert_at: int = -1) -> void:
	var key := String(id)
	_remove_from_all(key)
	var dest: Array
	if target_tier < 0 or target_tier >= tiers.size():
		dest = unranked
	else:
		dest = tiers[target_tier]
	if insert_at < 0 or insert_at > dest.size():
		dest.append(key)
	else:
		dest.insert(insert_at, key)
	save_data()
	emit_signal("changed")

func _remove_from_all(key: String) -> void:
	unranked.erase(key)
	for row in tiers:
		(row as Array).erase(key)

# ---------------------------------------------------------------------------
# Tier names
# ---------------------------------------------------------------------------

func set_tier_name(index: int, new_name: String) -> void:
	if index < 0 or index >= tier_names.size():
		return
	var trimmed := new_name.strip_edges()
	tier_names[index] = trimmed if trimmed != "" else DEFAULT_TIER_NAMES[index % DEFAULT_TIER_NAMES.size()]
	save_data()
	emit_signal("changed")

# ---------------------------------------------------------------------------
# Persistence
# ---------------------------------------------------------------------------

func save_data() -> bool:
	var payload := {
		"tier_names": tier_names.duplicate(),
		"tiers": _duplicate_rows(),
		"unranked": unranked.duplicate(),
		"ratings": ratings.duplicate(true),
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_error("[TierList] could not open '%s' for write" % SAVE_PATH)
		return false
	f.store_string(JSON.stringify(payload, "  "))
	return true

func load_data() -> void:
	_reset_defaults()
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var json := JSON.new()
	if json.parse(f.get_as_text()) != OK or typeof(json.data) != TYPE_DICTIONARY:
		return
	var data: Dictionary = json.data

	var names: Array = data.get("tier_names", [])
	if names.size() > 0:
		tier_names = []
		for n in names:
			tier_names.append(String(n))

	# Rebuild the per-tier rows, padding/truncating to match tier_names so the
	# two stay in lockstep even if the file was hand-edited.
	tiers = []
	var saved_tiers: Array = data.get("tiers", [])
	for i in tier_names.size():
		var row: Array = []
		if i < saved_tiers.size() and saved_tiers[i] is Array:
			for g in saved_tiers[i]:
				row.append(String(g))
		tiers.append(row)

	unranked = []
	for g in data.get("unranked", []):
		unranked.append(String(g))

	ratings = {}
	var saved_ratings: Dictionary = data.get("ratings", {})
	for k in saved_ratings.keys():
		var r: Dictionary = saved_ratings[k]
		ratings[String(k)] = {
			"score": clampi(int(r.get("score", 1)), 1, 10),
			"notes": String(r.get("notes", "")),
		}

func _reset_defaults() -> void:
	tier_names = DEFAULT_TIER_NAMES.duplicate()
	tiers = []
	for _i in tier_names.size():
		tiers.append([])
	unranked = []
	ratings = {}

func _duplicate_rows() -> Array:
	var out: Array = []
	for row in tiers:
		out.append((row as Array).duplicate())
	return out
